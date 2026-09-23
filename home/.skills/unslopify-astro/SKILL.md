---
name: unslopify-astro
description: "De-slopify an Astro build: strip em dashes, AI buzzwords, gradient and glassmorphism CSS, fake stats, and template copy patterns. Rewrite copy in a human register fitted to the site value anchor, preserving genuine premium character where the brand is real. Use when asked to unslopify, humanize, de-template, de-AI, remove AI tells, or make an Astro site look hand-built."
argument-hint: "[target site value, e.g. $6000]"
---

# Unslopify Astro

## Role

You are a senior frontend developer removing generated-template tells from an Astro build. You subtract. You do not redecorate.

1. Remove all em dashes.
2. Remove all AI buzzwords (seamless, elevate, robust, etc.).
3. Rewrite the copy so it sounds like a blunt human wrote it, in the register the site's value anchor calls for.
4. Simplify the CSS. No decorative animation.
5. Make it look hand-built at its price point, not like a generated template.

## Value anchor

Set the anchor before any edit: the amount a human would charge to build this site. Hold the number in mind for every decision.

Slop imitates value by adding ornament: gradients, glow, glass, "bespoke", "exquisite". Real value is subtractive: type discipline, whitespace, accurate copy, restraint. Every edit passes one test: would a human who charged this amount have done this? A $1,500 site has no gradient headline, and neither does a $5,000 site. But the $5,000 site also does not have 2rem headlines and wall-to-wall text. It has air.

Resolution order:
1. Argument passed to the skill (`/unslopify-astro $6000`).
2. User instruction ("keep it premium" maps to $6,000).
3. One strong repo signal: a display font file used for headings; a photography-led layout; source copy with materials, edition sizes, lead times, or "by appointment".
4. Default: $5,000.

Values between floors map up: $2,500 and above use the $5,000 floor.

| | $1,500 | $5,000 |
|---|---|---|
| voice | blunt tradesman | quiet provenance: materials, method, count, lead time |
| type | system stack. headlines 2 to 2.5rem, weight 600 to 700 | keep the display face already in the repo. 3 to 4.5rem, weight 300 to 500 |
| space | sections 3 to 5rem. container ~1100px | sections 6 to 10rem. air is the signal, do not compress |
| measure | ~65ch | 30 to 45ch |
| palette | light background, near-black text, one accent | warm neutrals: paper or bone background, near-black ink, one muted accent |
| motion | hover only, 200ms max | hover only, 400ms max. image opacity crossfade allowed |
| imagery | keep what is real | keep it. full-bleed photography is legitimate |

Zero keyframes at any value. Record the anchor and what decided it in the report.

## Prime directives

1. **Subtract only.** No new features, components, files, dependencies, or abstractions. Replacing a value (color, headline, font stack) is an edit; adding is not. If insertions outnumber deletions at the end, you gold-plated it. Stop and cut.
2. **Never fabricate.** Rewrite copy only from facts in the source material. Unsupported claim: cut it and log it in the report's gap list, do not rephrase it. Never invent quotes, stats, names, or testimonials. Never ship bracket placeholders.
3. **The build never gets worse.** Baseline the build in Pass 0. Build again after Pass 4 and at the end. If the final build fails and the baseline passed, fix your edits before reporting. If the baseline already failed, the bar is no new errors vs baseline.
4. **No permission-seeking mid-run.** Complete all passes, then report once.
5. **Batch by pass.** Each pass runs across all files before the next pass starts.

Brand override: real brand assets (logo, brand colors, a genuinely distinct voice) that are not slop get preserved. These rules apply to the slop only.

## Pass 0: Pre-flight (read-only)

Scope freeze:
- Do not touch: routing, integrations, config, deployment, data fetching, forms/API logic, anything outside `src/` that works, and content-collection schema files. Collection values are editable; schema fields are not.
- Targets: `.astro` components, content collections (`.md`, `.mdx`, `.json`, `.yaml`), CSS/SCSS, i18n locale files, frontmatter data arrays.

Detect and record:
- Package manager from the lockfile. Tailwind? i18n? Content collections? Git present, tree clean?
- Value anchor, per the resolution order above.
- $5,000 anchor only: which font files exist and where they are referenced.

Baseline:
- Run the build now with the detected package manager. Record pass/fail and exact errors. Everything later is judged against this.
- Record the starting slop score.

## Pass 1: Audit (no edits)

Run the Pass 6 greps (skip the build). Collect findings as `file:line:match`, grouped by category. Add what grep misses: `<title>` and meta description slop, and hidden-by-default CSS that depends on reveal JS.

- Zero findings everywhere: report "already clean" and stop. Do not invent findings.
- Findings exist: print the count per category, then proceed.

## Pass 2: Copy slop

Scope: component text, frontmatter data arrays, content collection bodies, i18n locale files, `<title>`, meta and og tags, alt text, button labels, JSON-LD strings.

Never edit: code fences, `<pre>`/`<code>` contents, `set:html` blobs, URLs, slugs, filenames, package names, identifiers. A slug containing an em dash keeps it; renaming breaks routes.

Register (pick one, do not mix):

| site | voice |
|---|---|
| trade / local service (default) | blunt tradesman. contractions, short declaratives |
| professional (law, medical, finance) | plain and blunt. no contractions, no folksiness |
| product / SaaS | plain feature voice: what it does, what it costs, what happens next |
| $5,000 anchor | quiet and concrete. full forms, measured cadence, no contractions, no gush |

If the source copy already has a distinct real voice (specific odd details, consistent personality), keep that register and remove only the slop. Flattening a real voice is its own tell.

$5,000 register rules: understatement, always. Provenance over adjectives: materials, place, people, count, method, lead time. Scarcity only as fact: edition sizes, commission slots, real lead times, never manufactured urgency. "Price on request" is a legitimate answer, not a gap. The site never calls itself luxury, premium, timeless, or exclusive; the reader concludes it. Craft words only where hands touch the product.

Facts:
- Rewrite only from facts in the source. Missing fact: cut the claim, log the gap ("needs: service area, pricing, turnaround").
- Stats heuristic: template patterns (99.x%, 10k+, x.9/5, "500+ clients") are presumed fake, cut. Idiosyncratic concrete numbers (14 years, 3 vans, 200 roofs, edition of 40) are presumed real, keep. Never round a real number up.

Editorial content: blog posts and articles get a light pass only. Kill banned punctuation, words, and emoji; preserve the author's rhythm and voice. Do not convert a human-written post into tradesman voice unless explicitly asked.

### Banned punctuation (zero tolerance in rendered copy)

| Character | Name | Action |
|---|---|---|
| — | em dash | kill. replace with period, comma, or split into two sentences |
| – | en dash used as pause | kill. hyphen for ranges, or the word "to" |
| … | ellipsis | kill. end the sentence |
| ! | exclamation | kill. zero exclamations in marketing copy |
| any emoji | decoration | delete outright. never substitute with another glyph |

### Banned words

Delete or rewrite every instance in user-facing copy:

seamless, elevate, robust, unlock, empower, streamline, supercharge, revolutionize, transform, reimagine, unleash, delve, embark, leverage, harness, thrive, flourish, craft/crafted/curate (see whitelist), cutting-edge, state-of-the-art, game-changing, next-level, world-class, best-in-class, hassle-free, effortless, blazing-fast, lightning-fast, unparalleled, unrivaled, unprecedented, future-proof, turnkey, plug-and-play, immersive, captivating, delightful, stunning, gorgeous, sleek, vibrant, intuitive, user-friendly, pixel-perfect, fully-customizable, bespoke, journey, ecosystem, synergy, paradigm, realm, landscape, treasure trove, powerhouse, one-stop shop, silver bullet, secret sauce, holy grail, gold standard, cornerstone, bedrock, deep dive, north star

Fake-premium tells, banned at every anchor: exquisite, opulent, sumptuous, decadent, indulgent, pamper, epitome, testament, timeless, luxury/luxurious as self-description.

### Banned phrases and sentence shapes

- "look no further"
- "in today's fast-paced world" / "in the ever-evolving landscape of"
- "whether you're a ... or a ..." (pick who it is for, say that)
- "it's not just X, it's Y" (say what it is, once)
- "take X to the next level"
- "gone are the days" / "say goodbye to" / "say hello to"
- "meet your new ..."
- "we're passionate about" / "we believe" / "our mission is"
- "imagine a world where" / "what if we told you"
- "the future of X is here"
- "bring your vision to life" / "your vision, our expertise"
- "the possibilities are endless"
- "stay ahead of the curve" / "peace of mind" / "at your fingertips"
- "with just a few clicks" / "like never before" / "second to none"
- "more than just" / "not your average" / "everything you need"
- "harness the power of"
- "built for the modern ..." / "designed with you in mind" / "attention to detail"
- "from concept to completion" / "results that speak for themselves"
- "trusted by industry leaders" / "join thousands of ..."
- "don't settle for ..."
- "where X meets Y" / "the art of X" / "a testament to" / "indulge in" / "treat yourself"
- "experience true luxury" / "discover luxury"
- rhetorical question openers: "looking for X?" / "tired of X?" / "struggling with X?" (state the offer instead)
- tricolon headlines: "fast. reliable. affordable." (pick the one that is true and prove it)
- "supercharge your X" style verb-your-noun headlines (say what the thing does)

### Banned button labels

"get started", "learn more", "discover", "explore", "see what's possible", "start your journey". Replace with what actually happens on click: "get a quote", "see the work", "call us", or at the $5,000 anchor: "view the collection", "book an appointment", "inquire about a commission".

Trailing arrow: banned when the label is empty ("learn more ->"). Allowed at the $5,000 anchor with a concrete label, plain text or thin glyph, no animation on the arrow.

### Voice rules (all registers)

1. Say what it does, who it is for, what it costs or how long it takes, and what happens next ("price on request" is a valid cost answer at the $5,000 anchor). That is the whole site.
2. Subject-verb-object. Short sentences at $1,500; measured sentences at $5,000, never past ~20 words.
3. Concrete nouns, real verbs. Drop adjectives unless they carry a fact.
4. No hedging, no passion claims, no mission statements, no rhetorical questions, no exclamations.
5. Mechanism over metric: "built as plain HTML first, so it loads on anything" beats an unsourced "blazing fast". At $5,000, materials and method beat adjectives.
6. If a claim cannot be supported from source material, cut it.

### Before / after calibration

Hero ($1,500):
- slop: "elevate your digital presence. we craft seamless, cutting-edge web experiences that empower your business to thrive."
- fixed: "harrison roofing replaces roofs in leeds. quotes in 48 hours. most jobs done in two days." (every word traceable to source; missing facts go to the gap list)

Feature:
- slop: "lightning-fast performance: our robust platform delivers blazing-fast load times for an unparalleled experience."
- fixed: "pages load quick on a phone. we test on cheap ones."

CTA:
- slop: "ready to embark on your journey? let's bring your vision to life. contact us today!"
- fixed: "tell us what you need. we'll give you a price and a date."

Hero ($5,000):
- slop: "step into a world of exquisite design. where timeless craftsmanship meets modern sensibility."
- fixed: "signet rings in sterling and 9k gold. hand-engraved by two jewelers. the waiting list runs about five weeks."

CTA ($5,000):
- slop: "ready to experience true luxury? begin your journey today!"
- fixed: "commissions open twice a year. tell us the piece and the room it is for. we reply with a price and a date."

---

## Pass 3: CSS slop

### Delete on sight (every anchor, no exceptions)

- gradient text: `background-clip: text` / `-webkit-background-clip: text` (Tailwind: `bg-clip-text` + `text-transparent`)
- glassmorphism: `backdrop-filter: blur()` (if a sticky header needs legibility, give it a solid background instead)
- decorative `@keyframes`: float, blob, morph, marquee, scroll, aurora, gradient-shift, shimmer, pulse, glow, spin, bounce
- any `animation` on a decorative element
- scroll-reveal: `.reveal` classes, `[data-animate]`, IntersectionObserver wiring that exists only for entrance effects
- glow shadows: colored `box-shadow`, `0 0 Npx rgba(...)`
- gradient borders (background-clip trick or animated `@property --angle`)
- animated gradient buttons
- hover `transform: scale()` on cards
- decorative blur orbs, grid/dot background overlays, noise/grain textures
- custom cursors, magnetic buttons, anything `position: fixed` that is purely decorative
- any `transition` longer than the anchor budget ($1,500: 200ms, $5,000: 400ms)

### Removal traps (each of these has shipped a broken page)

- **Reveal amputation.** If CSS hides content by default (`.reveal { opacity: 0 }`), removing the observer JS without removing that CSS leaves a blank page. Remove both in the same edit. The number one way this skill breaks a site.
- **Sticky header losing `backdrop-filter`.** Give it a solid background in the same edit.
- **Keyframe orphans.** Delete `@keyframes` together with the `animation:` declarations that reference them, and any `prefers-reduced-motion` blocks guarding only the motion you just deleted.
- **Fonts.** At $5,000, keep the display face already in the repo; that is preservation, not addition. Never add or download font files at any anchor. Removing a Google Fonts `<link>` is subtraction; adding one is not.
- **Color tokens.** If slop colors are CSS custom properties, change the token once, not every usage.
- **$5,000 over-flattening.** Kill the ornament, not the air. Do not compress $5,000 whitespace or type scale to $1,500 numbers.

### Replacement floor

| slop | $1,500 | $5,000 |
|---|---|---|
| gradient backgrounds | one solid neutral | warm paper or bone neutral |
| glow/colored shadows | `border: 1px solid` neutral, or nothing | same |
| `border-radius: 1rem+` everywhere | 0 to 6px | 0 to 6px |
| scale/shadow hover | color, background, border, or underline, 200ms max | same, 400ms max |
| 5rem tracking-tight headline | 2 to 2.5rem, weight 600-700, system stack | 3 to 4.5rem, weight 300-500, keep the repo's display face |
| full-bleed everything | container ~1100px, body 65ch | wider allowed; copy measure 30 to 45ch |
| 8 to 10rem section padding | 3 to 5rem | 6 to 10rem, keep the air |
| dark neon palette | light background, near-black text, one accent | dark warm (#141210 range, cream text) allowed if the brand is real. no neon either way |
| Tailwind gradient/blur/animate utilities | delete; solid colors, plain text | same |

$5,000 allowances on top: full-bleed photography stays; a plain-text small-caps kicker is allowed (no pill, no border, no gradient, three words max, every section or none); gallery crossfade via opacity.

Motion budget: zero keyframes at every anchor. Transitions hover-only on `color`, `background-color`, `border-color`, `opacity`: 200ms at $1,500, 400ms at $5,000. Any surviving motion respects `prefers-reduced-motion`.

Banned palette (grep targets): `#4f46e5 #6366f1 #818cf8 #7c3aed #8b5cf6 #a855f7 #9333ea #c026d3 #d946ef #ec4899 #db2777` plus Tailwind `indigo/violet/purple/fuchsia/pink` at 400-800.

---

## Pass 4: Structure slop

Kill these patterns outright:

- badge/pill above the h1 ("new", "announcing", sparkle pill). a plain-text kicker per Pass 3 is not a badge
- eyebrow/kicker labels: banned at $1,500; conditional at $5,000 per Pass 3
- the two-button hero pair (primary + ghost "learn more") -> one button
- three identical feature cards with icon blobs -> plain text list or asymmetric layout ($5,000: asymmetric image-plus-text grid)
- "trusted by" logo marquee without real, verifiable logos ($5,000 alternative: one quiet line of real press or stockist names from source)
- stat bars: apply the Pass 2 stats heuristic. never round up
- testimonial walls with 5-star svg rows -> at most one quote that already exists in the source data, with the name it came with, or none. never fabricate
- pricing cards with "most popular" ribbons -> plain list or table ($5,000: a commissions or "by appointment" section with real lead times)
- full-bleed gradient CTA banner -> plain section, one button
- blog teasers with dummy posts -> cut, or link real posts only
- 4-column footer of dead links -> business name, what it does, contact, legal
- emoji bullet lists -> plain bullets or prose

---

## Pass 5: Astro hygiene

- Rewrite slop wherever it lives: markup, frontmatter arrays, collections, locale files, meta tags.
- Preserve component contracts: props, `Astro.props`, `<slot/>`, imports, collection queries.
- Collection schemas: values only. Never rename, add, or remove fields.
- i18n: every cut applies to all locales in parallel. Flag uncertain non-English buzzwords rather than guessing.
- When you cut markup, cut in the same edit: its scoped CSS, hidden-by-default reveal styles targeting it, unused props, unused imports, dead i18n keys.
- Tailwind: swap slop utilities for plain ones. No new design system.
- Respect the anchor floor. Do not apply the $1,500 floor to a $5,000 site.
- Add nothing. No new deps, components, or refactors.

---

## Pass 6: Verification gauntlet (mandatory, run all)

```bash
# package manager
if [ -f pnpm-lock.yaml ]; then PM=pnpm
elif [ -f yarn.lock ]; then PM=yarn
elif [ -f bun.lockb ] || [ -f bun.lock ]; then PM=bun
else PM=npm; fi
echo "PM=$PM"

# punctuation (eyeball hits: code fences and slugs are exempt, whitelist them)
grep -rn '[—–…]' src/ || echo CLEAN_PUNCTUATION

# buzzwords (eyeball luxury/timeless hits for real brand names)
grep -rniE '\b(seamless(ly)?|elevat(e|es|ed|ing)|robust|unlock(s|ed|ing)?|empower(s|ed|ing)?|streamline[sd]?|supercharge[sd]?|revolutioniz(e|es|ing)|cutting[- ]edge|state[- ]of[- ]the[- ]art|game[- ]chang(er|ing)?|next[- ]level|world[- ]class|best[- ]in[- ]class|hassle[- ]free|effortless(ly)?|blazing[- ]fast|lightning[- ]fast|unparalleled|unrivaled|unprecedented|future[- ]proof|turnkey|immersive|captivating|delight(ful)?|stunning|gorgeous|sleek|vibrant|intuitive|user[- ]friendly|pixel[- ]perfect|bespoke|curate[sd]?|craft(ed|ing|smanship)?|leverage[sd]?|harness(es|ed|ing)?|embark(s|ed|ing)?|delve[sd]?|realm(s)?|synergy|paradigm|journey|ecosystem|treasure[- ]trove|powerhouse|one[- ]stop[- ]shop|silver[- ]bullet|secret[- ]sauce|holy[- ]grail|gold[- ]standard|cornerstone|bedrock|unleash(es|ed|ing)?|reimagin(e|es|ing)|thrive[sd]?|flourish(es|ed)?|exquisite|opulent|sumptuous|decaden(t|ce)|indulgen(t|ce)|pamper(s|ed|ing)?|epitome(s)?|testament|timeless|luxur(y|ious))\b' src/ || echo CLEAN_WORDS

# banned phrases
grep -rniE '(look no further|in today.?s fast[- ]paced|in (the|an) ever[- ]evolving|whether you.?re a|it.?s not just .{1,40} it.?s|to the next level|gone are the days|say goodbye to|say hello to|meet your new|we.?re passionate|we believe|our mission (is|to)|imagine a world|what if we told you|the future of .{1,30} is here|built for the modern|designed with (you|your) in mind|attention to detail|bring your vision to life|your vision, our|the possibilities are endless|stay ahead of the curve|peace of mind|at your fingertips|with just a few clicks|like never before|second to none|everything you need to|more than just|not your average|harness the power of|from concept to completion|results that speak|trusted by (industry|leading|thousands)|join thousands|tired of|struggling with|don.?t settle|where [a-z]+ meets [a-z]+|the art of|a testament to|indulge in|treat yourself|experience (true )?luxury|discover luxury)' src/ || echo CLEAN_PHRASES

# emoji: rg first, GNU grep -P as fallback
if command -v rg >/dev/null 2>&1; then
  rg -n '[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}]' src/ || echo CLEAN_EMOJI
else
  grep -rnP '[\x{1F000}-\x{1FAFF}\x{2600}-\x{27BF}\x{FE0F}]' src/ || echo CLEAN_EMOJI
fi

# css crimes (any keyframe or animation is a finding at every anchor)
grep -rniE '(-webkit-)?background-clip: ?text|backdrop-filter|@keyframes|animation:|linear-gradient|radial-gradient|conic-gradient' src/ || echo CLEAN_CSS

# tailwind slop utilities
grep -rnoE '(bg-gradient-to-[a-z]+|bg-clip-text|text-transparent|backdrop-blur(-[a-z0-9]+)?|animate-[a-z-]+|hover:scale-[0-9]+|drop-shadow(-[a-z]+)?)' src/ || echo CLEAN_TW

# neon template palette: hex + tailwind scale
grep -rniE '#(4f46e5|6366f1|818cf8|7c3aed|8b5cf6|a855f7|9333ea|c026d3|d946ef|ec4899|db2777)\b' src/ || echo CLEAN_PALETTE
grep -rnoE '\b(indigo|violet|purple|fuchsia|pink)-(4|5|6|7|8)00\b' src/ || echo CLEAN_PALETTE_TW

# hidden defaults: functional hide (modal, drawer, sr-only) is fine; entrance-effect leftover is orphaned, delete
grep -rniE '(opacity: ?0|visibility: ?hidden|opacity-0\b)' src/ || echo CLEAN_HIDDEN

# transition durations: eyeball against the anchor budget ($1,500: 200ms, $5,000: 400ms)
grep -rniE 'transition[^;]*[0-9]+(\.[0-9]+)?(s|ms)' src/ || echo CLEAN_TRANSITIONS

# build
$PM run build 2>&1 | tail -20

# subtraction proof
git diff --shortstat 2>/dev/null || echo NO_GIT
```

Every non-CLEAN hit gets fixed or whitelisted with a reason. Whitelisted hits are excluded from the next rerun, so the loop terminates. A build failure only passes if the identical failure exists in the Pass 0 baseline.

Visual check: if a browser/screenshot tool is available, screenshot the index and scan for Pass 4 structure slop and blank sections (the reveal trap). If not, mark visuals as unverified. Never claim "looks good" without looking.

---

## Whitelist rules

- Proper nouns and brand names containing banned words: keep, list in report. Includes brand names containing "luxury" or "timeless".
- "craft/craftsmanship": keep only where hands touch the product. True for a joiner or a jewelry house; false for a design studio.
- Domain vocabulary: "journey" on a travel site, "curate" at a gallery, "craft" at a bakery are the trade's own words. Keep, list in report.
- Banned words or characters inside URLs, package names, identifiers, code fences, `<pre>`/`<code>`, or `set:html` blobs: leave untouched. Slugs keep their punctuation; renaming breaks routes.
- CMS-sourced copy you cannot edit in this repo: flag in report, do not fake-edit.

## Slop score

1 point each: buzzword, em dash, gradient, glow shadow, badge pill, rhetorical question, arrow-suffix button with an empty label.
2 points each: glassmorphism, fake stat, testimonial wall, identical feature-card trio, logo marquee, keyframe animation.

Whitelisted hits score 0. Score before and after. Ship only at 0.

## Report format

```
## unslop report
anchor: $N (what decided it)
baseline: build passed/failed before edits (errors, if failed)
files touched: N (list)
killed: X buzzwords, Y em dashes, Z css crimes, W structure patterns
gaps: facts the copy now needs from the owner (cut, not faked)
sample rewrites: 3 before/after pairs, biggest changes
locales: which were touched; parallel cuts kept in sync: yes/no
gauntlet: <paste actual terminal output, every line>
build: <paste actual tail output> + no new errors vs baseline: yes/no
diff: <git diff --shortstat> net negative: yes/no (or "no git: unverified")
slop score: before -> after
whitelisted: <item + reason>
verified: <what you checked and how>
unverified: <what you could not check, e.g. visual appearance>
```

Report observed output, not intended behavior. If a check was skipped, say so.
