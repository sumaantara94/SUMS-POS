# Supabase Data API table grants audit (October 2026)

## Scope and status

This note records the preventive review prompted by Supabase's notice that, starting October 30, 2026, newly created tables in the `public` schema will no longer receive automatic Data API grants.

Read-only queries run against the SUMS POS Supabase project reported:

- 22 tables in schema `public` at the time of the snapshot.
- RLS enabled on all 22 tables.
- `anon` had no effective SELECT, INSERT, UPDATE, or DELETE privileges on those 22 tables.
- `authenticated` had SELECT on all 22 tables and no direct INSERT, UPDATE, or DELETE privileges on those 22 tables.
- `relforcerowsecurity = false` for the tables. This is not, by itself, a finding that application-role RLS is disabled; table owners and privileged roles have different RLS behavior.

These results are a snapshot, not a live guarantee. They do not audit RPC execute privileges, sequences, views, storage policies, schema usage, default privileges, or migrations applied after the snapshot. Re-run the queries after schema changes.

## Decision

Do **not** apply a blanket `GRANT ALL`, and do not grant broad access to `anon`. SUMS POS routes writes through permission-checked database functions, so direct table writes should remain denied unless a specific feature has been designed and reviewed to require them.

No production SQL change is included in this document. The current snapshot did not show a reason to change the grants on the 22 existing public tables solely because of this notice. The prevention point is every future table-creating migration.

## Required checklist for each new table in `public`

1. Create the table.
2. Enable RLS immediately.
3. Add policies for the intended authenticated business/workspace roles.
4. Explicitly revoke direct privileges from `PUBLIC`, `anon`, and `authenticated`.
5. Grant only the required operations to the intended role. For tables read through the app, this may be `SELECT` to `authenticated`; use no direct write grant if writes must go through RPCs.
6. Review any function that reads or writes the table, including its `SECURITY DEFINER` status, fixed `search_path`, ownership, and EXECUTE grants.
7. Add or update tests and validate the migration on a staging project before production.

## Example: RPC-only table

Adapt names and policies to the actual feature. This is a pattern, not a migration to run unchanged.

```sql
CREATE TABLE public.example_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id uuid NOT NULL REFERENCES public.pos_businesses(id)
);

ALTER TABLE public.example_records ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.example_records
  FROM PUBLIC, anon, authenticated;

-- If the app needs direct reads, add a narrow policy and grant SELECT:
-- CREATE POLICY example_records_read
--   ON public.example_records FOR SELECT TO authenticated
--   USING (pos_private.allowed(business_id, 'reports'));
-- GRANT SELECT ON TABLE public.example_records TO authenticated;

-- For RPC-only access, keep direct table grants revoked and expose
-- only reviewed public RPC functions with EXECUTE granted to authenticated.
```

Avoid copy-pasting a generic policy without confirming the feature's required permission and tenant isolation.

## Read-only verification queries

### RLS status

```sql
SELECT n.nspname AS schema_name,
       c.relname AS table_name,
       c.relrowsecurity AS rls_enabled,
       c.relforcerowsecurity AS rls_forced
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind IN ('r', 'p')
ORDER BY c.relname;
```

### Effective table privileges

```sql
SELECT c.relname AS table_name,
       r.role_name,
       has_table_privilege(r.role_name, c.oid, 'SELECT') AS can_select,
       has_table_privilege(r.role_name, c.oid, 'INSERT') AS can_insert,
       has_table_privilege(r.role_name, c.oid, 'UPDATE') AS can_update,
       has_table_privilege(r.role_name, c.oid, 'DELETE') AS can_delete
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
CROSS JOIN (VALUES ('anon'), ('authenticated')) AS r(role_name)
WHERE n.nspname = 'public'
  AND c.relkind IN ('r', 'p')
ORDER BY c.relname, r.role_name;
```

### Review RPC EXECUTE grants too

Table grants do not prove RPC security. Inventory public functions and effective EXECUTE grants separately before declaring the audit complete. In particular, review all newly introduced public RPC wrappers and ensure untrusted roles cannot execute private implementation functions.

## Release gate

Before merging a future migration that creates a `public` table, require a reviewer to confirm RLS, policy intent, explicit table grants/revokes, function EXECUTE privileges, and tenant-isolation tests. After applying it to staging, rerun both verification queries and exercise login, checkout, refunds, shifts, reporting, and offline/LAN sync flows relevant to that migration.
