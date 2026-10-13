# Owner-approved item refunds

A cashier/owner can request one, several or all full item lines on a Complete bill, with a mandatory reason and optional inventory return. Pending, approved and completed item lines cannot be requested twice; rejected selections can be requested again. The original invoice/lines/payments stay immutable. An approved item is visibly marked, not physically erased.

Owner Back Office dashboard has a live Refund approvals card showing pending item names/quantities, reason, cashier and amount. Review shows the original discounted net, allocated tax/service and restock choice. Only owner membership can approve/reject; rejection needs a note. Approved requests require a separate cashier/owner confirmation that money has actually been returned. Noncash records require a reference. No payment-provider transfer is performed automatically.

Reports → Refunds lists states, details and period CSV export; only completed refunds reduce net collections. Sales, category and gross-profit figures are explicitly labelled before refunds. Completed bills show partial/full refund markers, and printed original receipts disclose completed refunds and remaining payment. Original completed invoices remain in Complete; refunded records are separately auditable.

Migration 020 creates a tenant-scoped, read-only refund table and invoker public RPC wrappers backed by private functions. Order locks serialize requests and prevent overlapping items, duplicate completion and double stock return. Full-line fee allocation uses cumulative rounding against original bill snapshots so partial requests sum exactly to the original discounted total. Refunds emit the existing tenant Realtime invalidation feed. Business API/auth data remain uncached; no paid services are added.

Validation: 32 Node tests and syntax/static build checks; rolled-back database suite verifies owner-only decisions, required reason/rejection note/reference, direct-write denial, waiter and outsider restrictions, exact fee/discount allocation, retry/overlap protection, partial-to-full refunds, immutable invoice and optional exactly-once stock return. No test fixtures persist. Security advisor notices remain the existing private PIN tables/no read policies and disabled leaked-password protection. Browser/device acceptance and actual money transfer remain outside this verification.

Current catalogue/history APIs still load the most recent 1,000 invoices/refund requests. Refund quantity selection is by full original line, not individual units within a multi-quantity line.
