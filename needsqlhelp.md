# Supabase SQL Help Request

Please inspect the existing Supabase schema and return a reviewed SQL migration
for the inquiry-review workflow and its required access controls. Do not run
production changes until the app owner has reviewed the proposed migration.

## Verified application contract

- The Flask admin calls the authenticated Supabase RPC
  `review_tenant_inquiry` with:
  - `p_inquiry_id` (UUID)
  - `p_decision` (`approve` or `decline`)
  - `p_assigned_unit_id` (UUID or `NULL`)
  - `p_internal_note` (text, maximum 2,000 characters)
- The related tables used by the app are `tenant_inquiries`, `units`, and
  `tenants`. The app reads inquiry fields including `status`, `assigned_unit_id`,
  `tenant_id`, and `internal_note`; unit fields include `status`, `is_archived`,
  and `tenant_id`.
- The app's unit statuses include `Vacant`, `Occupied`, `Reserved`, and
  `Inactive`. The UI offers only non-archived `Vacant` units without a
  `tenant_id`; the RPC must repeat that check in the database.
- The review page currently allows `p_assigned_unit_id = NULL`. Do not make a
  unit mandatory for approval unless the owner confirms that business rule.
- The app uses the signed-in Supabase user's access token for this RPC; do not
  require or expose a service-role key.
- Record archiving in the app is a soft update of `is_archived`; preserve that
  behavior and existing history.

## Inspect before proposing changes

1. Confirm the exact columns, types, constraints, triggers, and foreign keys on
   `tenant_inquiries`, `units`, `tenants`, and `audit_logs` (if present).
2. Read the current definition, grants, and security mode of
   `review_tenant_inquiry`, plus the RLS policies on those tables.
3. Confirm how an authenticated user is recognized as an approved
   super-admin. Reuse the app's existing identity/role model; do not assume a
   new role table or trust client-supplied actor IDs.
4. Report any mismatch between the live schema and the application contract
   above before generating SQL that depends on a different name or type.

## Required inquiry-review behavior

Update or replace the existing RPC without changing its public argument names.
Within one database transaction, it must:

1. Verify the caller is an authorized, approved super-admin.
2. Lock and re-read the inquiry, and allow a decision only while it is still
   pending. Reject repeated or stale reviews without partially changing data.
3. Accept only `approve` or `decline`; validate the note length server-side.
4. If a unit ID is supplied, lock and re-read that unit and require it to be
   non-archived, `Vacant`, and unassigned to a tenant at the time of the
   transaction. Reject occupied, reserved, inactive, archived, missing, or
   concurrently claimed units.
5. Apply all existing approval/decline side effects (including tenant creation
   and inquiry/unit links, if that is what the current function does)
   atomically. If any step fails, roll back every step.
6. Preserve approval without a unit unless the owner separately confirms that
   a unit is mandatory.
7. Record a minimal business audit event if the current audit schema supports
   it. Include the actor and inquiry/decision identifiers where available, but
   never copy the internal note or other sensitive contents into audit details.

## Required access controls

- Enable or retain RLS on the relevant tables and write narrow policies that
  match the existing approved-super-admin authorization model.
- Permit the app's authenticated admin to read the inquiry and eligible unit
  data it already needs. Limit inquiry/tenant/unit writes to the approved
  review workflow and other existing authorized app operations.
- Do not add broad `USING (true)` or `WITH CHECK (true)` policies, and do not
  grant anonymous users access to private inquiry, tenant, or unit data.
- Prefer an invoker-security function that obeys RLS. If elevated privileges
  are required, explain why and harden the function: fixed `search_path`,
  explicit caller authorization, revoked `PUBLIC`/`anon` execution, and an
  explicit grant only to the intended authenticated role.
- If `audit_logs` exists, allow authorized reads and trusted append-only writes;
  deny updates/deletes to application roles. Do not break the existing
  read-only audit-history page.
- Inventory other app-used public tables for missing RLS and report them
  separately. Do not enable RLS across the whole schema without first proposing
  policies that preserve the app's required access.

## What to return for review

- A schema/policy/function inventory and any assumptions.
- One migration SQL file with safe ordering, explicit grants/revokes, and
  comments explaining security-sensitive choices.
- Verification SQL or reproducible checks for:
  - approved super-admin review;
  - unauthorized and anonymous calls;
  - invalid decision and stale/non-pending inquiry;
  - no-unit approval;
  - occupied, archived, missing, and concurrently claimed unit;
  - rollback when tenant creation or assignment fails;
  - two concurrent approvals attempting to claim the same unit;
  - append-only audit behavior, if supported.
- Confirmation that no service-role key, raw internal note, or unnecessary
  personal data is exposed or logged.
