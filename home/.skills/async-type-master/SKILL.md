---
name: async-type-master
description: "Blockwise per-layer int8 quantization for MoE/LLM safetensors models. Use when shrinking a checkpoint to fit VRAM, offloading weights layer-by-layer, or stitching quantized weights into one checkpoint. Trigger: quantize model, blockwise offload, int8 safetensors, VRAM-efficient quant, stitch quantized weights."
argument-hint: <model_dir>
---

## What this does

`blockwise_offloader.py` is a **blockwise quantization pipeline**. It compresses a
safetensors LLM/MoE checkpoint to int8 by processing one transformer layer at a
time, so only a single layer's weights touch GPU memory at once. Output is a
reassembled `quantized_model.safetensors`.

Pipeline:

1. **Parse index** — read `model.safetensors.index.json`, group `weight_map` by layer number.
2. **Calibrate** — build a "Frankenstein" dataset (30% science/GSM8K, 40% instruction/Alpaca, 30% code/HumanEval) to capture real activation ranges.
3. **Per-layer process** — for each layer: load only its weights → attach forward hooks → run calibration → compute per-channel symmetric quantization scales → save `quantized_layer_<n>.safetensors` → **flush VRAM**.
4. **Stitch** — reassemble per-layer quantized files + non-layer weights (embeddings, `lm_head`) into one checkpoint.

## When to use

- Fitting a large safetensors checkpoint into limited VRAM via int8.
- Quantizing MoE models where full-model quantization OOMs.
- Producing a single dequantizable checkpoint for later inference.

## Requirements

- `torch` (with CUDA), `datasets`, `safetensors`, `structlog`, `pydantic`.
- A real safetensors checkpoint with `model.safetensors.index.json`.
- Enough VRAM for **one layer** at a time, not the full model.

## How to run

```bash
python blockwise_offloader.py <model_dir> \
  --output <out.safetensors> \   # -o ; default: <model_dir>/quantized_model.safetensors
  --calib-samples 256 \          # -n ; calibration samples per domain mix
  --experts 8                    # -e ; MoE expert count for the pipeline
```

`<model_dir>` is the folder containing `model.safetensors.index.json`.

## Pipeline stages (what each step is responsible for)

- **Calibration data** — `build_frankenstein_calib_data` mixes three domains so
  activation scales span reasoning, instruction, and code. Adjust the split in the
  function if your model's workload is skewed (e.g. code-only → weight HumanEval higher).
- **Activation capture** — `attach_hook` records forward outputs; max-abs across
  samples becomes the per-channel quantization scale.
- **Quantization** — `quantize_layer` does per-channel symmetric int8.
- **VRAM discipline** — `process_layer` deletes all per-layer tensors and calls
  `torch.cuda.empty_cache()` after each layer. This is the load-bearing step for
  the OOM-avoidance promise; never remove the `finally` block.

## Honest gaps (fill before production use)

The script is a **structural skeleton** — several stages are explicit placeholders:

- **Tokenization is omitted.** Calibration prompts are generated but never
  tokenized or forwarded (`# adapter-specific tokenization omitted`). Wire in your
  model's tokenizer + a forward pass so the hooks actually see activations.
- **Model loading is omitted.** `run_blockwise_offload` never instantiates the
  model (`# substitute with your model class`). Load the real `nn.Module` so
  `model.get_submodule(...)` resolves and hooks attach.
- **Quantization is a placeholder.** `quantize_layer` is a simplified per-channel
  int8 — swap in a real kernel (APEX, bitsandbytes, or a custom kernel) for
  correctness/perf on production models.

Do not treat the committed output as numerically final until those three are wired.

## Verification

- After a run, check `quantized_layer_*.safetensors` exist per layer and the final
  `quantized_model.safetensors` reassembles without missing-layer warnings.
- Sanity-check one layer dequantizes back to roughly its original magnitude
  (per-channel scales preserved) before trusting the full checkpoint.
