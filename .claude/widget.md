---
paths:
  - "widget/**"
---

# Widget rules

The widget is a standalone Svelte 5 project built with Vite in **library mode**.
It is not SvelteKit and must never import SvelteKit.

## Hard constraints

- Two bundles, always:
  - `loader` — target **under 2kb gzip**. No Svelte runtime.
  - `widget` — target **under 15kb gzip**. Loaded by the loader via dynamic `import()`.
- Zero runtime dependencies. No fetch polyfills, no date libraries, no CSS frameworks.
- Every entry point wrapped in `try/catch`. A failure means the widget silently does
  not appear. It must never throw into the host page's console or break host JS.
- No globals on `window` beyond a single `__litenps` namespace.
- No cookies. State lives in `localStorage` under a single namespaced key.
- **The stored `visitor_id` is never transmitted.** It exists so the widget can
  decide, on the device, not to re-prompt someone. It must not appear in any
  request body, query string, or header. Server-side identity is derived
  independently — see `.claude/rules/ingest.md`.

## Loader flow

1. Read the public key from the script tag's `?k=` query param.
2. Check `localStorage` for an active cooldown. If cooling down, stop — no network call.
3. `GET /v1/config?k=...`. The server decides targeting; the loader does not.
4. If no active survey matches, stop. **Most pageviews end here.**
5. Only then `import()` the widget bundle.

## Custom element

Rendered as `<litenps-widget>` via `<svelte:options customElement={...} />`.

Verified caveats from the Svelte docs that apply here:

- Styles are encapsulated by Shadow DOM and **inlined as JavaScript strings**, not
  emitted as a separate CSS file. This is intended — one file, no extra request.
  `:global(...)` will not reach outside the shadow root.
- **Never name a prop or attribute starting with `on`.** Svelte treats it as an event
  listener; `oneworld={true}` becomes `addEventListener('eworld', true)`. Silent bug.
- With `$props()`, destructure explicitly or declare `customElement.props`. A rest
  element prevents Svelte from inferring what to expose.
- Use `shadow: { mode: import.meta.env.DEV ? 'open' : 'closed' }`.
- Custom elements are unsuitable for SSR. Not relevant here — do not add SSR.

## Versioning

- `w.js` — stable filename, short cache (`max-age=300`).
- `w-<hash>.js` — immutable widget bundle (`max-age=31536000, immutable`).

Customers must never have to change their script tag to receive an update.

## Testing

Test against a plain static HTML page with its own aggressive CSS, to prove style
isolation. Do not test the widget only inside the Phoenix dashboard.
