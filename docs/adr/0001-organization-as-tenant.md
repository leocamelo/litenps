# 1. The organization is the tenant, and a user belongs to exactly one

- **Date:** 2026-09-03
- **Status:** Accepted
- **Affects:** `docs/ARCHITECTURE.md` §4 (`Litenps.Accounts`), rule 6 in `CLAUDE.md`

## Context

`ARCHITECTURE.md` §4 states that the tenant is the org and that every
tenant-owned table carries `org_id`, but it does not say how a user relates to an
organization. Phase 1 cannot proceed past `Accounts` without settling it: `sites`
is the first tenant-owned table, and the shape of `Litenps.Accounts.Scope`
determines the signature of every context function written afterwards.

Two properties were wanted:

1. **No organization picker.** Logging in must land the user in their
   organization. An account switcher is interface surface, a session concern, and
   a class of "wrong tenant" bug that a single maintainer should not have to own.
2. **Room for several users in one organization, with membership levels**, when
   invites eventually arrive.

## Decision

An `orgs` table (schema `Litenps.Accounts.Org`), and `users.org_id` (not
null). A user belongs to exactly one organization. The organization is created in the same transaction as
the user at registration, named after the email local-part and renameable
afterwards.

The code says `org` throughout — `Org`, `orgs`, `org_id`, `scope.org` — so
the schema, the table and every foreign key share one name. Prose may still say
"organization".

`Litenps.Accounts.Scope` carries both:

```elixir
%Scope{user: %User{}, org: %Org{}}
```

`Scope.for_user/1` raises when handed a user whose organization is not loaded.
Every path in `Litenps.Accounts` that can feed a scope preloads it, so a scope
that cannot name its tenant is unconstructible rather than merely discouraged.

Roles are deliberately **not** added yet. The expensive-to-reverse decision is
where `org_id` lives; a role column is a one-line reversible migration, and
adding one now with a single `:owner` value would be Phase 5 work leaking into
Phase 1.

## Consequences

- Requirement 2 is already satisfied: an organization has many users. Invites
  need an invite flow and a `role` column, not a schema change to the tenant
  boundary.
- Requirement 1 is satisfied *by construction*, not by convention. With one
  organization per user there is nothing to pick, so no code path exists that
  could pick wrong.
- The same human needing two organizations must use two accounts with two email
  addresses. This is the direct price of having no switcher, and it is the normal
  arrangement in small B2B products.
- Registration is now a transaction over two tables. The user changeset is
  validated before the organization is inserted, so an invalid email still comes
  back as an error on the form's changeset.

## Alternatives considered

**`org_memberships` join table.** The textbook model, and the natural home for a
role. Rejected because the only thing it buys over `users.org_id` is one user in
several organizations — which is exactly the case that forces the picker
property 1 rules out. Under that constraint its flexibility is unusable, while
its cost (a join on every scope resolution, plus "which organization is current"
becoming session state) is paid on every request.

The escape hatch stays cheap for the same reason. If one human ever genuinely
needs two organizations, `org_memberships` gets introduced then — but that is the
same moment the switcher has to be built anyway, so the migration rides along
with interface work that would be required regardless. Under the no-picker
constraint, the future migration cost of this decision is zero; it is only paid
when the constraint itself is abandoned.

**No orgs table; the user is the tenant.** `org_id` would hold a user
id. Rejected: the column name would lie, and introducing a real organization
later means backfilling `org_id` across every tenant-owned table — including
`responses`, which by rule 1 is immutable and by §7 is the one table whose
rewrite has real consequences.
