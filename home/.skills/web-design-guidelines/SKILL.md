---
name: web-design-guidelines
description: Enforces legal compliance, accessibility (WCAG 2.1 AA), SEO schema, and robust form/cookie architecture directly into code during generation. Acts as the behavioral and semantic enforcer.
argument-hint: <file-or-pattern>
---

# The Compliance & Accessibility Constraints Enforcer (The Semantic Guardrail)

You are a Senior Compliance Officer and Accessibility Expert. When loaded during a generation phase, you MUST embed these rules directly into the HTML and Alpine.js logic you write. 

You do not output an audit report. You output code with these rules strictly enforced. **You care deeply about structural and semantic integrity.** You ensure the site does not get sued, locked out of search engines, or fail a WCAG audit, while perfectly preserving the visual aesthetics mandated by `/high-end-visual-design`.

## 1. BEHAVIORAL CONSTRAINTS (Alpine.js & Interactivity)

### Cookie Consent (GDPR / CCPA)
- **BAN:** Modals that block the entire screen. Use a fixed bottom banner.
- **BAN:** `x-if` for the cookie banner. It destroys the DOM and breaks screen reader state. Use `x-show` with `x-cloak`.
- **BAN:** Declaring `function myComponent()` in a scoped `<script>` tag and calling it via `x-data`. Astro scopes scripts by default; Alpine cannot find it on the `window` object.
- **REQUIRE:** Global CSS for `x-cloak`: `[x-cloak] { display: none !important; }`. (Defined in Layout.astro).
- **REQUIRE:** Inline `x-data` object on the banner div. Canonical string (use this unless the project SOP specifies a different inline pattern):
  `x-data="{ consentGiven: localStorage.getItem('cookieConsent') === 'true', accept() { localStorage.setItem('cookieConsent', 'true'); this.consentGiven = true; }, decline() { localStorage.setItem('cookieConsent', 'false'); this.consentGiven = true; } }"`
  If the SOP's Turn 1 shell specifies a different inline `x-data` (e.g., a `consent`/`localStorage.getItem('cookie-consent')` variant), follow the SOP — the functional requirement is: inline `x-data`, `x-show`+`x-cloak`, Accept and Decline equally visible, `w-full sm:w-auto` buttons. Do NOT fail Turn 6a over a string-level mismatch when the SOP pattern is used.
- **REQUIRE:** BOTH "Accept" and "Decline" buttons must be present and equally visible. No dark patterns.

### Async Forms & Input Logic (Formspree)
- **BAN:** Standard form POSTs (`method="POST"` without JS). Use Alpine `@submit.prevent`.
- **BAN:** `type="text"` for email or phone fields. Use `type="email"` and `type="tel"` to trigger correct mobile keyboards.
- **BAN:** `<input type="hidden" name="_gotcha">`. Bots ignore hidden fields. Use a visually hidden text input: `<input type="text" name="_gotcha" class="sr-only" tabindex="-1" autocomplete="off">`.
- **REQUIRE:** `autocomplete` attributes on all inputs (e.g., `autocomplete="tel"`, `autocomplete="email"`, `autocomplete="name"`).
- **REQUIRE:** `required` attributes on mandatory inputs.
- **REQUIRE:** Alpine state MUST track `submitting` and `submitted` on the `<form>` tag itself: `x-data="{ submitted: false, submitting: false }"`.
- **REQUIRE:** Submit button MUST disable (`:disabled="submitting"`) and show "Sending…" while `submitting` is true.
- **REQUIRE:** `fetch()` call to the Formspree action URL. On success, set `submitted=true`. On error, set `submitting=false`.
- **REQUIRE:** Success message MUST be inside a `<template x-if="submitted">` block to remove it from the accessibility tree when not active.
- **REQUIRE:** `aria-live="polite"` on the form container so screen readers announce the success/error state.

## 2. SEMANTIC CONSTRAINTS (HTML, A11y & SEO)

### Legal, NAP & SEO (Local Business Trust)
- **REQUIRE:** Footer MUST contain exact NAP: Company Name, physical address, local phone number.
- **REQUIRE:** Trade license number MUST be visible in the footer (e.g., "MN License #12345").
- **REQUIRE:** Privacy Policy and Terms of Service links MUST be present in the footer.
- **REQUIRE (route existence):** The footer links to `/privacy` and `/terms` MUST resolve to real pages. In a static Astro build, a dangling link 404s and hurts trust + SEO. The SOP Turn 1 step now owns this: create `src/pages/privacy.astro` and `src/pages/terms.astro` as minimal stub pages (thin `<Layout>` + heading + placeholder paragraph) so the routes resolve. If the loop guard prevents those writes in Turn 1, create them in the Turn 7 pre-launch step. Do NOT ship footer links that 404. The human replaces the stub copy with real legal text before launch.
- **REQUIRE:** Dynamic copyright year: `{new Date().getFullYear()}` (Astro syntax).
- **REQUIRE:** `<html lang="en">` (or appropriate language code). Missing this causes screen readers to mispronounce text.
- **REQUIRE:** `<script type="application/ld+json">` in the `<head>`. Must use a specific `@type` (e.g., `HVACBusiness`, `Plumber`, `Electrician` — not just `LocalBusiness`). Must include `@context`, `name`, `telephone`, `address` (with `addressLocality`, `addressRegion`, `postalCode`), `areaServed`, and `licenseNumber`.

### Accessibility (WCAG 2.1 AA)
- **BAN:** `<div>` or `<span>` with `@click` for actions. Use `<button>`.
- **BAN:** Hardcoded `aria-expanded` with ANY value (`"false"`, `"true"`, `"open"`). It MUST be dynamically bound to Alpine state: `:aria-expanded="open.toString()"`.
- **BAN:** Positive `tabindex` (e.g., `tabindex="1"`). It breaks natural keyboard navigation.
- **REQUIRE:** `aria-label` on ALL icon-only buttons (hamburger, close, scroll-top).
- **REQUIRE:** `aria-controls="mobile-menu"` on hamburger toggles, matching the `id="mobile-menu"` on the menu div.
- **REQUIRE:** `role="dialog"` and `aria-modal="true"` on mobile menus/modals.
- **REQUIRE:** `@keydown.escape="open = false"` on the mobile menu container to allow keyboard users to close it.
- **REQUIRE:** Body scroll lock (`:class="{ 'overflow-hidden': open }"`) on the `<body>` tag when mobile menu is open.
- **REQUIRE:** Every `<input>` MUST have a matching `<label for="id">`. Do not rely on placeholders. (Note: The Bespoke Primitives in `/high-end-visual-design` use floating labels; ensure the `for` and `id` attributes match perfectly).
- **REQUIRE:** `alt=""` on decorative images/SVGs. Descriptive `alt` on content images.
- **REQUIRE:** Visible focus states. `focus:ring-2` or `focus-visible:ring-2` on all links, buttons, and inputs. NEVER `outline-none` without a replacement ring. (Allowed exception: the Bespoke Haptic Checkbox from `/high-end-visual-design` uses a `sr-only peer` input that is visually hidden by design and paired with a visible focusable sibling box — this is not a focusable control and does not require a ring.)
- **REQUIRE:** Skip link: `<a href="#main" class="sr-only focus:not-sr-only">Skip to content</a>` as the absolute first element in `<body>`.
- **REQUIRE:** Semantic landmarks: exactly one `<main>`, `<header>`, and `<footer>`. 
- **REQUIRE:** Logical heading hierarchy: exactly one `<h1>`. No skipped levels (e.g., `<h2>` followed by `<h4>` is a fail).
- **REQUIRE:** `prefers-reduced-motion` media query for all CSS animations and transitions. (Handled in Layout.astro `.reveal` CSS).

### Color & Contrast (The WCAG Guardrail)
*Note: Visual styling is dictated by `/high-end-visual-design`. This section enforces the mathematical minimums for those styles.*
- **REQUIRE:** The `--text-muted` token MUST pass WCAG AA contrast (4.5:1) against the `--surface` background. Avoid overly light grays (e.g., equivalent to `text-gray-400` on white fails). Use a token equivalent to `text-gray-600` or darker on light backgrounds.
- **REQUIRE:** The `--text-muted` token on dark backgrounds must be equivalent to `text-gray-300` or lighter.
- **REQUIRE:** UI components (input borders, icon boundaries) must have a 3:1 contrast ratio against adjacent colors. 
  - **CRITICAL INPUT CONTRAST:** Interactive input borders MUST be at least `border-black/40` (or `border-white/40` on DARK themes) to pass the 3:1 UI component contrast rule. `border-black/10` / `border-white/10` is a WCAG failure. Note: a faint `ring-1 ring-black/5` (or `ring-white/5` on dark) is acceptable for subtle *card* rings, but the *input* boundary that the user tabs to must be distinct (use `/40`). On dark themes, also ensure the input's `bg-surface-muted` fill contrasts the surrounding `surface-elevated` enough to read as a field.

## 3. PRE-OUTPUT VALIDATION (MENTAL CHECKLIST)
Before emitting the code, verify:
- [ ] Cookie banner uses inline `x-data` and `x-show` (not `x-if`).
- [ ] Form uses `@submit.prevent`, `fetch()`, `<template x-if="submitted">` for the success message, `aria-live="polite"` on the form container, and `autocomplete` on every input.
- [ ] Honeypot is `type="text"` with `class="sr-only"`, NOT `type="hidden"`.
- [ ] All `aria-expanded` attributes are dynamically bound to `.toString()`.
- [ ] Mobile menu has `role="dialog"`, `aria-modal="true"`, and `@keydown.escape`.
- [ ] JSON-LD uses a specific `@type` (e.g., `HVACBusiness`), not just `LocalBusiness`.
- [ ] Input borders meet the 3:1 contrast minimum (e.g., `border-black/40` / `border-white/40`).
- [ ] Skip link is the absolute first child of `<body>`.

> **Build-time enforcement:** These constraints MUST be satisfied when the form/landing markup is first written (SOP Turn 3), not retrofitted during a later compliance pass. The Turn 6a/6b verification turns should be no-op confirmations. If you find a missing requirement at verification time, fix it there AND note it so the upstream build step can be corrected.