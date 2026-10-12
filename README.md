# SUMS POS

Dedicated web POS project for independent businesses, separate from SUMS Studio.

## v0.1 interactive demo

- Owner dashboard with sales totals and seven-day chart.
- Catalog, pricing, available stock and active/inactive products.
- Cashier/waiter order entry and stock reservation.
- Cash settlement with change calculation; owner cancellation restores stock.
- Browser receipt/order printing and CSV sales export.
- Browser-local business workspaces and brand personalization.
- Role simulation for owner, cashier and waiter.

**This is a browser-local demo, not a production authenticated POS.** Data stays in localStorage on the current browser. The role picker does not enforce security. Seed transactions are sample data. Cash payments are only recorded, not processed. Bluetooth direct printing, dedicated database, sign-up/authentication, staff invitations, custom roles and cross-device realtime are not connected yet. Reports currently use today/rolling seven/rolling thirty days, not calendar week/month.

## Run and check

Requires Node.js 20+ for checks and Python 3 for the local server. No npm dependencies.

```sh
npm run check
npm test
npm run build
npm run dev
```

Open http://localhost:5173 . Static deployment output is `dist/` after building. No CI workflow is enabled.

Try: Online POS → select product → save order → Orders → Pay → enter cash → Reports. Switch to waiter to see order-entry permissions; switch to owner for catalog and workspace settings.

See [infrastructure contract](docs/ARCHITECTURE.md) for the dedicated backend, tenant isolation, payment/inventory transactions and deployment gates. Database and hosting must remain independent from SUMS Studio.
