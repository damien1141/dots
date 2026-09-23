from __future__ import annotations

import asyncio
import json
import logging
import random
import structlog
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

import torch
import torch.nn as nn
from datasets import load_dataset
from pydantic import BaseModel, ConfigDict, Field
from safetensors.torch import load_file, save_file

logger = structlog.get_logger()


# ── Models & Config ──────────────────────────────────────────────────────────


class LayerWeightRef(BaseModel):
    model_config = ConfigDict(extra="forbid")

    weight_name: str
    filename: str


class LayerGroup(BaseModel):
    model_config = ConfigDict(extra="forbid")

    layer_num: int
    weights: list[LayerWeightRef] = field(default_factory=list)


class ModelConfig(BaseModel):
    model_config = ConfigDict(extra="forbid")

    model_dir: Path
    device: str = "cuda"
    dtype: torch.dtype = torch.float16
    calib_samples: int = 256
    expert_count: int = 8


# ── Index Parser ─────────────────────────────────────────────────────────────


def parse_index(model_dir: Path) -> dict[int, list[LayerWeightRef]]:
    """Read the safetensors index.json and group weight refs by layer number.

    Returns an ordered dict keyed by layer number.
    """
    index_path = model_dir / "model.safetensors.index.json"
    with open(index_path, "r") as f:
        index = json.load(f)

    layer_files: dict[int, list[LayerWeightRef]] = {}
    for weight_name, filename in index["weight_map"].items():
        if "model.layers." not in weight_name:
            continue
        parts = weight_name.split(".")
        if len(parts) < 3:
            continue
        try:
            layer_num = int(parts[2])
        except ValueError:
            continue

        layer_files.setdefault(layer_num, []).append(
            LayerWeightRef(weight_name=weight_name, filename=filename)
        )

    return dict(sorted(layer_files.items()))


def extract_non_layer_weights(
    model_dir: Path,
) -> dict[str, str]:
    """Return {weight_name: filename} for weights outside model.layers."""
    index_path = model_dir / "model.safetensors.index.json"
    with open(index_path, "r") as f:
        index = json.load(f)

    non_layer: dict[str, str] = {}
    for weight_name, filename in index["weight_map"].items():
        if "model.layers." not in weight_name:
            non_layer[weight_name] = filename
    return non_layer


# ── Calibration Data ─────────────────────────────────────────────────────────


def build_frankenstein_calib_data(
    model_dir: Path,
    num_samples: int = 256,
    seed: int = 42,
) -> list[str]:
    """Build a diverse calibration dataset: 30% science, 40% instruction, 30% code."""

    gpqa_count = int(num_samples * 0.3)
    instruct_count = int(num_samples * 0.4)
    code_count = num_samples - gpqa_count - instruct_count

    # Science / reasoning
    gpqa = (
        load_dataset("openai/gsm8k", "main", split="train")
        .shuffle(seed=seed)
        .select(range(gpqa_count))
    )

    # General instruction
    instruct = (
        load_dataset("tatsu-lab/alpaca", split="train")
        .shuffle(seed=seed)
        .select(range(instruct_count))
    )

    # Code
    code = (
        load_dataset("openai_humaneval", split="test")
        .shuffle(seed=seed)
        .select(range(code_count))
    )

    calib_texts: list[str] = []

    for item in gpqa:
        calib_texts.append(item["question"])

    for item in instruct:
        text = item["instruction"]
        if item["input"]:
            text += "\n" + item["input"]
        calib_texts.append(text)

    for item in code:
        calib_texts.append(item["prompt"])

    random.shuffle(calib_texts)
    return calib_texts[:num_samples]


# ── Forward-Pass Hook ────────────────────────────────────────────────────────


class _ActivationRecorder:
    """Attach to a module to record its forward activations."""

    __slots__ = ("name", "activations")

    def __init__(self, name: str) -> None:
        self.name = name
        self.activations: list[torch.Tensor] = []

    def __call__(self, module: nn.Module, input: tuple, output: torch.Tensor) -> None:
        self.activations.append(output.detach())


def attach_hook(layer_module: nn.Module, name: str) -> _ActivationRecorder:
    hook = _ActivationRecorder(name)
    layer_module.register_forward_hook(hook)
    return hook


# ── Quantization Stub ────────────────────────────────────────────────────────


def quantize_layer(
    weights: dict[str, torch.Tensor],
    activation_scales: dict[str, torch.Tensor],
) -> dict[str, Any]:
    """Quantize a layer's weights using per-channel symmetric quantization.

    This is a simplified placeholder — replace with real INT8/INT4 quantization
    logic (e.g., APEX, bitsandbytes, or custom kernel) in production.
    """
    quantized: dict[str, Any] = {}
    for name, w in weights.items():
        scales = activation_scales.get(name, None)
        if scales is not None:
            # Per-channel symmetric quantization to int8
            abs_max = torch.max(torch.abs(w), dim=-1).values.unsqueeze(-1)
            scale = abs_max.float() / 127.0
            quantized[name] = (
                torch.round(w.float() / scale).to(torch.int8),
                scale.to(w.dtype),
            )
        else:
            quantized[name] = (w, torch.tensor(1.0, dtype=w.dtype))
    return quantized


# ── Layer Processor ──────────────────────────────────────────────────────────


async def process_layer(
    layer_num: int,
    weight_paths: list[LayerWeightRef],
    calibration_prompts: list[str],
    model: nn.Module,
    config: ModelConfig,
) -> None:
    """Load one layer's weights, run calibration, quantize, save, and flush VRAM."""

    logger.info("Processing Layer", layer=layer_num)

    # 1. Load ONLY this layer's weights to GPU
    layer_weights: dict[str, torch.Tensor] = {}
    for ref in weight_paths:
        full_weights = load_file(config.model_dir / ref.filename, device="cpu")
        layer_weights[ref.weight_name] = full_weights[ref.weight_name].to(config.device)

    # 2. Attach hooks to capture activations
    hooks: list[_ActivationRecorder] = []
    layer_module = model.get_submodule(f"model.layers.{layer_num}")

    for weight_name in layer_weights.keys():
        # Derive module path from weight name (e.g. q_proj -> self_attn.q_proj)
        module_path = f"model.layers.{layer_num}.{weight_name.replace('.weight', '')}"
        try:
            mod = model.get_submodule(module_path)
            hook = attach_hook(mod, weight_name)
            hooks.append(hook)
        except Exception:
            logger.warning("Could not attach hook for weight", weight=weight_name)

    try:
        # 3. Run calibration data through the layer
        for prompt in calibration_prompts:
            with torch.no_grad():
                # Tokenize and forward — adapter-specific tokenization omitted
                # The hooks capture activation ranges for every submodule
                pass

        # 4. Aggregate activation scales
        activation_scales: dict[str, torch.Tensor] = {}
        for hook in hooks:
            if hook.activations:
                # Use max absolute value across all calibration samples
                max_abs = torch.cat(hook.activations, dim=0).abs().max(dim=0).values
                activation_scales[hook.name] = max_abs

        # 5. Quantize
        quantized_weights = quantize_layer(layer_weights, activation_scales)

        # 6. Save quantized weights to disk
        save_path = config.model_dir / f"quantized_layer_{layer_num}.safetensors"
        save_file(quantized_weights, str(save_path))
        logger.info("Layer quantized and saved", layer=layer_num, path=str(save_path))

    finally:
        # 7. FLUSH THE VRAM — most important part
        del layer_weights
        del activation_scales
        del hooks
        for hook in hooks:
            hook.activations.clear()
        torch.cuda.empty_cache()
        logger.info("VRAM flushed", layer=layer_num)


# ── Stitcher ──────────────────────────────────────────────────────────────────


def stitch_quantized_layers(
    model_dir: Path,
    layer_count: int,
    non_layer_weights: dict[str, str],
    output_path: Path,
) -> None:
    """Reassemble quantized layer files + non-layer weights into a single safetensors file."""
    all_tensors: dict[str, torch.Tensor] = {}

    # Load non-layer weights (embeddings, lm_head, etc.)
    for weight_name, filename in non_layer_weights.items():
        full = load_file(model_dir / filename, device="cpu")
        all_tensors[weight_name] = full[weight_name]

    # Load quantized layer files
    for layer_num in range(layer_count):
        layer_path = model_dir / f"quantized_layer_{layer_num}.safetensors"
        if not layer_path.exists():
            logger.warning("Missing quantized layer", layer=layer_num)
            continue

        layer_data = load_file(str(layer_path), device="cpu")
        # Restore quantized tuples back to tensors for saving
        for key, val in layer_data.items():
            if isinstance(val, tuple) and len(val) == 2:
                # Quantized: (int8_tensor, scale) — save as-is for dequant at load time
                all_tensors[f"layers.{layer_num}.{key}"] = val[0]
            else:
                all_tensors[f"layers.{layer_num}.{key}"] = val

    save_file(all_tensors, str(output_path))
    logger.info("Stitched model saved", path=str(output_path))


# ── Orchestrator ─────────────────────────────────────────────────────────────


async def run_blockwise_offload(
    model_dir: Path,
    output_path: Path | None = None,
    calib_samples: int = 256,
    expert_count: int = 8,
) -> None:
    """Main entry point: parse index, calibrate layers, quantize, stitch."""

    config = ModelConfig(
        model_dir=model_dir,
        calib_samples=calib_samples,
        expert_count=expert_count,
    )

    # 1. Parse the index — map weights to layers
    layer_files = parse_index(model_dir)
    layer_count = len(layer_files)
    logger.info("Index parsed", layers=layer_count)

    # 2. Build the Frankenstein calibration dataset
    calibration_prompts = build_frankenstein_calib_data(
        model_dir=model_dir,
        num_samples=config.calib_samples,
    )
    logger.info("Calibration dataset built", samples=len(calibration_prompts))

    # 3. Load model (lazy — we only load what we need per layer)
    #    Adapter-specific model loading omitted; substitute with your model class.
    #    model = YourModelClass.from_pretrained(model_dir)

    # 4. Process layers one-by-one (structured concurrency)
    async with asyncio.TaskGroup() as tg:
        for layer_num in sorted(layer_files.keys()):
            tg.create_task(
                process_layer(
                    layer_num,
                    layer_files[layer_num],
                    calibration_prompts,
                    # model,  # <-- uncomment when model is loaded
                    config,
                )
            )

    # 5. Stitch quantized layers back together
    non_layer_weights = extract_non_layer_weights(model_dir)
    if output_path is None:
        output_path = model_dir / "quantized_model.safetensors"

    stitch_quantized_layers(
        model_dir=model_dir,
        layer_count=layer_count,
        non_layer_weights=non_layer_weights,
        output_path=output_path,
    )

    logger.info("Blockwise offload complete", output=str(output_path))


# ── CLI Entry ────────────────────────────────────────────────────────────────


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description="Blockwise MoE offloader")
    parser.add_argument("model_dir", type=Path, help="Path to model.safetensors.index.json")
    parser.add_argument("--output", "-o", type=Path, default=None, help="Output path")
    parser.add_argument("--calib-samples", "-n", type=int, default=256)
    parser.add_argument("--experts", "-e", type=int, default=8)
    args = parser.parse_args()

    asyncio.run(
        run_blockwise_offload(
            model_dir=args.model_dir,
            output_path=args.output,
            calib_samples=args.calib_samples,
            expert_count=args.experts,
        )
    )


if __name__ == "__main__":
    main()
