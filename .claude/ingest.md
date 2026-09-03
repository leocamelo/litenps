---
paths:
  - "lib/litenps/collect/**"
  - "lib/litenps/collect.ex"
  - "lib/litenps_web/controllers/widget/**"
  - "lib/litenps_web/plugs/**"
---

# Public ingestion rules

This is the only code path reachable by anonymous internet traffic. Treat every
input as hostile.

## Pipeline

The `:widget` pipeline shares no plug with `:browser`. It must not include
`Plug.Session`, CSRF protection, or anything that fetches a user or scope.

Order: public key auth → origin check → rate limit → parser with a small body limit.

- `PublicKeyAuth` resolves `pk_...` to a site. Unknown key → `404`, not `401`
  (do not confirm which keys exist).
- `OriginCheck` validates the `Origin` header against the site's `allowed_origins`.
  Reject on mismatch. Never reflect an arbitrary origin in `Access-Control-Allow-Origin`.
- `RateLimit` keys on public key + IP. IP is used in memory only and is **never persisted**.
- Body limit is small (~4kb). Enforce in `Plug.Parsers`, not in the handler.

## Endpoints

| Method | Path | Response |
|---|---|---|
| `GET` | `/v1/config?k=pk_...` | JSON: active survey, targeting, theme. `ETag`, ~5 min cache. |
| `POST` | `/v1/responses` | `204`, empty body |
| `POST` | `/v1/responses/:id/comment` | `204`, empty body |

Never return a response body on write endpoints. Never leak internal ids beyond the
opaque response id needed for the follow-up comment.

## Writing

- `Litenps.Collect` is the **only** module that writes to `responses`.
- Write with a direct `Repo.insert`. **Do not add a buffer, GenStage, Broadway, or
  batching layer.** NPS responses are rare events; a batching layer would trade
  at-least-once delivery for at-most-once and add a failure mode for no gain.
  If a real burst problem appears, it goes behind `Collect.record_response/1`.
- After a successful insert, `Phoenix.PubSub.broadcast` to `"site:#{site_id}:responses"`.
- `responses` rows are immutable. The follow-up comment is the single write-after-insert
  exception and is only permitted while the row's comment is `NULL` and within a short
  time window. Deletion happens only through the named paths below.

## Validation

- `score` must be an integer 0..10. Reject anything else.
- `comment` has a hard length cap; store raw, escape at render time.
- `url_path` is stored without query string or fragment.
- This is the code Sobelow cares most about. Every finding here is either fixed or
  carries a `# sobelow_skip` with a written reason. Missing CSRF on this pipeline is
  intentional and documented; anything else flagged is presumed real until proven otherwise.

## Visitor identity

```
visitor_hash = sha256(daily_salt <> site_id <> ip <> user_agent)
```

- The salt is **random**, not derived. A salt derived from a long-lived secret is
  recomputable forever by anyone holding that secret, which makes the identifier
  pseudonymous rather than anonymous. A random salt that is deleted makes past
  identifiers permanently unlinkable — that is the whole privacy claim.
- Salts live in Postgres so they survive restart, with current and previous held in
  memory. Rotate lazily on the first request of a new UTC day; delete salts older
  than 48h opportunistically. **No scheduler and no Oban dependency required.**
- Keep the previous day's salt so a response submitted just after midnight can still
  be matched against the same visitor's earlier activity.
- Raw IP and user-agent are used in-request only. They are never written to the
  database, to logs, or to disk.
- The client's `visitor_id` in `localStorage` is for cooldown checks on the device
  and **must never be sent to the server**. If a request body contains it, that is a bug.

`visitor_hash` supports same-day deduplication only. Long-horizon cooldown is
enforced client-side and is best-effort by design.

## Deletion paths

`responses` rows are never mutated in place, but three deletion paths exist and must
be implemented explicitly — an absolute no-delete rule would make erasure requests
and account closure impossible.

1. **Tenant deletion** — remove all rows for an `org_id` on account closure.
2. **Comment redaction** — set `comment = NULL` and stamp `redacted_at`. The score
   survives; it carries no personal data.
3. **Retention expiry** — delete rows older than the site's `data_retention_days`.

Each path is a named function in `Litenps.Collect`, logged, and never invoked from
a request handler on the public pipeline.
