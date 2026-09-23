---
name: htmx
description: Expert guidance for building web apps with htmx -- the library that gives HTML superpowers via attributes for AJAX, CSS transitions, WebSockets, and Server-Sent Events. Use when working with hx-* attributes, building hypermedia apps, writing server endpoints that return HTML fragments, or implementing click-to-edit/infinite scroll/lazy-loading; also for partial asks like 'submit a form without a page reload'.
---

# htmx Development Guide

htmx gives you access to AJAX, CSS Transitions, WebSockets, and Server-Sent Events directly in HTML using attributes. The core idea: any element can issue HTTP requests, and the response is HTML that gets swapped into the DOM.

## The Mental Model

In traditional web apps, only `<a>` and `<form>` can make HTTP requests, only `click` and `submit` trigger them, and only the full page gets replaced. htmx removes these constraints:

- **Any element** can issue a request (`<button>`, `<div>`, `<span>`, `<tr>`, etc.)
- **Any event** can trigger it (click, input, revealed, load, custom events, polling)
- **Any HTTP verb** works (GET, POST, PUT, PATCH, DELETE)
- **Any part of the page** can be the swap target

The server returns **HTML fragments**, not JSON. This is the fundamental architectural difference from SPA frameworks.

## Core Attributes

### HTTP Verbs
| Attribute | Description |
|-----------|-------------|
| `hx-get` | Issues a GET request |
| `hx-post` | Issues a POST request |
| `hx-put` | Issues a PUT request |
| `hx-patch` | Issues a PATCH request |
| `hx-delete` | Issues a DELETE request |

None of the HTTP verb attributes are inherited. An empty value (e.g., `hx-get=""`) requests the current URL.

**Example — a button that loads content:**
```html
<button hx-get="/api/data" hx-target="#result" hx-swap="innerHTML">
  Load Data
</button>
<div id="result"></div>
```

### hx-trigger — What Causes the Request
Controls which event fires the request. Default triggers: `click` for most elements, `change` for inputs/selects/textareas, `submit` for forms.

**Syntax:** `hx-trigger="<event>[<filter>] <modifiers>"`

**Modifiers:**
- `once` — trigger only once
- `changed` — only if the element's value changed
- `delay:<time>` — debounce (e.g., `delay:500ms`)
- `throttle:<time>` — throttle (e.g., `throttle:1s`)
- `from:<selector>` — listen on a different element (supports `document`, `window`, `closest <sel>`, `find <sel>`, `next`, `previous`)
- `target:<selector>` — only if the event target matches
- `consume` — stop event propagation
- `queue:<first|last|all|none>` — queuing strategy

**Event filters** use JavaScript expressions in brackets:
```html
<input hx-get="/search" hx-trigger="keyup[key=='Enter']"/>
<button hx-get="/action" hx-trigger="click[ctrlKey]">Ctrl+Click</button>
```

**Special triggers:**
- `load` — fires when element loads
- `revealed` — fires when element scrolls into viewport
- `intersect` — uses IntersectionObserver (with `root:` and `threshold:` options)
- `every <time>` — polling (e.g., `every 2s`)

**Multiple triggers** are comma-separated:
```html
<input hx-post="/search"
       hx-trigger="input changed delay:500ms, keyup[key=='Enter'], load"
       hx-target="#results">
```

Not inherited.

### hx-target — Where the Response Goes
CSS selector for the element that receives the response HTML. Defaults to the element making the request.

**Extended selectors:**
- `this` — the element itself
- `closest <sel>` — nearest ancestor matching selector
- `find <sel>` — first descendant matching selector
- `next` / `next <sel>` — next sibling (optionally matching selector)
- `previous` / `previous <sel>` — previous sibling

```html
<button hx-get="/info" hx-target="closest .card">Load</button>
<button hx-delete="/item/1" hx-target="closest tr">Delete</button>
```

Inherited.

### hx-swap — How Content is Replaced
Controls the swap strategy. Default: `innerHTML`.

| Value | Description |
|-------|-------------|
| `innerHTML` | Replace inner content of target |
| `outerHTML` | Replace the entire target element |
| `textContent` | Replace text content (no HTML parsing) |
| `beforebegin` | Insert before target |
| `afterbegin` | Insert at start of target |
| `beforeend` | Insert at end of target |
| `afterend` | Insert after target |
| `delete` | Delete the target element |
| `none` | Do nothing with the response |

**Swap modifiers** (appended with space):
- `swap:<time>` — delay before swap (e.g., `swap:1s` for fade-out animations)
- `settle:<time>` — delay before settling (e.g., `settle:1s` for fade-in)
- `transition:true` — use View Transitions API
- `ignoreTitle` — don't update page title
- `scroll:top` / `scroll:bottom` — scroll target after swap
- `show:top` / `show:bottom` — scroll element into view
- `focus-scroll:true/false` — scroll focused element into view

```html
<button hx-delete="/item" hx-swap="outerHTML swap:1s">Delete with fade</button>
```

Inherited.

### hx-swap-oob — Out of Band Swaps
Allows response elements to update multiple parts of the page simultaneously. Add `hx-swap-oob="true"` (or a swap strategy) to elements in the response that should be swapped into their matching `id` location.

```html
<!-- Server response can include: -->
<div id="main-content">Primary content here</div>
<div id="notification-count" hx-swap-oob="true">5</div>
<div id="sidebar" hx-swap-oob="outerHTML">Updated sidebar</div>
```

Use `<template>` to wrap elements that can't exist standalone (like `<tr>`, `<td>`, `<option>`):
```html
<template><tr id="row-1" hx-swap-oob="true"><td>Updated</td></tr></template>
```

Not inherited.

### hx-vals — Additional Request Parameters
Add extra values to requests in JSON format:
```html
<button hx-post="/action" hx-vals='{"key": "value"}'>Go</button>
```

Dynamic values with `js:` prefix:
```html
<button hx-post="/action" hx-vals='js:{timestamp: Date.now()}'>Go</button>
```

Inherited. Child values override parent values.

### hx-include — Include Extra Inputs
Include input values from other elements:
```html
<button hx-post="/search" hx-include="#search-form">Search</button>
<button hx-post="/save" hx-include="closest form">Save</button>
```

### hx-select and hx-select-oob — Cherry-pick Response Content
`hx-select` picks a portion of the response to swap. `hx-select-oob` picks portions for out-of-band swaps elsewhere on the page.
```html
<div hx-get="/page" hx-select="#content" hx-select-oob="#sidebar,#nav">
```

Both inherited.

## Important Patterns

### Inheritance
Most htmx attributes inherit from parent elements. Place shared attributes on a container:
```html
<div hx-target="#result" hx-swap="outerHTML" hx-indicator="#spinner">
  <button hx-get="/one">One</button>
  <button hx-get="/two">Two</button>
</div>
```

Control with `hx-disinherit` (disable) or `hx-inherit` (enable when globally disabled). HTTP verb attributes (`hx-get`, `hx-post`, etc.) and `hx-trigger` are never inherited.

### Loading Indicators
```html
<button hx-get="/data" hx-indicator="#spinner">Load</button>
<span id="spinner" class="htmx-indicator">Loading...</span>
```
htmx adds `htmx-request` class to the indicator during requests. Default CSS transitions opacity from 0 to 1.

### CSS Transitions & Animations
htmx applies CSS classes at different lifecycle stages:
- `htmx-request` — during the request (on the indicator or triggering element)
- `htmx-swapping` — during the swap phase
- `htmx-settling` — during the settling phase
- `htmx-added` — on newly added content before settling

Use these with CSS transitions for smooth animations:
```css
tr.htmx-swapping td { opacity: 0; transition: opacity 1s ease-out; }
.htmx-added { opacity: 0; }
#element { transition: opacity 300ms ease-in; }
```

### Boosting
`hx-boost="true"` progressively enhances links and forms to use AJAX:
```html
<nav hx-boost="true">
  <a href="/page1">Page 1</a>  <!-- Now uses AJAX -->
  <a href="/page2">Page 2</a>
</nav>
```

### Confirmation and Prompts
```html
<button hx-delete="/item/1" hx-confirm="Are you sure?">Delete</button>
<button hx-post="/rename" hx-prompt="Enter new name">Rename</button>
```
Prompt value is sent in the `HX-Prompt` request header.

### Synchronization
Prevent race conditions between related requests:
```html
<form hx-post="/validate" hx-sync="closest form:abort">
  <input hx-post="/validate-email" hx-sync="closest form:abort"/>
  <button type="submit">Submit</button>
</form>
```

Strategies: `drop`, `abort`, `replace`, `queue first`, `queue last`, `queue all`.

### Inline Event Handling (hx-on)
```html
<button hx-get="/data" hx-on::after-request="alert('Done!')">Load</button>
<form hx-on::after-request="if(event.detail.successful) this.reset()">
```
Double-colon `::` is shorthand for `htmx:` prefix. `this` refers to the element, `event` is the event object.

## Request and Response Headers

### Request Headers (sent by htmx)
| Header | Description |
|--------|-------------|
| `HX-Request` | Always `"true"` |
| `HX-Trigger` | ID of the triggered element |
| `HX-Trigger-Name` | Name of the triggered element |
| `HX-Target` | ID of the target element |
| `HX-Current-URL` | Current browser URL |
| `HX-Boosted` | `"true"` if boosted |
| `HX-Prompt` | User response to `hx-prompt` |

### Response Headers (sent by server)
| Header | Description |
|--------|-------------|
| `HX-Trigger` | Trigger client-side events |
| `HX-Trigger-After-Swap` | Trigger events after swap |
| `HX-Trigger-After-Settle` | Trigger events after settle |
| `HX-Push-Url` | Push URL to browser history |
| `HX-Replace-Url` | Replace current URL |
| `HX-Redirect` | Full page redirect |
| `HX-Location` | Client-side redirect (AJAX) |
| `HX-Refresh` | Full page refresh |
| `HX-Reswap` | Override swap strategy |
| `HX-Retarget` | Override swap target |
| `HX-Reselect` | Override hx-select |

`HX-Trigger` header can carry data:
```
HX-Trigger: {"showMessage": "Item deleted", "itemCount": "5"}
```

Listen for these events:
```html
<div hx-trigger="showMessage from:body" hx-get="/notifications">
```

## Response Handling

By default, 2xx responses are swapped, 4xx/5xx are not. This is configurable:

```html
<meta name="htmx-config" content='{
  "responseHandling": [
    {"code": "204", "swap": false},
    {"code": "[23]..", "swap": true},
    {"code": "422", "swap": true, "error": true},
    {"code": "[45]..", "swap": false, "error": true}
  ]
}'>
```

A `204 No Content` response causes no swap. For DELETE, return `200` with empty body to clear the element.

## Security Considerations

- `htmx.config.selfRequestsOnly` (default: `true`) — restricts AJAX to same domain
- Use `hx-disable` on containers with user-generated content
- `hx-vals` with `js:` prefix evaluates JavaScript — sanitize user input
- Set CSP nonces via `htmx.config.inlineScriptNonce` and `htmx.config.inlineStyleNonce`
- `htmx.config.allowEval` can be set to `false` for strict CSP

## Configuration

Set via meta tag or JavaScript:
```html
<meta name="htmx-config" content='{"defaultSwapStyle":"outerHTML"}'>
```

Key config options: `defaultSwapStyle` (default: `innerHTML`), `defaultSettleDelay` (default: 20ms), `historyCacheSize` (default: 10), `selfRequestsOnly` (default: true), `globalViewTransitions` (default: false).

## Reference Files

For detailed information, consult these reference files:
- `references/attributes.md` — Complete attribute reference with all options and edge cases
- `references/patterns.md` — Common UI patterns with full HTML and server-side examples
- `references/extensions.md` — SSE, WebSocket, Idiomorph, head-support, preload, response-targets, and building custom extensions
- `references/server-side.md` — Server integration patterns, response headers, and framework examples
