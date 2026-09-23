# htmx Common UI Patterns

## Table of Contents
- [Click to Edit](#click-to-edit)
- [Inline Validation](#inline-validation)
- [Active Search](#active-search)
- [Infinite Scroll](#infinite-scroll)
- [Click to Load](#click-to-load)
- [Lazy Loading](#lazy-loading)
- [Delete Row with Animation](#delete-row-with-animation)
- [Edit Row (Inline Table Editing)](#edit-row)
- [Bulk Update](#bulk-update)
- [Progress Bar](#progress-bar)
- [Cascading Selects](#cascading-selects)
- [Tabs (HATEOAS)](#tabs-hateoas)
- [Tabs (JavaScript)](#tabs-javascript)
- [Modal (Bootstrap)](#modal-bootstrap)
- [Modal (Custom)](#modal-custom)
- [File Upload with Progress](#file-upload-with-progress)
- [Dialogs (Confirm/Prompt)](#dialogs)
- [Custom Confirmation (SweetAlert2)](#custom-confirmation)
- [Keyboard Shortcuts](#keyboard-shortcuts)
- [Sortable (Drag and Drop)](#sortable)
- [Updating Other Content](#updating-other-content)
- [Reset Form After Submit](#reset-form-after-submit)
- [Animations](#animations)
- [Web Components](#web-components)

---

## Click to Edit

Display a record, click to switch to edit mode, save to switch back.

```html
<!-- Display mode -->
<div hx-target="this" hx-swap="outerHTML">
  <p><strong>Name:</strong> Joe Smith</p>
  <p><strong>Email:</strong> joe@example.com</p>
  <button hx-get="/contact/1/edit">Edit</button>
</div>

<!-- Edit mode (returned by GET /contact/1/edit) -->
<form hx-put="/contact/1" hx-target="this" hx-swap="outerHTML">
  <input name="name" value="Joe Smith">
  <input name="email" value="joe@example.com">
  <button type="submit">Save</button>
  <button hx-get="/contact/1">Cancel</button>
</form>
```

**Server:** PUT saves data, returns display mode HTML. Cancel GET returns display mode.

---

## Inline Validation

Validate fields as the user types or tabs away.

```html
<div hx-target="this" hx-swap="outerHTML">
  <label>Email</label>
  <input name="email" hx-post="/validate/email"
         hx-trigger="change, keyup delay:500ms changed"
         type="email" value="">
</div>
```

**Server:** POST `/validate/email` checks the value, returns the entire wrapping div with `.error` or `.valid` class:
```html
<div hx-target="this" hx-swap="outerHTML" class="error">
  <label>Email</label>
  <input name="email" hx-post="/validate/email" type="email" value="bad">
  <span class="error-message">That email is already taken</span>
</div>
```

```css
.error input { box-shadow: 0 0 3px red; }
.valid input { box-shadow: 0 0 3px green; }
```

---

## Active Search

Live search with debouncing and loading indicator.

```html
<input type="search" name="q"
       hx-post="/search"
       hx-trigger="input changed delay:500ms, keyup[key=='Enter'], load"
       hx-target="#results"
       hx-indicator=".search-spinner">

<span class="search-spinner htmx-indicator">Searching...</span>

<table>
  <thead><tr><th>Name</th><th>Email</th></tr></thead>
  <tbody id="results"></tbody>
</table>
```

**Key techniques:**
- `input changed delay:500ms` debounces typing
- `keyup[key=='Enter']` allows immediate search on Enter
- `load` shows initial results on page load

**Server:** Returns `<tr>` elements matching the search query.

---

## Infinite Scroll

Load more content as user scrolls down.

```html
<table>
  <tbody>
    <tr>...</tr>
    <tr>...</tr>
    <!-- Sentinel row triggers next page load -->
    <tr hx-get="/items?page=2"
        hx-trigger="revealed"
        hx-swap="afterend">
      <td>Loading...</td>
    </tr>
  </tbody>
</table>
```

**Server:** Returns more rows plus a new sentinel row for the next page. On the last page, omit the sentinel.

For `overflow: auto/scroll` containers, use `intersect once` instead of `revealed`:
```html
<tr hx-trigger="intersect once" ...>
```

---

## Click to Load

Pagination with an explicit "Load More" button.

```html
<table>
  <tbody id="contacts">
    <tr>...</tr>
  </tbody>
</table>
<button hx-get="/contacts?page=2"
        hx-target="#contacts"
        hx-swap="beforeend"
        id="load-more">
  Load More
</button>
```

**Server:** Returns additional rows. The last batch replaces the button with `hx-swap-oob`:
```html
<tr>...</tr>
<button id="load-more" hx-swap-oob="true" hx-get="/contacts?page=3"
        hx-target="#contacts" hx-swap="beforeend">
  Load More
</button>
```

---

## Lazy Loading

Load content when it appears on the page.

```html
<div hx-get="/chart-data" hx-trigger="load">
  <img src="/spinner.gif" class="htmx-indicator">
</div>
```

```css
.htmx-settling img { opacity: 0; }
img { transition: opacity 300ms ease-in; }
```

---

## Delete Row with Animation

Delete a table row with confirmation and fade-out.

```html
<tbody hx-confirm="Are you sure?"
       hx-target="closest tr"
       hx-swap="outerHTML swap:1s">
  <tr>
    <td>Joe</td>
    <td><button hx-delete="/contact/1">Delete</button></td>
  </tr>
</tbody>
```

```css
tr.htmx-swapping td {
  opacity: 0;
  transition: opacity 1s ease-out;
}
```

**Server:** DELETE returns `200` with empty body. The row element is replaced with nothing.

---

## Edit Row

Inline table row editing with mutual exclusivity.

```html
<tbody hx-target="closest tr" hx-swap="outerHTML">
  <tr>
    <td>Joe</td>
    <td>joe@example.com</td>
    <td>
      <button hx-get="/contact/1/edit"
              hx-trigger="edit"
              onClick="
                let editing = document.querySelector('.editing');
                if(editing) {
                  Swal.fire({title: 'Already Editing',
                    text: 'Finish current edit first'});
                } else {
                  htmx.trigger(this, 'edit');
                }">
        Edit
      </button>
    </td>
  </tr>
</tbody>
```

Edit mode uses `hx-include="closest tr"` on the save button since `<form>` can't go inside `<tr>`.

---

## Bulk Update

Select items with checkboxes and apply bulk action.

```html
<form hx-post="/users/bulk-update" hx-swap="outerHTML settle:3s" hx-target="#toast">
  <table>
    <tr>
      <td><input type="checkbox" name="active:user1"></td>
      <td>User 1</td>
    </tr>
    <!-- more rows -->
  </table>
  <button type="submit">Bulk Update</button>
  <output id="toast"></output>
</form>
```

```css
#toast { opacity: 0; transition: opacity 3s ease-out; }
#toast.htmx-settling { opacity: 100; }
```

---

## Progress Bar

Polling progress bar for long-running jobs.

```html
<!-- Start button -->
<button hx-post="/start-job">Start Job</button>

<!-- Returned after POST (the progress wrapper) -->
<div hx-target="this" hx-swap="innerHTML"
     hx-trigger="done" hx-get="/job/complete">
  <div hx-get="/job/progress"
       hx-trigger="every 600ms"
       hx-target="this"
       hx-swap="innerHTML">
    <div class="progress-bar" style="width:0%"></div>
  </div>
</div>
```

**Server:** Progress endpoint returns updated bar. When complete, sends `HX-Trigger: done` header. The `done` event triggers the outer div to fetch the completion state.

```css
.progress-bar {
  transition: width 0.6s ease;
}
```

---

## Cascading Selects

Dependent dropdowns (e.g., make/model).

```html
<label>Make:
  <select name="make" hx-get="/models" hx-target="#models">
    <option value="audi">Audi</option>
    <option value="toyota">Toyota</option>
  </select>
</label>
<label>Model:
  <select id="models" name="model">
    <option value="a1">A1</option>
  </select>
</label>
```

**Server:** GET `/models?make=toyota` returns `<option>` elements for that make.

---

## Tabs (HATEOAS)

Server-driven tab selection — the server controls which tab is active.

```html
<div id="tabs" hx-target="this" hx-swap="innerHTML"
     hx-get="/tab1" hx-trigger="load delay:100ms">
</div>
```

**Server:** Each tab endpoint returns full tab navigation + content:
```html
<a hx-get="/tab1" class="selected">Tab 1</a>
<a hx-get="/tab2">Tab 2</a>
<div id="tab-content">Content for tab 1...</div>
```

---

## Tabs (JavaScript)

Client-side tab switching with server-loaded content.

```html
<div id="tabs" hx-target="#tab-contents" hx-swap="innerHTML">
  <button hx-get="/tab1" class="selected"
          hx-on:htmx:after-on-load="
            document.querySelectorAll('#tabs button').forEach(b => b.classList.remove('selected'));
            this.classList.add('selected');">
    Tab 1
  </button>
  <button hx-get="/tab2"
          hx-on:htmx:after-on-load="...same...">
    Tab 2
  </button>
</div>
<div id="tab-contents">Tab 1 content</div>
```

---

## Modal (Bootstrap)

```html
<button hx-get="/modal-content"
        hx-target="#modals-here"
        hx-trigger="click"
        data-bs-toggle="modal"
        data-bs-target="#modals-here">
  Open Modal
</button>

<div id="modals-here" class="modal fade" tabindex="-1">
  <div class="modal-dialog modal-dialog-centered">
    <!-- Content loaded here by htmx -->
  </div>
</div>
```

**Server:** Returns Bootstrap modal structure (`modal-content`, `modal-header`, `modal-body`, `modal-footer`).

---

## Modal (Custom)

```html
<button hx-get="/modal" hx-target="body" hx-swap="beforeend">
  Open Modal
</button>
```

**Server returns:**
```html
<div id="modal-backdrop" class="modal-backdrop"
     _="on click trigger closeModal">
  <div class="modal-content"
       _="on closeModal add .closing wait for animationend then remove me">
    <h2>Title</h2>
    <p>Content...</p>
    <button _="on click trigger closeModal">Close</button>
  </div>
</div>
```

---

## File Upload with Progress

```html
<form hx-encoding="multipart/form-data" hx-post="/upload"
      hx-on::xhr:progress="
        document.querySelector('#progress').value = event.detail.loaded/event.detail.total * 100">
  <input type="file" name="file">
  <button>Upload</button>
  <progress id="progress" value="0" max="100"></progress>
</form>
```

---

## Dialogs

```html
<button hx-post="/action"
        hx-prompt="Enter a value"
        hx-confirm="Are you sure?"
        hx-target="#response">
  Do Action
</button>
```

Server reads the `HX-Prompt` header for the prompt value.

---

## Custom Confirmation

### Approach 1: Custom trigger event
```html
<button hx-post="/delete" hx-trigger="confirmed"
        onClick="Swal.fire({title:'Confirm?',preConfirm:()=>{htmx.trigger(this,'confirmed')}})">
  Delete
</button>
```

### Approach 2: htmx:confirm event
```javascript
document.body.addEventListener('htmx:confirm', function(e) {
  if (!e.target.hasAttribute('hx-confirm')) return;
  e.preventDefault();
  Swal.fire({
    title: 'Are you sure?',
    text: e.detail.question
  }).then(result => {
    if (result.isConfirmed) e.detail.issueRequest(true);
  });
});
```

---

## Keyboard Shortcuts

```html
<button hx-post="/action"
        hx-trigger="click, keyup[altKey&&shiftKey&&key=='D'] from:body">
  Action (Alt+Shift+D)
</button>
```

---

## Sortable

Drag-and-drop with Sortable.js integration.

```html
<form class="sortable" hx-post="/items/reorder" hx-trigger="end">
  <div class="item"><input type="hidden" name="item" value="1">Item 1</div>
  <div class="item"><input type="hidden" name="item" value="2">Item 2</div>
</form>
```

```javascript
htmx.onLoad(function(content) {
  var sortables = content.querySelectorAll('.sortable');
  for (var i = 0; i < sortables.length; i++) {
    new Sortable(sortables[i], { animation: 150, ghostClass: 'blue-bg' });
  }
});
```

---

## Updating Other Content

Four strategies for updating content outside the immediate swap target:

### 1. Expand the target
Wrap both the form and the table in a shared container and target that.

### 2. Out of Band (OOB)
Include extra elements in the response:
```html
<!-- Main response -->
<form>...</form>
<!-- OOB update -->
<tbody id="contacts-table" hx-swap-oob="beforeend">
  <tr><td>New Contact</td></tr>
</tbody>
```

### 3. Server-triggered events
Server sends: `HX-Trigger: newContact`
```html
<tbody hx-get="/contacts" hx-trigger="newContact from:body">
```

### 4. Path Dependencies extension
```html
<body hx-ext="path-deps">
  <form hx-post="/contacts">...</form>
  <tbody hx-get="/contacts" hx-trigger="path-deps" path-deps="/contacts">
```

---

## Reset Form After Submit

```html
<form hx-post="/items"
      hx-target="#items-list"
      hx-swap="beforeend"
      hx-on::after-request="if(event.detail.successful) this.reset()">
  <input name="item">
  <button>Add</button>
</form>
```

---

## Animations

### Fade out on delete
```css
tr.htmx-swapping td { opacity: 0; transition: opacity 1s; }
```
```html
<tr hx-swap="outerHTML swap:1s">
```

### Fade in new content
```css
.new-item.htmx-added { opacity: 0; }
.new-item { transition: opacity 300ms; }
```

### Request in-flight dimming
```css
form.htmx-request { opacity: 0.5; transition: opacity 300ms; }
```

### View Transitions
```html
<div hx-swap="innerHTML transition:true">
```
```css
@keyframes slide-from-right { from { transform: translateX(100%); } }
@keyframes slide-to-left { to { transform: translateX(-100%); } }
::view-transition-old(content) { animation: slide-to-left 0.3s; }
::view-transition-new(content) { animation: slide-from-right 0.3s; }
.content { view-transition-name: content; }
```

---

## Web Components

Using htmx inside Shadow DOM:

```javascript
class MyComponent extends HTMLElement {
  connectedCallback() {
    const root = this.attachShadow({mode: 'open'});
    root.innerHTML = `<button hx-get="/data" hx-target="find .output">Load</button>
                      <div class="output"></div>`;
    htmx.process(root);  // Required!
  }
}
customElements.define('my-component', MyComponent);
```

- `hx-target` and selectors only see elements within the same Shadow DOM
- Use `host` to target the host element
- Use `global` prefix to select from the main document
