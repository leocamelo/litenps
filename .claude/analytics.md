---
paths:
  - "lib/litenps/analytics/**"
  - "lib/litenps/analytics.ex"
---

# Analytics rules

Read-only context. It queries `responses` and computes metrics. It never writes.

## The Stats boundary

All NPS math lives in `Litenps.Analytics.Stats` — score, promoter/passive/detractor
split, trend, percentiles, confidence interval. No statistical calculation may
appear in a query, a LiveView, or a template.

This boundary is the whole point: it lets the implementation be replaced later
(see `docs/ARCHITECTURE.md` §Deferred) without touching anything else. Keep the
functions pure — take a list or a stream of scores, return a struct. No `Repo`
calls inside `Stats`.

Every public function needs `@spec` and a property-based test.

## Queries

- Read `responses` directly. **Do not add a rollup or materialized table.** With an
  index on `(site_id, inserted_at)` Postgres answers these in milliseconds at any
  volume this project will realistically see.
- If a dashboard query exceeds ~200ms on production-shaped data, that is the signal
  to reconsider — record the measurement in `docs/adr/` first.
- Aggregates are always recomputable from raw rows. Never introduce a number that
  cannot be rederived.

## Correctness

- NPS is `%promoters - %detractors`, rounded to an integer, range -100..100.
  Promoters are 9-10, passives 7-8, detractors 0-6.
- With a small sample the score is noise. Always return the sample size alongside
  the score, and have the dashboard surface it. Do not display a score without `n`.
- Timezone: bucket by the site's configured timezone, not UTC, or trends will be
  off by a day for most customers. Store UTC, convert at query time.
