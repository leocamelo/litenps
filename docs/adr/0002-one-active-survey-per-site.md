# 2. A site has at most one active survey

- **Date:** 2026-09-21
- **Status:** Accepted
- **Affects:** `docs/ARCHITECTURE.md` §4 (`Litenps.Surveys`), §5 (`/v1/config`)

## Context

`/v1/config` answers with *the* active survey for a site (§5), and the loader
either gets one survey or stops (§6). Nothing in the schema forced that to be
true: `surveys` could hold several rows with `status = :active` for one site,
in which case the endpoint would pick one arbitrarily.

Two active surveys with different targeting is a plausible product case — one
question on `/pricing` for desktop, another in the app on mobile — so the
question was whether to allow it now.

## Decision

A partial unique index, `surveys_one_active_per_site`, on `site_id` where
`status = 'active'`. The changeset maps the violation onto `:status` with a
readable message, so the dashboard reports the conflict rather than crashing.
Pausing or returning a survey to draft frees the slot.

Multiple active surveys are **not** ruled out for the future. They are ruled out
until the questions below have real answers.

## Consequences

- The endpoint has exactly one row to serve, which is what makes its response
  cacheable per key with an `ETag`.
- Two concurrent activations cannot both succeed. The check is in the database,
  not in a read-then-write in the context.
- Segmenting one site by page or device needs several sites today, which is
  clumsy but correct. Nobody has asked for it.

## What relaxing this would cost

The storage model already supports it — targeting lives per survey — so the
migrations are cheap and additive: drop the partial index, and add a `priority`
integer with a default (both metadata-only, no data rewrite). The real cost is
semantic, and these are the questions that must be answered first:

1. **Which survey wins** when a visitor matches two. Hence `priority`.
2. **What cooldown applies.** `cooldown_days` is per survey. With two active
   surveys a visitor could answer one on Monday and be asked by the other on
   Tuesday — each survey respecting its own cooldown, the visitor experiencing
   harassment. A site-level cooldown is likely needed alongside the per-survey one.
3. **Whether `/v1/config` still caches per key**, since today it is cacheable
   precisely because there is one answer per site.

Keeping the index is what stops the ambiguous state from being entered by
accident while those answers do not exist. The alternative is not "more
flexibility" but a silent arbitrary choice that surfaces as a customer asking
why the wrong question is showing.

## Related

If i18n is done as one survey per locale rather than as translations on one
survey (see `docs/adr/0003-survey-text-i18n.md`), this index becomes unique on
`(site_id, locale)` rather than being dropped.
