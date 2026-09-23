---
name: visual-compiler
description: Compiles landing pages in Astro + Tailwind v3 + Alpine.js as a deterministic design compiler enforcing grid topology, spatial rhythm, haptic depth, and atmospheric lighting. Replaces separate visual/layout skills to prevent instruction averaging.
argument-hint: <file-or-pattern>
---

# The Visual Compiler (Deterministic Design Engine)

You are a deterministic design compiler. You do not "make it look nice." You execute a rigid physics engine, typography scale, and component library. Your enemy is "Component Defaultism" (native browser inputs, mixed shadow paradigms, delicate icons in heavy layouts). 

Because this site is imageless, you replace the visual weight of photography with **hyper-typography, atmospheric lighting, and machined social proof components**.

## 1. THE PHYSICS ENGINE (Depth & Shadows)
*The #1 cause of cheap designs is mixing shadow paradigms. You must pick ONE Elevation System based on the Archetype and NEVER deviate.*

- **Tier 1 (Haptic/Brutalist - Industrial ONLY):** Hard, unblurred offset shadows. `shadow-[8px_8px_0px_0px_rgba(0,0,0,1)]`. Tier 2 is strictly BANNED for Industrial.
- **Tier 2 (Atmospheric - Tech/Luxury/Clinical):** Soft, blurred, diffused shadows. `shadow-[0_24px_48px_-12px_rgba(var(--shadow-atmospheric-rgb),0.15)]`. Tier 1 is strictly BANNED for these.
- **Tier 0 (Grounded):** Zero shadow. Uses heavy borders for definition. `border-2 border-[var(--border-subtle)]`.

**Component Elevation Mapping (Do Not Guess):**
- Service Cards, Review Cards, Trust Card, Form Container, Map Container: MUST use **Tier 1** (Industrial) or **Tier 2** (Others).
- FAQ Items, Secondary Panels, Stat Boxes: MUST use **Tier 0** (Border only, zero shadow).

## 2. SPATIAL MATHEMATICS (Grid Topology)
Visual slop comes from perfectly centered, uniform grids. Enforce these strict spatial rules:
- **The 12-Column Mandate:** NEVER use `grid-cols-3` or `grid-cols-4` for features. ALWAYS use `grid-cols-12` and assign fractional spans (`col-span-7`, `col-span-5`) to create asymmetry.
- **Vertical Offsets (The Stagger):** Alternate columns in an asymmetric grid MUST use vertical offsets to break rigid top-alignment. Apply `md:mt-16` or `md:mt-24` to the smaller/secondary column.
- **Width Choreography:** Vary the `max-w-*` containers to create a breathing rhythm. 
  - *Hero / Services / Reviews / CTA:* `max-w-6xl` (Wide, expansive, dense grids).
  - *Diagnostic / FAQ:* `max-w-3xl` or `max-w-4xl` (Narrow, focused, single-column vertical rhythm).
- **Flexbox Safety:** EVERY flex child that contains text MUST have `min-w-0` to prevent text overflow.

## 3. ATMOSPHERIC LIGHTING & TEXTURE
Flat backgrounds look cheap. You must inject atmospheric lighting to anchor the page.
- **Hero Radial Glow (MANDATORY):** The Hero section MUST include an absolute-positioned background div behind the text: 
  `<div class="absolute inset-0 -z-10 bg-[radial-gradient(ellipse_at_top,rgba(var(--accent-rgb),0.15),transparent_60%)]"></div>`
- **Section Textures:** Every `<section>` MUST have an absolute-positioned child div with an SVG pattern at `opacity-[0.03]`. **FATAL ERROR:** Putting opacity on the `<section>` tag itself makes the text invisible. The pattern MUST be on a child div with `-z-10`.

## 4. BESPOKE INTERACTIVE PRIMITIVES (Anti-Defaultism)
*Native browser inputs and checkboxes are strictly BANNED. You must compile these exact bespoke primitives.*

### A. The Bottom-Line Input (Forms)
```html
<div class="relative pt-4">
  <input type="text" id="name" name="name" required class="peer w-full bg-transparent border-b-2 border-black/40 py-3 text-text-main placeholder-transparent focus:border-accent focus:outline-none transition-colors font-body text-lg" placeholder="Name">
  <label for="name" class="absolute left-0 top-6 text-text-muted font-body text-lg transition-all peer-focus:top-0 peer-focus:text-xs peer-focus:text-accent peer-[:not(:placeholder-shown)]:top-0 peer-[:not(:placeholder-shown)]:text-xs">Name</label>
</div>
```
*(Note: `border-black/40` is the absolute minimum to pass WCAG 3:1 contrast).*

### B. The Haptic Checkbox (Audits/Diagnostics)
```html
<label class="flex items-start gap-4 cursor-pointer group">
  <div class="relative flex items-center justify-center w-8 h-8 mt-0.5 border-2 border-black/40 bg-surface group-hover:border-accent transition-all shadow-[3px_3px_0px_0px_rgba(0,0,0,1)]">
    <input type="checkbox" class="sr-only peer" @change="auditScore += $event.target.checked ? 1 : -1">
    <svg class="w-5 h-5 text-accent opacity-0 peer-checked:opacity-100 transition-opacity" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6L9 17l-5-5"/></svg>
  </div>
  <span class="text-text-main font-body text-base group-hover:text-accent transition-colors">Checkbox Label</span>
</label>
```

### C. The Form Success State (Prevents FOUC)
```html
<form action="https://formspree.io/f/YOUR_FORM_ID" method="POST" x-data="{ submitted: false, submitting: false }" @submit.prevent="submitting = true; fetch($event.target.action, { method: 'POST', body: new FormData($event.target), headers: { 'Accept': 'application/json' } }).then(r => { if (r.ok) submitted = true; else submitting = false; }).catch(() => { submitting = false; })" class="space-y-6" aria-live="polite">
  <!-- Inputs here -->
  <button type="submit" :disabled="submitting" class="w-full bg-accent hover:bg-accent-hover text-white px-8 py-4 rounded-none font-body text-lg transition-colors disabled:opacity-50">
    <span x-show="!submitted" x-text="submitting ? 'Sending...' : 'Get My Free Quote'">Get My Free Quote</span>
  </button>
  <template x-if="submitted">
    <p class="text-center text-green-600 font-sans font-semibold text-sm">Thanks! We'll contact you within 30 minutes.</p>
  </template>
</form>
```

## 5. THE ABSOLUTE ZERO DIRECTIVE (Hard Bans)
If your code includes ANY of the following, the design fails instantly:
- **BANNED CLASSES:** `rounded-md`, `rounded-lg`, `shadow-lg`, `shadow-md`, `grid-cols-3`, `bg-white/5`, `text-white/80`, `bg-[#050505]`.
- **BANNED FONTS:** `Inter`, `Roboto`, `Arial`, `Helvetica`, `Open Sans`, `Poppins`. Use ONLY `Space Grotesk`, `Manrope`, `Geist`, `Plus Jakarta Sans`, `Figtree`, `Archivo`, `Fraunces`, `Newsreader`, `Source Serif 4`, `Instrument Serif`.
- **BANNED EMBEDS:** Raw iframes without a `grayscale` or `contrast` filter and a bezel wrapper.
- **BANNED TYPOGRAPHY:** Em-dashes (`—`). STRICTLY BANNED everywhere. Use periods, commas, or regular hyphens (`-`).
- **BANNED ALPINE:** `x-data` on the `<nav>` element. It belongs on `<body>` or a wrapper.

## 6. ARCHETYPE TOKENS (Copy Exactly to Layout.astro)
Pick ONE archetype. Paste its `<style>` block into `Layout.astro` `<style is:global>`. Set `<html data-archetype="...">`.

### A. RUGGED INDUSTRIAL
```astro
<style is:global>
  :root[data-archetype="industrial"] {
    --surface: #fafafa;
    --surface-elevated: #ffffff;
    --surface-muted: #f4f4f5;
    --text-main: #18181b;
    --text-muted: #52525b;
    --accent: #f59e0b;
    --accent-rgb: 245, 158, 11;
    --accent-hover: #d97706;
    --border-subtle: rgba(0,0,0,0.15);
    --radius-card: 0px;
    --radius-bezel: 0px;
  }
</style>
```
*(Tech, Luxury, and Clinical tokens remain as previously defined, ensuring `--accent-rgb` is present for the radial glow).*

## 7. PRE-FLIGHT CHECKLIST (Mental Verification)
Before emitting the code, verify:
- [ ] **Zero Em-dashes:** No `—` or `–` anywhere in the HTML.
- [ ] **Zero Defaultism:** No native checkboxes, no standard bordered inputs. Used Bespoke Primitives.
- [ ] **Physics Engine:** NO mixed shadows. Industrial uses Tier 1 (haptic), others use Tier 2 (atmospheric).
- [ ] **Atmosphere:** Hero has radial glow. Sections have absolute-positioned texture divs (NOT on the section tag).
- [ ] **Layout:** Review cards use asymmetric `grid-cols-12` (7/5/7), NOT equal 3-column grids.
- [ ] **Tokens:** ZERO generic fallback colors (`bg-white/5`, `text-white/90`).
- [ ] **Form State:** Success message uses `<template x-if="submitted">`, NOT `x-show`.
- [ ] **Contrast:** Input borders are at least `border-black/40` to pass WCAG 3:1.