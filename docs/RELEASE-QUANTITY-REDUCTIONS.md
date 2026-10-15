# Cashier item quantity reductions

POS login logo is smaller and aligned right inside the login card.

Cashiers/owners can remove a chosen quantity or all remaining units from an open bill using the existing six-digit authorization PIN configured by the owner. Server recalculates menu subtotal, service, tax and stock in one locked transaction; every reduction writes immutable quantity-before/removed/after, amount, item, actor, timestamp and mandatory reason. Request UUID prevents duplicate reductions. Queued kitchen tickets are updated and printed tickets receive quantity correction slips.

Paid item reductions require the same PIN, then owner approve/reject. Requests specify per-line quantities. Original invoice/payment snapshots remain unchanged; only completed refunds affect net collections and restocking. Cumulative integer allocation conserves original discounts, service and tax across sequential partial refunds. Owner approval remains required before actual refund recording. The legacy PIN-free refund endpoints are revoked. Existing pending/approved requests remain reviewable and completable.

Reports → Cancel/Voids includes Open order reductions with CSV. Reports → Refunds records requested quantity, reason, requester, owner decision/note, refunded amount, refund recorder/time/method/reference. Financial logs are tenant/permission scoped and client writes are revoked.

Verification: rollback-only SQL integration covers invalid PIN, atomic quantity/stock/totals, retry idempotency, full removal, partial paid refunds, approval before completion, cashier self-approval denial, waiter/foreign-tenant denial, immutable logs, legacy bypass denial, discount/fee rounding and shared PIN throttling. Node tests include partial refund state. Security advisories match existing notices; no new exposed data or mutable search paths. Physical printers and direct phone layout are not verified.
