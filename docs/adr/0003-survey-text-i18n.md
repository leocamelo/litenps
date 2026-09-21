# 3. Survey text stays single-language, and i18n is additive when it comes

- **Date:** 2026-09-21
- **Status:** Accepted — deferred, with the shape chosen in advance
- **Affects:** `docs/ARCHITECTURE.md` §4 (`Litenps.Surveys`)

## Context

`question` and `followup_question` are `varchar` columns holding one string
each. A customer with a multi-language site will eventually want the question in
the language of the page it appears on.

Since the project has no production data, converting the columns to a map now
would be free in migration terms. The question was whether to do it now or later.

## Decision

Leave both columns as single strings. When i18n is needed, add a column rather
than convert one:

```elixir
# question stays as the default-locale text
add :translations, :map, null: false, default: %{}
# %{"pt-BR" => %{question: ..., followup_question: ...}}
```

Validation goes in an embedded schema, as `Litenps.Surveys.Targeting` already
does for the targeting blob.

## Rationale

**The shape is still a guess.** Locale keys as `pt` or `pt-BR`; whether `pt-PT`
falls back to `pt` and then to a default; whether the default is per survey or
per site; and whether the widget picks the locale from `Accept-Language`, the
host page's `<html lang>`, or something explicit in the snippet tag. Those are
Phase 3 and product decisions. A guessed structure with code written against it
is harder to change than a plain column.

**Every reader would pay immediately.** As a map, `survey.question` needs a
locale and a fallback at every call site — the dashboard list and form, then
`/v1/config` in Phase 2, later exports and the public report — and the form
becomes an add/remove-locale repeater. That is Phase 1 work for a feature with
no user.

**"No data" removes the wrong objection.** The additive column above needs no
backfill and no rewrite *even once there is data*, so converting early buys
almost nothing later.

**The additive shape is also the better one.** With `question` plus
`translations`, a non-null default always exists, so "requested locale missing"
has an obvious answer. A pure map needs a rule for "no matching key and no
default", and `/v1/config` sits on the critical path of the customer's own page —
a poor place to discover an empty string.

## Alternatives

**Convert `question` to a map now.** Rejected above. Note that once there is
data this becomes a genuine data migration in which every reader changes at once.

**A `survey_translations` table.** The better choice if translations ever need
their own workflow — per-locale review or publishing. It costs a join on the
serving path, which the jsonb column avoids.

**One survey per locale, with a `locale` column.** Viable, and it interacts with
`docs/adr/0002-one-active-survey-per-site.md`: the active-survey index would
become unique on `(site_id, locale)`.

**Reusing `theme`.** Rejected. It is untyped and meant for styling; user-facing
copy there loses validation and length limits.

## Revisit when

The locale-selection rule is settled and fixed — at that point the shape is no
longer a guess. Likely alongside Phase 3, when the widget learns what language
the host page is in.
