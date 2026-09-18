# LiteNPS — Architecture

Reference document. Read before starting a new phase or proposing a structural
change. Not loaded into agent context automatically — the distilled rules live in
`CLAUDE.md` and `.claude/rules/`.

Last revised: 2026-09

---

## 1. What this is

An open-source NPS collection tool. A small script embedded in a customer's site
shows a survey, collects a 0-10 score plus an optional comment, and reports it on
a real-time dashboard.

- **AGPL-3.0**, with a hosted version run by the maintainer.
- Single maintainer. **Operational simplicity is a hard constraint, not a preference.**

Pricing, plans and commercial terms live on the website, not in this repository.

### Design principles

1. **Response volume is inherently low.** An NPS answer is a rare event; even a busy
   site produces a handful per hour. The real cost driver is the script loading on
   every pageview, which is why the loader is tiny and cacheable and why bandwidth
   is pushed to an edge cache.
2. **Data minimisation.** No persistent visitor identifier is stored, and raw IP and
   user-agent never reach disk. Free-text comments are the deliberate exception and
   are treated as personal data throughout — see §7.
3. **Responses are immutable, not permanent.** Rows are never updated in place;
   aggregates are always derived. Deletion happens only through the named paths in §7.
4. **The widget never breaks the host page.** Silent failure, isolated styles, no globals.
5. **Open source is trust, not a cost centre.** The hosted version competes on
   operation, not on withholding the code.

---

## 2. Stack

| Layer | Choice |
|---|---|
| Language | Elixir 1.20.x |
| Backend / dashboard | Phoenix 1.8.x + LiveView 1.2.x |
| Database | PostgreSQL 16+ |
| Widget | Svelte 5 + Vite (library mode) — **not SvelteKit** |
| Deploy | `mix phx.gen.release --docker` onto a managed platform with a managed Postgres |
| Edge cache | Cloudflare in proxy mode over the app domain |
| Payments | Merchant of Record — vendor recorded in private notes |

Everything else is added per phase (§9), not up front.

---

## 3. What was deliberately removed

An earlier draft of this design included several components that were cut. They
are listed here so they are not silently reintroduced.

| Removed | Why | Reintroduce when |
|---|---|---|
| GenServer/Broadway ingestion buffer | NPS volume is a few events per minute. Batching trades at-least-once for at-most-once and adds a failure mode for no gain. | A measured write burst that a direct insert cannot absorb. |
| `rollups` table + Oban aggregation job | Indexed Postgres answers dashboard queries in milliseconds at this scale. Two sources of truth is a real cost. | A dashboard query exceeds ~200ms on production-shaped data. |
| Separate `Endpoint` for the widget | A separate pipeline gives nearly all the isolation for ~10 lines. A separate endpoint costs a port, TLS, config and deploy surface. | A concrete isolation requirement the pipeline cannot meet. |
| CI job publishing the widget to object storage | Serving `w.js` from Phoenix behind Cloudflare gets the same caching with no pipeline. | Bandwidth or origin load becomes measurable. |
| Scheduled salt rotation job | Reversed on review — see §7. The salt must be random and deleted, not derived, or the identifier is only pseudonymous. Rotation is lazy (first request of a new day), so no scheduler and no Oban dependency is needed — but the salt is stored and expired. | N/A |
| Table partitioning | Premature at any volume this project will see for years. | Query planning degrades on `responses`. |
| Maintained `docker-compose.yml` for self-hosting | Nobody dogfoods it — the hosted deployment uses a managed database and terminates TLS at the platform. An unexercised deployment path breaks silently and becomes a support burden. See §11. | Never as a maintained artifact; a published image plus a guide replaces it. |

---

## 4. Contexts

### `Litenps.Accounts`
Users and organizations. Generated with Phoenix 1.8 auth + scopes.

`orgs`: `id`, `name`, `inserted_at`

`users`: the generated auth schema plus `org_id`.

**A user belongs to exactly one organization**, created in the same transaction
at registration. This is what lets the scope resolve a tenant from the session
alone — there is no organization picker anywhere in the interface, and so no code
path that can pick the wrong one. An organization has many users, so invites need
only an invite flow and a `role` column, not a change to the tenant boundary. A
`role` is deliberately absent until invites exist. See `docs/adr/0001-organization-as-tenant.md`.

`Litenps.Accounts.Scope` carries `%Scope{user: user, org: org}`.
`Scope.for_user/1` raises on a user whose organization is not loaded, and every
path in `Accounts` that can feed a scope preloads it — a scope that cannot name
its tenant is unconstructible, not merely discouraged.

### `Litenps.Sites`
The measurement scope. An org has many sites. **The tenant is the org.**

`sites`: `id`, `org_id`, `name`, `allowed_origins` (array), `timezone`,
`data_retention_days`, `inserted_at`

`api_keys`: `id`, `site_id`, `org_id`, `key` (`pk_live_...`, unique), `revoked_at`

Keys are a separate table, not a column, because a leaked key must be rotatable.
Two keys may be active at once during a transition; a revoked key returns `404`.

### `Litenps.Surveys`
Survey definition and display rules.

`surveys`: `id`, `org_id`, `site_id`, `question`, `followup_question`,
`status` (`draft|active|paused`), `theme` (jsonb), `targeting` (jsonb),
`cooldown_days` (default 90), `sample_rate` (0.0–1.0)

`targeting`: `url_patterns`, `delay_seconds`, `device`

### `Litenps.Collect`
The only writer to `responses`.

`responses`: `id`, `org_id`, `site_id`, `survey_id`, `score` (0–10),
`comment` (nullable), `redacted_at` (nullable), `visitor_hash` (bytea),
`url_path`, `metadata` (jsonb), `inserted_at`

`salts`: `date`, `value` (bytea) — random, deleted after 48h.

Indexes: `(site_id, inserted_at)`, `(site_id, survey_id, inserted_at)`,
`(site_id, visitor_hash)`, `(org_id)`

**`org_id` is denormalized onto every tenant-owned table**, including `responses`.
Database purists object, but it makes account deletion and export a single
predicate and stops a bad join from crossing a tenant boundary. Composite indexes
lead with the column queries actually filter on.

Tenant scoping is enforced by construction through Phoenix 1.8 scopes: no context
function accepts a bare id. Postgres RLS is the recommended safety net for teams,
but is deliberately skipped here — for a single maintainer using scopes it adds
operational surface without a matching risk.

### `Litenps.Analytics`
Read-only. `Litenps.Analytics.Stats` holds all NPS math as pure functions.

### `Litenps.Billing`
Receives MoR webhooks, maintains `subscriptions`. Behind a behaviour so the app runs
with billing disabled.

---

## 5. Request paths

Three pipelines, sharing no plugs:

- `:browser` — dashboard. Session, CSRF, LiveView, scope-based auth.
- `:api` — dashboard API. Token auth.
- `:widget` — public. No session, no CSRF, no user. Public key auth, origin check,
  rate limit, small body limit.

Public endpoints:

| Method | Path | Response |
|---|---|---|
| `GET` | `/v1/config?k=pk_...` | JSON with active survey, targeting, theme. `ETag`, ~5 min cache. |
| `POST` | `/v1/responses` | `204` |
| `POST` | `/v1/responses/:id/comment` | `204` |

---

## 6. Widget

Installed as one tag:

```html
<script async src="https://{your-instance}/w.js?k=pk_live_abc"></script>
```

### Two-stage load

This is what keeps the per-pageview cost near zero. Do not collapse it into one bundle.

1. `w.js` is a **loader under 2kb**, not the widget.
2. It checks the local cooldown. If cooling down, it stops without a network call.
3. Otherwise it calls `GET /v1/config`. **Targeting is decided server-side.**
4. If nothing matches, it stops. The overwhelming majority of pageviews end here,
   served from cache.
5. If something matches, it dynamically imports the widget bundle.

### Rendering

A `<litenps-widget>` custom element with Shadow DOM. Svelte inlines the styles as
JS strings rather than emitting a CSS file — which is exactly what a widget wants.
Known caveats are recorded in `.claude/rules/widget.md`; the sharpest one is that
props must never begin with `on`.

### Versioning

`w.js` is a stable filename with a short cache, pointing at an immutable
`w-<hash>.js`. Customers never change their tag to get updates.

---

## 7. Privacy

```
visitor_hash = sha256(daily_salt <> site_id <> ip <> user_agent)
```

This follows the pattern every serious cookieless tool converged on: derive the
identifier from what the server already sees, and scope it to a single day so it
cannot become a tracking ID.

Two decisions here were corrected from an earlier draft and should not be reverted:

**The salt is random, not derived from a secret.** A salt computed as
`hmac(secret, date)` is recomputable forever by anyone holding the secret — the
resulting identifier is pseudonymous, not anonymous. A random salt that is deleted
after 48h makes yesterday's identifiers unlinkable to today's, including by the
operator. Since privacy is this product's differentiator, the weaker version is not
worth the saved complexity. Rotation is lazy — generated on the first request of a
new UTC day, persisted to Postgres, current and previous cached in memory. The
previous salt exists so a response submitted just after midnight still matches the
same visitor.

**The client-side `visitor_id` never reaches the server.** It lives in `localStorage`
purely so the widget can decide not to re-prompt someone, and it is checked before
any network call. Sending it would create exactly the persistent cross-day identifier
this design exists to avoid — being in `localStorage` rather than a cookie changes
nothing legally. The cost is that long-horizon cooldown is best-effort: clearing
site data resets it. That is the correct trade.

Raw IP and user-agent are used within the request for hashing and rate limiting, and
are never written to database, logs, or disk.

Scores are anonymous. Free-text comments are not — people type names, emails and
phone numbers into them. Treat the `comment` column as personal data for the purposes
of erasure, export, and retention. Publishing this algorithm is intentional: security
rests on the secret and the deleted salt, and verifiability is the point of the claim.

### Deletion paths

An absolute "never delete" rule would make erasure requests and account closure
impossible. Three named paths exist, and only these:

1. **Tenant deletion** — all rows for an `org_id`, on account closure.
2. **Comment redaction** — `comment = NULL` plus `redacted_at`; the score survives.
3. **Retention expiry** — rows older than the site's `data_retention_days`.

Immutability means `score`, `inserted_at`, `site_id` and `visitor_hash` are never
updated in place. It does not mean rows live forever.

---

## 8. Dashboard

LiveView subscribed to `"site:#{id}:responses"`. Response list via `stream/3`,
heavier queries via `assign_async`. Charts start as plain SVG; a Svelte component
mounted through a colocated hook is the escape hatch if real interactivity is needed.

Screens: install/snippet, responses, overview (score + trend + sample size),
survey settings, billing.

Always show sample size next to a score. A score computed from twelve responses is
noise and presenting it bare is misleading.

---

## 9. Phases

Each phase ships on its own. Do not start the next before the exit criterion holds.

**Phase 1 — Foundation.** Auth with scopes, `Accounts`, `Sites`, `Surveys`, dashboard CRUD.
New deps: none beyond a stock Phoenix app.
*Done when:* you can sign up, create a site, create a survey, and see an install snippet.

**Phase 2 — Ingestion.** `:widget` pipeline, plugs, `/v1/config`, `/v1/responses`, direct insert.
New deps: a rate limiter.
*Done when:* `curl` records a response, and is rejected with a bad origin or bad key.

**Phase 3 — Widget.** Loader, custom element, cooldown, comment step.
New deps: Svelte, Vite.
*Done when:* it works embedded in a plain HTML page with hostile CSS, and leaks nothing.

**Phase 4 — Real-time dashboard.** PubSub, streams, `Stats`, trend.
New deps: none.
*Done when:* a submitted response appears on the dashboard in under one second.

**Phase 5 — Product.** Billing, onboarding, public shared report, user-facing docs.
New deps: Oban, MoR SDK.
*Done when:* a stranger can pay and install unaided.

**Phase 6 — Optimization.** Telemetry, benchmarks, and only now an evaluation of
native code.

---

## 10. Out of scope

Not planned, not promised, and not to be started without an explicit decision.
This is a record of reasoning, not a roadmap — nothing here carries a commitment
or a date.

**Marketing site in SvelteKit.** Separate project, separate deploy. Never mixed into the app.

**Integrations.** Outbound webhook first — simplest and most useful.

---

## 11. Deployment

One supported target: the hosted deployment. `config/runtime.exs` is the only
configuration surface.

`mix phx.gen.release --docker` generates the Dockerfile, `rel/`, and a migration
helper; the release is assembled inside the container and the image is built from
its artifacts.

### Hosted (operated by the maintainer)

Application and database on the **same provider and region**. Ecto issues many small
queries; splitting app and database across providers adds a round trip to each one.

Non-negotiable settings:

- **Nothing scales to zero — neither the app nor the database.** Cold starts break
  LiveView sessions, and `/v1/config` sits on the critical path of the customer's
  own page. This also rules out usage-metered serverless Postgres, whose entire
  cost advantage depends on idling.
- **The database is managed, with backups and upgrades owned by the provider.**
  A self-run Postgres instance on a hosting platform is not acceptable here.
  Database operations are outside this project's maintained scope, and
  unrecoverable data loss is the one failure mode with no undo.
- Cloudflare in front, proxying the app domain, keeping widget bandwidth off the
  origin and inside egress allowances.
- The provider's backup retention window must be documented, because it interacts
  with the deletion paths in §7 — an erased comment must not survive in an old dump.

**Connection pooling.** Managed Postgres usually sits behind PgBouncer in transaction
mode. This has three consequences that are easy to miss until they break in production:

- Ecto must be configured with `prepare: :unnamed` and no statement cache.
- **Oban's default Postgres notifier relies on `LISTEN/NOTIFY`, which does not work
  through transaction pooling.** Use `Oban.Notifiers.PG` instead. This surfaces in
  Phase 5, long after the decision is made.
- `Phoenix.PubSub` is unaffected — it is not database-backed, so the real-time
  dashboard is safe either way.

Prefer the provider's direct connection string over the pooled one when the
connection limit allows, which avoids all three.

### Self-hosting — not offered yet

The code is public under AGPL, but **self-hosting is not a supported feature at
launch.** No `docker-compose.yml` is maintained. Anyone can build and run the repo;
nothing about that path is promised, tested, or supported.

This is deliberate. A deployment configuration the maintainer does not run breaks
silently, and every published deployment artifact is a support surface. Publishing
the code costs nothing; publishing a stack implies you keep it working.

When self-hosting is offered, it follows the shape Metabase uses:

- **A published, versioned image** built by CI — not a Dockerfile users build
  themselves. The artifact is the image; a Dockerfile is homework.
- **Bring your own Postgres.** The database stays outside the supported surface,
  which is the same reason the hosted deployment uses a managed one.
- **A written production guide**, honest about what the operator takes on: the
  application database, TLS termination, backups, and upgrades.
- **A stated support level** in the README: community-supported, no upgrade
  guarantees, no SLA.

Compose files, if any, are illustrative examples explicitly marked as unsuitable
for production — the way Metabase labels theirs — not a maintained deployment path.

Not before Phase 5 is complete and the hosted version has real users.

---

## 12. Conventions

- Contexts talk to each other only through public functions.
- `LitenpsWeb` never touches `Repo`.
- Migrations are always reversible.
- No business logic in LiveViews — orchestration only.
- Public context functions have `@doc` and `@spec`.
- Structural decisions get a dated file in `docs/adr/` and an update to this document
  in the same commit.
