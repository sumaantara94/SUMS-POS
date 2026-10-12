# SUMS POS v0.2

Dedicated repository and Supabase project for POS, separate from SUMS Studio.

## Online workspace

Email/password login, business onboarding and personalization, owner/cashier/waiter permissions, custom permission assignment to registered staff, persistent catalog, atomic order stock reservations, idempotent cash settlement, cancellations and stock/audit ledgers. Database operations use RLS and permission-checked private functions. Browser receives only a publishable key.

Automatic refresh currently polls every 15 seconds; event-based realtime is not implemented yet. Order history currently loads the latest 1,000 records. Reports summarize only the loaded records using device-local today/rolling 7/30-day boundaries; full calendar reporting is not yet implemented. This limit must be removed before production reporting.

## Demo

Choose “Lihat demo tanpa login” for browser-local sample data. Demo roles are simulations; online roles are enforced in the database.

## Checks and build

Node.js 20+ and Python 3, no npm dependencies.

```sh
npm run check
npm test
npm run build
npm run dev
```

Static output: dist/. Database schema: database/001_core.sql (already applied to the dedicated project). Database tests: tests/database.sql — transactional fixtures are rolled back. Do not apply the initial schema twice.

## Before real use

End-to-end browser and email confirmation tests, deployed auth Site URL/redirect configuration, calendar reporting, concurrent API load tests, offline strategy, printer hardware tests and backup/restore remain outstanding. Browser print works through the device print dialog; direct Bluetooth is not implemented. Payments record cash only; no QRIS/card payment processing. Staff must register before an owner grants membership; no invitation email is sent. No CI workflow enabled.
