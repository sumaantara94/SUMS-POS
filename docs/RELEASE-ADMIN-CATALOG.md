# SUMS POS Admin Catalog Role

Status: implementation proposal in PR; requires migration before release.

## What this role can do

The Owner can create an **Admin Back Office** account from the existing staff-management form. In this first, deliberately narrow slice, Admin can access the product/catalog screen and use the existing product permission to manage the catalog. Admin cannot open POS, orders, sales reports, cash reconciliation, outlet management, staff management, or owner-only settings.

The account uses the existing staff username/password login. After authentication, the app routes it into the Back Office catalog screen while keeping the staff-login URL so a reload or expired session still presents the username login form.

## Database and authorization

Apply `database/032_admin_catalog_role.sql` once to the dedicated SUMS-POS Supabase project after migrations 001–031 and the existing supplemental SQL files that the project already uses. Do not re-run the initial schema. The migration adds `admin` to the membership role constraint and updates the staff-finalization RPC so Admin receives only `['products']`.

The existing database `pos_private.allowed` function and RLS policies remain the authorization boundary. This is not just a hidden navigation item: the Admin membership is not granted `orders`, `reports`, `dashboard`, `pay`, or `settings` permissions. The Owner remains the only actor who can provision staff.

## Validation

The PR adds tests for the staff provisioning flow and the role's narrow permission assignment. Before release:
1. Run GitHub Actions syntax, unit tests, and static build.
2. Apply the migration to a non-production/test Supabase project first.
3. Verify Admin can create/update a product.
4. Verify Admin cannot read paid orders/payments or invoke Owner-only RPCs directly.
5. Verify Owner, Cashier, and Waiter flows remain unchanged.

This migration is not applied automatically by the GitHub workflow and no production Supabase schema is changed by merging the code.
