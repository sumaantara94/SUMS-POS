# SUMS POS · Restaurant operations

## Current infrastructure — 15 October 2026

Device-local orders/cash settlement, durable sync queue, cashier shifts, cash movements/expenses and a basic Owner Brief are implemented. See [offline and cash operations release notes](docs/RELEASE-OFFLINE-CASH.md) for exact setup, permissions, validations and limits. Earlier milestone notes below are historical. Offline reporting across midnight, mobile airplane-mode verification, physical printers and full accounting still need separate validation/development.


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

End-to-end browser and email confirmation tests, deployed auth Site URL/redirect configuration, calendar reporting, concurrent API load tests, offline strategy, printer hardware tests and backup/restore remain outstanding. Browser print works through the device print dialog; direct Bluetooth is not implemented. Payments record cash only; no QRIS/card payment processing. Owner creates staff using name, unique username, password and cashier/waiter role; no staff email confirmation is required. No CI workflow enabled.

## Restaurant flow

Back Office → Pengaturan bisnis configures Restaurant mode, waiter, a cancellation PIN, area/layer table maps and timed checkout discounts. Waiter selects table then guest before menu. Item notes and category print jobs are saved atomically on submit. Cashier loads orders, applies currently valid discounts, or cancels with PIN and reason. Net reports subtract allocated discounts. See docs/RELEASE-RESTAURANT.md for setup, validation and current limits. Migrations 001–010 are applied to the dedicated project; do not reapply. Reload old tabs for the current RPCs.

## Seating and payment methods

Red open-bill tables show elapsed time; orange reservations are controlled by cashier/owner and block waiter seating. Cashier has sales/payment reports. Back Office sets tax/service for new orders. Cash, credit/debit card, QR, transfer, other and split tender are supported as manually confirmed records. No payment gateway authorization is performed. See docs/RELEASE-SEATING-PAYMENTS.md. Migration 012 is applied.

## PWA / Realtime

Android install controls, fullscreen and a fixed POS shell are implemented. Workspace changes synchronize through an authenticated Supabase event feed, with a recovery refresh. The original static-only shell has been extended with the device outbox described above. See docs/RELEASE-PWA.md for validation and audience/install limits.
