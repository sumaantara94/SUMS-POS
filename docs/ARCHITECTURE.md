# Infrastructure contract

## Current v0.1

Buildless browser preview with localStorage; UI role selector is a demonstration, not authentication. Multiple browser-local business records, product catalog, available stock reservation, open orders, cash settlement, cancellation, receipts, rolling 1/7/30-day sales exports. Seed sales are explicitly demo records. No CI workflow, external database or payment keys are configured.

## Production implementation

Back office and POS share domain services but have different routes and permission checks. Recommended deployment: static frontend with a dedicated API and PostgreSQL project, entirely separate from SUMS Studio. Database provider and hosting account are still to be selected.

Entities: businesses, outlets, users, memberships, roles, permissions, role_permissions, products, outlet_inventory, orders, order_lines, payments, stock_movements, cashier_shifts, audit_events, print_jobs.

Every operational record carries business_id and outlet_id. The API derives allowed tenants from authenticated membership, never from an unvalidated browser ID. Server-side policies control reading and mutation; role configuration and invitations are owner-only. Waiters create orders; cashiers settle them; owners manage the business. Multi-outlet roles are scoped explicitly.

Store IDR amounts as whole-rupiah integers, quantities as validated units, and timestamps in UTC with business-local reporting boundaries. Snapshot product names and prices into order lines. Keep immutable stock movements and payment ledger. Database transactions lock inventory rows and validate order state; idempotency keys prevent repeated payments, double stock movements and repeated webhook settlement. Broadcast committed changes only to authorized tenant subscribers.

Separate open-order reservations from stock-on-hand and support expiry/release policies. Refunds need an explicit ledger and inventory decision; never overwrite paid orders. Implement fiscal calendar daily/weekly/monthly reports, timezone configuration, shifts, discounts/taxes, service charges, variants and service products in later increments. v0.1 rolling 7/30-day reports are not calendar-week/month reports.

## Printing

v0.1 uses browser print with receipt-sized styles; actual Bluetooth communication is not implemented. Validate device OS, browser and printer model/protocol before choosing a native bridge, network print gateway or supported browser API. Do not promise universal Bluetooth compatibility. Track job ID, retries and completion separately from sales; printing failure must not reprocess payment.

## Deployment gates

Dedicated database selected; auth/RLS or equivalent server policies; cross-tenant access tests; concurrent stock and settlement tests; backup/restore test; printer hardware test; payment sandbox verification; owner acceptance. No real customer transactions until these gates pass.
