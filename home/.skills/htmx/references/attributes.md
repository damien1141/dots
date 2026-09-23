# htmx Attribute Reference

## Table of Contents
- [HTTP Verb Attributes](#http-verb-attributes)
- [hx-trigger](#hx-trigger)
- [hx-target](#hx-target)
- [hx-swap](#hx-swap)
- [hx-swap-oob](#hx-swap-oob)
- [hx-select and hx-select-oob](#hx-select-and-hx-select-oob)
- [hx-vals and hx-vars](#hx-vals-and-hx-vars)
- [hx-headers](#hx-headers)
- [hx-params](#hx-params)
- [hx-include](#hx-include)
- [hx-encoding](#hx-encoding)
- [hx-boost](#hx-boost)
- [hx-confirm and hx-prompt](#hx-confirm-and-hx-prompt)
- [hx-indicator](#hx-indicator)
- [hx-disabled-elt](#hx-disabled-elt)
- [hx-on](#hx-on)
- [hx-push-url and hx-replace-url](#hx-push-url-and-hx-replace-url)
- [hx-sync](#hx-sync)
- [hx-request](#hx-request)
- [hx-ext](#hx-ext)
- [hx-preserve](#hx-preserve)
- [hx-disable](#hx-disable)
- [hx-history and hx-history-elt](#hx-history-and-hx-history-elt)
- [hx-disinherit and hx-inherit](#hx-disinherit-and-hx-inherit)
- [hx-validate](#hx-validate)
- [Inheritance Summary](#inheritance-summary)

---

## HTTP Verb Attributes

`hx-get`, `hx-post`, `hx-put`, `hx-patch`, `hx-delete`

All issue an AJAX request of the corresponding HTTP method to the specified URL.

```html
<button hx-get="/api/items">Load Items</button>
<form hx-post="/api/items">...</form>
<button hx-put="/api/items/1">Update</button>
<button hx-patch="/api/items/1">Partial Update</button>
<button hx-delete="/api/items/1">Delete</button>
```

- Empty value (e.g., `hx-get=""`) requests the current page URL.
- GET requests on non-form elements do NOT include surrounding input values by default. Use `hx-include="closest form"` to include them.
- For DELETE: return `200` with empty body to remove the element. A `204 No Content` triggers NO swap.
- None are inherited.

---

## hx-trigger

**Syntax:** `hx-trigger="<event>[<filter>] <modifiers>, ..."`

### Default Triggers
- Most elements: `click`
- `<input>`, `<textarea>`, `<select>`: `change`
- `<form>`: `submit`

### Event Filters
JavaScript expressions in square brackets. Must return truthy to fire:
```html
<div hx-get="/data" hx-trigger="click[ctrlKey]">Ctrl+Click only</div>
<input hx-get="/search" hx-trigger="keyup[key=='Enter']"/>
<div hx-get="/data" hx-trigger="click[event.shiftKey]">Shift+Click</div>
```

### Modifiers
| Modifier | Description | Example |
|----------|-------------|---------|
| `once` | Trigger only once | `click once` |
| `changed` | Only if value changed | `keyup changed` |
| `delay:<time>` | Debounce | `input delay:500ms` |
| `throttle:<time>` | Throttle | `scroll throttle:200ms` |
| `from:<selector>` | Listen on another element | `keyup from:body` |
| `target:<selector>` | Filter by event target | `click target:.btn` |
| `consume` | Stop propagation | `click consume` |
| `queue:<strategy>` | Queue behavior | `click queue:last` |

### from: Extended Selectors
- `from:document` / `from:window` — global listeners
- `from:closest <sel>` — nearest ancestor
- `from:find <sel>` — descendant
- `from:next` / `from:previous` — siblings
- `from:body` — for `HX-Trigger` response headers

### Special Events
```html
<!-- Fire on page load -->
<div hx-get="/content" hx-trigger="load">

<!-- Fire when scrolled into viewport -->
<div hx-get="/content" hx-trigger="revealed">

<!-- IntersectionObserver with options -->
<img hx-get="/image" hx-trigger="intersect once threshold:0.5">

<!-- Polling -->
<div hx-get="/status" hx-trigger="every 2s">
<div hx-get="/status" hx-trigger="every 1s [isActive]">
```

### Multiple Triggers
```html
<input hx-post="/search"
       hx-trigger="input changed delay:500ms, keyup[key=='Enter'], load">
```

### Keyboard Shortcuts
```html
<button hx-post="/action"
        hx-trigger="click, keyup[altKey&&shiftKey&&key=='D'] from:body">
  Do Action (Alt+Shift+D)
</button>
```

Not inherited.

---

## hx-target

**Values:**
| Syntax | Description |
|--------|-------------|
| CSS selector | Any element matching selector |
| `this` | The element itself |
| `closest <sel>` | Nearest ancestor |
| `find <sel>` | First descendant |
| `next` / `next <sel>` | Next sibling |
| `previous` / `previous <sel>` | Previous sibling |

```html
<div hx-target="#output">
<tr hx-target="closest tbody">
<button hx-target="find .result">
<button hx-target="next div">
```

Inherited.

---

## hx-swap

**Values:** `innerHTML` (default), `outerHTML`, `textContent`, `beforebegin`, `afterbegin`, `beforeend`, `afterend`, `delete`, `none`

### Modifiers
```html
<!-- Delay swap for animation -->
<div hx-swap="outerHTML swap:1s">

<!-- Delay settle for animation -->
<div hx-swap="outerHTML settle:1s">

<!-- Use View Transitions API -->
<div hx-swap="innerHTML transition:true">

<!-- Don't update page title -->
<div hx-swap="innerHTML ignoreTitle">

<!-- Scroll target after swap -->
<div hx-swap="innerHTML scroll:top">
<div hx-swap="innerHTML scroll:#other-element:bottom">

<!-- Show element after swap -->
<div hx-swap="innerHTML show:top">
<div hx-swap="innerHTML show:window:top">
<div hx-swap="innerHTML show:#element:top">

<!-- Control focus scrolling -->
<div hx-swap="innerHTML focus-scroll:true">
```

`outerHTML` on `<body>` is automatically converted to `innerHTML`.

Inherited.

---

## hx-swap-oob

Enables out-of-band swaps — response elements update different parts of the page.

**Values:**
- `true` — swap into element with matching `id` using `innerHTML`
- Any `hx-swap` value — use that strategy
- `<strategy>:<selector>` — swap using strategy into element matching selector

```html
<!-- In response HTML: -->
<div id="alerts" hx-swap-oob="true">New alert!</div>
<div id="count" hx-swap-oob="outerHTML">42</div>
<div hx-swap-oob="innerHTML:#sidebar">Sidebar content</div>
```

### Template Wrapping for Table Elements
Elements like `<tr>`, `<td>`, `<option>` cannot exist outside their parent context. Wrap in `<template>`:
```html
<template><tr id="row-5" hx-swap-oob="true"><td>Updated</td></tr></template>
```

For SVG elements, double-wrap:
```html
<template><svg><circle id="c1" hx-swap-oob="true" r="10"/></svg></template>
```

Nested OOB swaps are processed by default (`htmx.config.allowNestedOobSwaps`).

Not inherited.

---

## hx-select and hx-select-oob

### hx-select
CSS selector to pick a portion of the response:
```html
<div hx-get="/page" hx-select="#main-content">
```

### hx-select-oob
Pick portions for out-of-band swap. Comma-separated, with optional swap strategy:
```html
<div hx-get="/page"
     hx-select="#content"
     hx-select-oob="#sidebar, #nav:afterbegin">
```

Both inherited.

---

## hx-vals and hx-vars

### hx-vals (preferred)
JSON format for static values:
```html
<button hx-post="/action" hx-vals='{"key": "value", "count": 42}'>
```

Dynamic with `js:` prefix:
```html
<div hx-post="/action" hx-vals='js:{lastKey: event.key, time: Date.now()}'>
```

Inherited. Child values override parent.

### hx-vars (deprecated, use hx-vals)
```html
<div hx-vars="myVar:computeMyVar()">
```
Always evaluates as JavaScript. More XSS risk than `hx-vals`.

---

## hx-headers

Add custom HTTP headers in JSON format:
```html
<button hx-post="/api" hx-headers='{"X-CSRF-Token": "abc123"}'>
```

Dynamic with `js:` prefix:
```html
<button hx-post="/api" hx-headers='js:{"X-Token": getToken()}'>
```

Inherited. Child values override parent.

---

## hx-params

Filter which parameters are submitted:
```html
<div hx-params="*">         <!-- all (default) -->
<div hx-params="none">      <!-- none -->
<div hx-params="name,email"> <!-- only these -->
<div hx-params="not token">  <!-- all except these -->
```

Inherited.

---

## hx-include

Include input values from other elements:
```html
<button hx-post="/action" hx-include="#extra-fields">
<button hx-post="/action" hx-include="closest form">
<button hx-post="/action" hx-include="find .inputs">
<button hx-post="/action" hx-include="next input">
```

Non-input elements include all their child inputs. Disabled inputs are ignored.

Supports `inherit` keyword to combine parent + own selectors.

Inherited.

---

## hx-encoding

Switch encoding for file uploads:
```html
<form hx-post="/upload" hx-encoding="multipart/form-data">
  <input type="file" name="file">
  <button>Upload</button>
</form>
```

Inherited.

---

## hx-boost

Progressively enhance links and forms to use AJAX:
```html
<div hx-boost="true">
  <a href="/page">Becomes AJAX</a>
  <form action="/submit" method="post">Becomes AJAX</form>
</div>
<a href="/normal" hx-boost="false">Still normal</a>
```

- Anchors: GET to href, targets body, pushes URL to history
- Forms: method determines verb, targets body, does NOT push URL by default
- Only boosts same-domain links (not `#anchors`, not external)

Inherited.

---

## hx-confirm and hx-prompt

### hx-confirm
```html
<button hx-delete="/item" hx-confirm="Delete this item?">Delete</button>
```

Custom confirmation via `htmx:confirm` event:
```javascript
document.body.addEventListener('htmx:confirm', function(evt) {
  evt.preventDefault();
  showCustomDialog().then(confirmed => {
    if (confirmed) evt.detail.issueRequest(true);
  });
});
```

### hx-prompt
```html
<button hx-post="/rename" hx-prompt="Enter new name:">Rename</button>
```
User input is sent in the `HX-Prompt` request header.

Both inherited.

---

## hx-indicator

Element(s) that show a loading state during requests:
```html
<button hx-get="/data" hx-indicator="#spinner">Load</button>
<span id="spinner" class="htmx-indicator">
  <img src="/spinner.gif"/> Loading...
</span>
```

htmx adds `htmx-request` class to the indicator element during requests. Default CSS transitions `opacity` from 0 to 1.

```html
<!-- Use closest ancestor -->
<button hx-indicator="closest .card">

<!-- Multiple indicators with inherit -->
<div hx-indicator="#global-spinner">
  <button hx-indicator="inherit #local-spinner">
```

Without `hx-indicator`, the triggering element itself gets `htmx-request`.

Inherited.

---

## hx-disabled-elt

Disable elements during requests:
```html
<button hx-post="/save" hx-disabled-elt="this">Save</button>
<button hx-post="/save" hx-disabled-elt="find input">Save</button>
<form hx-post="/save" hx-disabled-elt="find input, find button">
```

Inherited.

---

## hx-on

Inline event handlers:
```html
<!-- Standard DOM events -->
<button hx-on:click="alert('clicked')">Click</button>

<!-- htmx events (double-colon shorthand) -->
<button hx-get="/data" hx-on::before-request="showSpinner()">
<button hx-get="/data" hx-on::after-request="hideSpinner()">
<form hx-post="/save" hx-on::after-request="if(event.detail.successful) this.reset()">

<!-- Full form -->
<button hx-on:htmx:before-request="showSpinner()">

<!-- JSX-compatible (dashes replace colons) -->
<button hx-on--before-request="showSpinner()">
```

Provides `this` (element) and `event` (event object). Not inherited (but events bubble).

---

## hx-push-url and hx-replace-url

### hx-push-url — Create history entry
```html
<a hx-get="/page" hx-push-url="true">         <!-- push the fetched URL -->
<a hx-get="/page" hx-push-url="/custom-url">   <!-- push custom URL -->
<a hx-get="/page" hx-push-url="false">         <!-- no history update -->
```

### hx-replace-url — Replace current entry
```html
<a hx-get="/page" hx-replace-url="true">       <!-- replace with fetched URL -->
<a hx-get="/page" hx-replace-url="/custom-url"> <!-- replace with custom URL -->
```

Response headers `HX-Push-Url` and `HX-Replace-Url` override the attributes. Both inherited.

---

## hx-sync

Synchronize requests between elements:
```html
<form hx-sync="this:replace">
  <!-- Only the latest submission goes through -->
</form>

<input hx-post="/validate" hx-sync="closest form:abort">
<!-- Aborts this validation if form submits -->

<button hx-get="/data" hx-sync="this:drop">
<!-- Ignore clicks while request is in-flight -->

<button hx-get="/data" hx-sync="this:queue last">
<!-- Queue only the last request -->
```

**Strategies:**
| Strategy | Behavior |
|----------|----------|
| `drop` | Ignore new request if one in-flight (default) |
| `abort` | Drop this request, abort ongoing |
| `replace` | Abort ongoing, replace with this |
| `queue first` | Queue first request only |
| `queue last` | Queue last request only |
| `queue all` | Queue all requests |

Inherited.

---

## hx-request

Configure request options:
```html
<div hx-request='{"timeout": 5000}'>
<div hx-request='{"credentials": true}'>
<div hx-request='{"noHeaders": true}'>
<div hx-request='js:{"timeout": getTimeout()}'>
```

Merge-inherited (child values merge with parent).

---

## hx-ext

Enable extensions:
```html
<body hx-ext="response-targets, head-support">
  <div hx-ext="ignore:response-targets">
    <!-- response-targets disabled here, head-support still active -->
  </div>
</body>
```

Inherited and merged.

---

## hx-preserve

Keep an element unchanged across swaps:
```html
<video id="player" hx-preserve>...</video>
```

Requires a stable `id`. The response must contain an element with the same `id`. Not inherited.

---

## hx-disable

Completely disable htmx processing:
```html
<div hx-disable>
  <!-- No htmx attributes will be processed here -->
  <div hx-get="/nope">This won't work</div>
</div>
```

Use for user-generated content as a security measure. Inherited (cannot be overridden by children).

---

## hx-history and hx-history-elt

### hx-history
Prevent page from being cached in localStorage:
```html
<body hx-history="false">
```

Use for pages with sensitive data.

### hx-history-elt
Specify which element is used for history snapshots (default: `<body>`):
```html
<div id="content" hx-history-elt>...</div>
```

Not inherited.

---

## hx-disinherit and hx-inherit

### hx-disinherit
Disable attribute inheritance:
```html
<div hx-target="#output" hx-disinherit="*">        <!-- disable all -->
<div hx-target="#output" hx-disinherit="hx-target"> <!-- disable specific -->
```

### hx-inherit
Enable when global inheritance is off (`htmx.config.disableInheritance: true`):
```html
<div hx-target="#output" hx-inherit="hx-target">
```

---

## hx-validate

Force HTML5 validation before request:
```html
<input hx-post="/validate" hx-validate="true">
```

By default, only `<form>` elements validate. Adding this to individual inputs enables per-input validation. Not inherited.

---

## Inheritance Summary

### Inherited Attributes
`hx-target`, `hx-swap`, `hx-select`, `hx-select-oob`, `hx-boost`, `hx-vals`, `hx-confirm`, `hx-indicator`, `hx-include`, `hx-push-url`, `hx-replace-url`, `hx-sync`, `hx-headers`, `hx-params`, `hx-ext`, `hx-request`, `hx-encoding`, `hx-disable`, `hx-disabled-elt`, `hx-prompt`, `hx-vars`

### Not Inherited
`hx-get`, `hx-post`, `hx-put`, `hx-delete`, `hx-patch`, `hx-trigger`, `hx-swap-oob`, `hx-on`, `hx-preserve`, `hx-history-elt`, `hx-validate`
