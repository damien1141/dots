# htmx Extensions Reference

## Table of Contents
- [SSE (Server-Sent Events)](#sse)
- [WebSocket](#websocket)
- [Idiomorph (DOM Morphing)](#idiomorph)
- [Head Support](#head-support)
- [Response Targets](#response-targets)
- [Preload](#preload)
- [htmx 1.x Compatibility](#htmx-1x-compatibility)
- [Building Custom Extensions](#building-custom-extensions)

---

## SSE

Server-Sent Events extension for real-time, uni-directional server-to-client streaming.

### Setup
```html
<body hx-ext="sse">
  <div sse-connect="/events">
    <div sse-swap="message">Waiting for messages...</div>
    <div sse-swap="notification">Waiting for notifications...</div>
  </div>
</body>
```

### Attributes
| Attribute | Description |
|-----------|-------------|
| `sse-connect="<url>"` | Establish SSE connection |
| `sse-swap="<event-name>"` | Swap content when named event arrives |
| `sse-close="<event-name>"` | Close connection on event |
| `hx-trigger="sse:<event>"` | Trigger htmx request on SSE event |

### Named Events
```html
<div sse-connect="/events">
  <!-- Swap on named event "userUpdate" -->
  <div sse-swap="userUpdate">...</div>

  <!-- Trigger a GET when "refresh" event arrives -->
  <div hx-get="/data" hx-trigger="sse:refresh">...</div>
</div>
```

### Swap Strategies with SSE
```html
<div sse-swap="message" hx-swap="beforeend">
  <!-- Messages append instead of replacing -->
</div>
```

### Closing the Connection
```html
<div sse-connect="/events" sse-close="complete">
  <!-- Closes when server sends event named "complete" -->
</div>
```

### Events
- `htmx:sseOpen` — connection opened
- `htmx:sseError` — connection error
- `htmx:sseBeforeMessage` — before processing (cancelable)
- `htmx:sseMessage` — after processing
- `htmx:sseClose` — connection closed (reasons: `nodeMissing`, `nodeReplaced`, `message`)

### Server-Side
```
event: userUpdate
data: <div>New user data</div>

event: notification
data: <span class="badge">3 new</span>
```

---

## WebSocket

Bi-directional communication via WebSocket.

### Setup
```html
<body hx-ext="ws">
  <div ws-connect="/chat">
    <!-- Incoming messages swapped by element ID using OOB -->
    <div id="messages">...</div>

    <!-- Form sends JSON to WebSocket -->
    <form ws-send>
      <input name="message">
      <button>Send</button>
    </form>
  </div>
</body>
```

### Attributes
| Attribute | Description |
|-----------|-------------|
| `ws-connect="<url>"` | Establish WebSocket connection |
| `ws-send` | Send form data as JSON on submit |

### How It Works
- **Sending:** `ws-send` serializes the nearest form's inputs as JSON and sends to the server
- **Receiving:** Incoming HTML messages are parsed and swapped via OOB (matching element `id`s)

### URL Prefixes
```html
<div ws-connect="ws://example.com/chat">   <!-- explicit ws -->
<div ws-connect="wss://example.com/chat">  <!-- explicit wss -->
<div ws-connect="/chat">                    <!-- auto: wss for https, ws for http -->
```

### Configuration
- `htmx.config.wsReconnectDelay` — reconnect strategy (default: `full-jitter`)
- `htmx.config.wsBinaryType` — binary data type (default: `blob`)
- `htmx.createWebSocket` — factory function override

### Events
- `htmx:wsConnecting` — attempting to connect
- `htmx:wsOpen` — connection established
- `htmx:wsClose` — connection closed
- `htmx:wsError` — connection error
- `htmx:wsBeforeMessage` — before processing incoming (cancelable)
- `htmx:wsAfterMessage` — after processing incoming
- `htmx:wsConfigSend` — before sending (modify message)
- `htmx:wsBeforeSend` — just before send
- `htmx:wsAfterSend` — after send

---

## Idiomorph

DOM morphing swap strategy that reuses existing nodes for smoother transitions.

### Setup
```html
<body hx-ext="morph">
  <div hx-get="/content" hx-swap="morph">
    <!-- Content morphed instead of replaced -->
  </div>
</body>
```

### Swap Strategies
```html
<div hx-swap="morph">           <!-- morph target + children (outerHTML style) -->
<div hx-swap="morph:outerHTML"> <!-- same as above -->
<div hx-swap="morph:innerHTML"> <!-- morph only children, keep target -->
```

### When to Use
- When you want smooth transitions without losing DOM state (scroll position, focus, etc.)
- When you have complex nested structures that benefit from minimal DOM changes
- Pairs well with polling or SSE for live-updating UIs

---

## Head Support

Manage `<head>` tag content from htmx responses.

### Setup
```html
<head hx-ext="head-support">
  <title>My App</title>
  <link rel="stylesheet" href="/styles.css">
</head>
```

### Behavior
- **Boosted requests:** Merge algorithm — keeps matches, adds new, removes old
- **Non-boosted requests:** Appends new head content only

### Override per-request
```html
<head hx-head="merge">   <!-- force merge -->
<head hx-head="append">  <!-- force append -->
```

### Per-element control
```html
<script src="/app.js" hx-head="re-eval">   <!-- re-execute on every request -->
<link rel="stylesheet" hx-preserve="true">  <!-- never remove -->
```

### Events
- `htmx:beforeHeadMerge` — before merge
- `htmx:afterHeadMerge` — after merge
- `htmx:removingHeadElement` — before element removal (cancelable)
- `htmx:addingHeadElement` — before element addition (cancelable)

---

## Response Targets

Route responses to different swap targets based on HTTP status code.

### Setup
```html
<body hx-ext="response-targets">
  <form hx-post="/api/submit"
        hx-target="#success"
        hx-target-422="#form-errors"
        hx-target-5*="#server-error"
        hx-target-error="#error-container">
    ...
  </form>
</body>
```

### Attribute Syntax
| Attribute | Matches |
|-----------|---------|
| `hx-target-404` | Exactly 404 |
| `hx-target-4*` | 400-499 |
| `hx-target-40*` | 400-409 |
| `hx-target-*` | Any non-2xx/3xx |
| `hx-target-error` | Any 4xx or 5xx |

Wildcard resolution tries most specific first: `404` → `40*` → `4*` → `*`

Use `x` instead of `*` if your tooling doesn't support asterisks: `hx-target-4xx`

### Configuration
- `responseTargetPrefersRetargetHeader` (default: `true`) — `HX-Retarget` header overrides
- `responseTargetUnsetsError` (default: `true`) — clears `isError` for matched errors
- `responseTargetPrefersExisting` (default: `false`) — pre-existing targets take precedence

---

## Preload

Preload content before the user clicks for near-instant page loads.

### Setup
```html
<body hx-ext="preload">
  <a href="/page" preload>Fast Link</a>
  <button hx-get="/data" preload="mouseover">Hover to Preload</button>
</body>
```

### Trigger Modes
| Value | Behavior |
|-------|----------|
| `mousedown` | Load on mouse press (default, ~100-200ms head start) |
| `mouseover` | Load on hover (100ms debounce) |
| `custom-event` | Load on custom event |
| `always` | Re-preload on every trigger (not just once) |

### Images
```html
<a href="/page" preload preload-images="true">
  <!-- Also preloads images found in the response -->
</a>
```

### Immediate Preloading
```html
<a href="/page" preload="preload:init">
  <!-- Preload immediately on page load -->
</a>
```

Only works with GET requests. Server responses must include `Cache-Control` headers for browser caching.

---

## htmx 1.x Compatibility

Bridge extension for migrating from htmx 1.x to 2.x.

### Setup
```html
<script src="htmx.js"></script>
<script src="htmx-1-compat.js"></script>
```

### What It Restores
- `hx-ws` and `hx-sse` attributes (replaced by extensions in v2)
- Old-style `hx-on` attribute (replaced by `hx-on*` wildcard in v2)
- `scrollBehavior` default to `'smooth'` (v2 uses `'instant'`)
- DELETE requests use form-encoded body (v2 uses URL parameters)
- Cross-domain requests allowed by default (v2 blocks them)

### What It Does NOT Cover
- IE11 support (dropped in htmx 2)
- Extension `swap` method API changes

---

## Building Custom Extensions

### Defining an Extension
```javascript
htmx.defineExtension('my-extension', {
  // Called once when the extension is initialized
  init: function(api) {
    // api provides internal htmx methods
  },

  // Return additional CSS selectors for htmx to process
  getSelectors: function() {
    return ['[my-attr]'];
  },

  // Called on every htmx event
  onEvent: function(name, evt) {
    if (name === 'htmx:beforeRequest') {
      // modify request
    }
  },

  // Transform response text before processing
  transformResponse: function(text, xhr, elt) {
    return text.toUpperCase();
  },

  // Declare custom swap styles
  isInlineSwap: function(swapStyle) {
    return swapStyle === 'my-swap';
  },

  // Handle custom swap
  handleSwap: function(swapStyle, target, fragment, settleInfo) {
    if (swapStyle === 'my-swap') {
      // custom swap logic
      return []; // return settled elements
    }
  },

  // Custom parameter encoding
  encodeParameters: function(xhr, parameters, elt) {
    xhr.setRequestHeader('Content-Type', 'application/json');
    xhr.overrideMimeType('text/json');
    return JSON.stringify(parameters);
  }
});
```

### Using the Extension
```html
<div hx-ext="my-extension">
  <button hx-get="/data">Load</button>
</div>
```

### Naming Convention
Use dash-separated, short, descriptive names (e.g., `json-enc`, `class-tools`, `response-targets`).
