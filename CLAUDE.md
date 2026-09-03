@AGENTS.md

# LiteNPS

Open-source NPS widget SaaS. Embeddable script collects scores from a customer's
site; a Phoenix LiveView dashboard shows them in real time.

Elixir 1.20.x · Phoenix 1.8.x · LiveView 1.2.x · PostgreSQL 16+ · Svelte 5 (widget)

Full rationale lives in `docs/ARCHITECTURE.md`. Read it before starting a new
phase or proposing a structural change. Do not import it here — it is reference,
not session context.

## Non-negotiable rules

These are expensive or impossible to reverse. Do not relax them without an
explicit instruction and a matching update to `docs/ARCHITECTURE.md`.

1. **`responses` is immutable, not undeletable.** Never UPDATE `score`,
   `inserted_at`, `site_id` or `visitor_hash` on an existing row. Deletion happens
   only through three named, audited paths: tenant deletion, comment redaction
   (`comment = NULL` + `redacted_at`), and retention expiry. No other code deletes.
2. **The visitor identifier never leaves the device.** The client's `visitor_id`
   is used locally for cooldown only and is **never sent to the server**. The server
   derives `visitor_hash` from a random daily salt + site + IP + user-agent, and
   never stores raw IP or user-agent. See `.claude/rules/ingest.md`.
3. **Comments are potentially personal data.** Scores are anonymous; free-text
   comments are not, because people type names and phone numbers into them. Any
   erasure or export path must cover the comment column.
4. **The widget only knows the public key** (`pk_...`). Secrets never reach client code.
5. **The `:widget` pipeline has no session, no CSRF, no `current_scope`.** It shares
   no plug with `:browser`.
6. **Tenant scoping is by construction, never by habit.** Context functions take a
   scope, never a bare id. Every tenant-owned table carries `org_id`, including
   `responses`.
7. **All statistics go through `Litenps.Analytics.Stats`.** No NPS math anywhere else.
   This boundary exists so the implementation can be swapped later.
8. **`Litenps.Analytics` never writes.** `Litenps.Collect` is the only writer to `responses`.
9. **`LitenpsWeb` never calls `Repo` directly.**

## Build discipline

This project is maintained by one person. Operational simplicity beats throughput.

- Do not add a dependency without asking. Current phase dependencies are listed
  in `docs/ARCHITECTURE.md` §Phases.
- Do not add background jobs, queues, buffers, caches, or rollup tables until a
  measured problem requires them. Several were deliberately removed from the
  original design.
- Prefer a direct `Repo.insert` over a batching layer. Response volume is low by
  nature — an NPS answer is a rare event, not a stream.
- Ship one phase at a time. Do not implement work from a later phase.
- Production Postgres sits behind a transaction-mode pooler. Ecto needs
  `prepare: :unnamed`, and when Oban is introduced it must use `Oban.Notifiers.PG` —
  the default notifier depends on `LISTEN/NOTIFY`, which pooling breaks.

## Commands

```bash
mix setup                  # deps, db create + migrate, assets
mix phx.server             # dev server (also runs the widget Vite watcher)
mix test
mix credo --strict
mix sobelow --config       # reads .sobelow-conf
mix precommit              # compile --warnings-as-errors, format, credo, sobelow, test
cd widget && npm run build # widget bundle only
```

`mix precommit` must pass before any commit. Sobelow will flag the `:widget`
pipeline for missing CSRF protection and for its parser configuration — those are
intentional (see rule 5). Silence them with an annotated `# sobelow_skip` and a
comment explaining why; never by loosening the check globally. An unexplained skip
is a review failure.

## Layout

- `lib/litenps/` — contexts: `accounts`, `sites`, `surveys`, `collect`, `analytics`, `billing`
- `lib/litenps_web/controllers/widget/` — public endpoints (`/v1/*`)
- `lib/litenps_web/plugs/` — public key auth, origin check, rate limit
- `lib/litenps_web/live/` — dashboard
- `widget/` — standalone Svelte + Vite project (not SvelteKit)
- `docs/adr/` — one file per architectural decision, dated

<!-- Maintainer note: keep this file under ~100 lines. Path-scoped detail belongs
     in .claude/rules/. Narrative and rationale belong in docs/ARCHITECTURE.md. -->
