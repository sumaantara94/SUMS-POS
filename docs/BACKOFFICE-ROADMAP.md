# Back Office and POS Online specification

User direction 2026-10-12: order creation belongs only in POS Online. Back Office manages business operations. The current release separates navigation using `?app=office` and `?app=pos`; both share authenticated tenant data. This is an application-surface separation, not a replacement for database permissions.

## Official competitor references reviewed

- Moka Library: https://help.mokapos.com/materi-3-mengisi-library-di-backoffice — catalog, variants/modifiers, category maintenance, percentage/fixed/free-item promotions, schedules, sales types, stock threshold, COGS, taxes and service charges.
- Moka shift reporting: https://help.mokapos.com/cara-melihat-laporan-shift?post_type=product — actual cash and noncash shift totals.
- Olsera: https://www.olsera.com/en/pos/features — table layout/numbering, split/merge bills, kitchen/bar printing, kitchen display, ingredient inventory, transfers, loyalty, staff access and transaction-change visibility.
- majoo: https://majoo.id/produk/ and https://majoo.id/Perangkat — inventory, CRM, employee management, cashier shifts, attendance, commissions and accounting. Features may depend on package and platform.

## Module contracts (planned, not implemented)

### Promotions

Percentage/fixed discounts, voucher codes, minimum spend, maximum discount, start/end schedule, outlet and product/category applicability, usage quota, stacking rules and approval for manual overrides. Server calculates and snapshots subtotal, discount, taxes/service and net total. Lock quota/redemption rows; never trust the browser-displayed total. Reserve redemption at order submission; release on eligible cancellation; settle once on payment. Historical receipts retain the original rule and amounts after promotions change.

### Categories and products

Keep business type (retail/FnB/service) distinct from product categories (drinks, pastry, services). Category records persist independently of existing products, have stable IDs, may be renamed/archived and stay available when creating later products. Renaming must not rewrite historical order-line descriptions. Product templates may follow business type without forcing fixed categories. Add SKU/barcode, variants, modifiers, purchase cost and stock-tracking flag for services.

### Inventory

Product-specific reorder thresholds, stock adjustment reasons, stock opname, supplier/purchase receiving, purchase orders and outlet transfers. FnB supports recipes/ingredients and waste. Low-stock dashboard plus owner-email notification settings with threshold-crossing detection, cooldown and deduplication. Queue mail jobs durably; email failure must not roll back sales. Notification recipient and provider credentials are backend-controlled. Email provider is not yet configured; no notification email has been sent.

### Staff

Employee records, account membership, custom permission bundles, assigned outlets, attendance, schedules, PIN-based operational access where appropriate, commissions and performance summaries. Authorize refund/discount/stock overrides separately. Preserve audit history after deactivating staff; never infer permissions from editable profile metadata.

### Tables

Back Office configures areas, table names/numbers, capacity and active status. POS selects tables, creates orders and changes operational occupancy. Transfers/merge/split must preserve item/payment ownership and be atomic. No fixed text entry as the sole table source once management is introduced.

### Shifts and reports

Back Office configures opening cash rules, close-shift requirements, recipients, daily delivery schedule and business timezone. POS opens/closes cashier shifts and records actual cash count. Report contains opening float, cash/noncash sales, cash-in/out, refunds, discounts, expected cash, actual cash and variance. Distinguish close-shift summaries from daily calendar totals. Query complete server-side data with timezone-aware periods; remove frontend 1,000-order reporting dependency.

### Other operational modules

Customer CRM/loyalty, refunds and approval trails, taxes/service charges, price lists, multi-outlet overview, kitchen display, printer routing, stock aging, product gross margin and category performance. Accounting/payroll and procurement automation follow after sales/inventory/shift ledgers are reconciled.

## Delivery order

1. App separation (implemented in this update), master categories, table master, richer staff navigation.
2. Promotion engine with server-side pricing and quota tests; shift ledger and complete calendar reports.
3. Notification settings, durable email queue/provider and owner reports after closing shifts.
4. Supplier/purchases/opname/recipes, customer loyalty and refund controls.
5. Realtime subscriptions, offline sync and verified printer integrations.

Acceptance examples: new product can choose a category created last week; expired voucher rejected on server; two concurrent last-quota redemptions cannot both succeed; revoked employee cannot access another outlet; repeated closing does not send duplicate reports; stock alert sends once per threshold event; back office exposes no new-order screen.
