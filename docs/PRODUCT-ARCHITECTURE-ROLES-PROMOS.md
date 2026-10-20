# SUMS POS Product Architecture: Roles, Outlets, Promotions & Recipes

Status: product/engineering proposal for review
Date: 2026-10-19
Scope: SUMS POS only. This document does not claim the proposed capabilities are already implemented.

## Product principles

1. Keep cashier workflows fast and understandable for small F&B businesses.
2. Enforce permissions on the server/database, not only by hiding UI controls.
3. Separate configuration, transaction execution, financial visibility, and approval authority.
4. Every stock or money-affecting mutation must be atomic, idempotent where retries are possible, and auditable.
5. Use capability/entitlement configuration for tier limits instead of scattering hard-coded plan checks through UI code.
6. Do not activate GitHub Actions or paid infrastructure as part of this proposal.

## Roles and permission boundaries

### Owner
- Full access to the business and its authorized outlets.
- Manage subscription/tier, outlet entitlement, staff and roles, permission assignment, approval policies, report visibility, email recipients, and security settings.
- View sales dashboards, reports, cash reconciliation, audit events, and cross-outlet comparisons.
- Approve sensitive actions and configure who may request them.
- May delegate operational work without delegating owner-only approval or billing authority.

### Admin (Back Office Admin)
- Manage catalog: products, categories, variants/modifiers, menu availability, prices, and product imports.
- Manage restaurant setup: table areas/layout, waiter workflow, kitchen/bar routing, receipt and cashier operational settings supported by the system.
- Manage promotions: discount rules, special-promo schedules, and packages/bundles.
- Growth/Premium only: manage recipes, ingredients, units, and recipe-to-stock mappings.
- Manage operational stock records and perform permitted adjustments with a required reason and audit trail, subject to owner-configured limits.
- View operational configuration needed to do the job.
- MUST NOT access sales dashboard, sales/financial reports, cash reconciliation, owner analytics, or approval queues.
- MUST NOT approve refunds, paid-order reversals, exceptional discounts, cash variances, or other approval-gated actions.
- MUST NOT change plan/billing, outlet entitlements, owner account, or role/permission assignments.
- By default, does not receive sales-report emails. Report recipients are explicitly configured by the Owner.
- Admin may configure discounts/promotions, but cannot bypass checkout rules or approve an exception to those rules.

### Cashier
- Use POS, view and fulfil orders within assigned outlet(s), collect supported payments, and close own shift where permitted.
- Apply only active, eligible promotions and discounts allowed by server-side rules.
- Cannot create/edit catalog, recipes, promotion rules, package definitions, outlet setup, or user permissions unless separately granted a narrow capability.
- Cannot see owner dashboard or reports unless explicitly granted a read permission.
- Cannot approve their own restricted action.

### Waiter
- Create and update permitted open orders, select tables/guests, add order notes, and see the order/table state needed for service.
- Cannot collect payment, change prices/promotions, edit recipes/catalog, access sales reports, or manage staff unless explicitly granted a narrow capability.

### Permission model
Replace broad, overlapping permission checks with named capabilities. Initial suggested capabilities:
- pos.use
- orders.read, orders.create, orders.update_open
- payments.collect
- catalog.read, catalog.manage, catalog.import
- inventory.read, inventory.adjust, inventory.count
- recipes.read, recipes.manage
- discounts.read, discounts.manage
- promotions.read, promotions.manage
- packages.read, packages.manage
- restaurant.setup
- cashier.setup
- staff.read (limited operational roster only)
- staff.permissions.manage (Owner only)
- reports.sales.read, reports.operations.read
- dashboard.sales.read, dashboard.operations.read
- cash.reconcile
- approvals.read, approvals.decide
- outlets.read, outlets.manage
- settings.business.manage
- settings.notifications.manage
- billing.manage
- audit.read

Use deny-by-default checks and role presets. Owner-only capabilities must not be granted to Admin through custom permissions. Keep sales visibility and approval authority as separate capabilities. Add database regression tests for role escalation, tenant isolation, outlet isolation, and direct RPC attempts.

## Discount, special promo, and package UX

Use three separate Back Office sections with plain-language descriptions, previews, validation, and a summary of when the rule will apply.

### 1. Diskon
Purpose: a cashier-applied price reduction for an eligible checkout.
- Types: percentage or fixed amount.
- Scope: whole order, selected products, or categories where supported.
- Conditions: active date/time, minimum spend, maximum discount, active/inactive status.
- Show a live example before saving, e.g. “Belanja Rp100.000, diskon 10%, maksimal Rp15.000 → bayar Rp90.000.”
- Server revalidates eligibility and limits at checkout; the client is never authoritative.
- No stacking by default. Show a clear conflict message if another discount is already applied.
- Audit create/edit/deactivate and checkout use.

### 2. Promo Spesial
Purpose: a scheduled or rule-driven promotion that applies automatically when conditions match.
- MVP rules: happy hour/day schedule, selected product/category, and minimum spend.
- Make the trigger obvious: “Aktif Jumat, 16.00–18.00 untuk kategori Minuman.”
- Display active dates, eligible items, discount type, maximum discount, and priority in one review screen.
- Only one automatic promo applies by default. If multiple rules match, use an explicit priority and show the selected rule to the cashier.
- Do not add buy-X-get-Y, loyalty, voucher quotas, or campaign stacking until their stock, refund, and reporting behaviour is specified and tested.

### 3. Package / Bundle
Purpose: sell a predefined combination of products at a package price.
- Owner/Admin defines package name, included products, quantities, availability, and package price.
- The POS shows the package as one easy-to-select menu tile with a clear included-items breakdown.
- Package components must be reserved/decremented atomically. Never maintain a separate fictitious stock count for a bundle when the stock belongs to components.
- If a component is unavailable, block the package or apply an explicitly configured substitution; do not silently oversell.
- Growth/Premium recipes may decrement underlying ingredients for each component. Prevent double-decrement when a product has both stock-tracked units and a recipe.
- For reporting, preserve the package sale and allocate revenue to components using a documented, deterministic rule so totals reconcile to the receipt.
- Package cancellation/release follows the same stock reversal and audit rules as regular orders.

### Shared UX requirements
- Setup wizard: name → rule/type → eligible items → schedule/conditions → preview → save.
- Use plain labels, inline examples, sensible defaults, and validation before saving.
- Status labels: Draft, Scheduled, Active, Paused, Expired.
- Soft-deactivate records instead of deleting records referenced by historical transactions.
- At checkout, show the applied rule, discount amount, and final total clearly.
- Persist a snapshot of applied rule and amounts on the order; later edits must not rewrite old receipts.
- Tax/service interaction and rounding must be explicit and tested.

## Outlets and subscription entitlements

- All tiers support adding outlets as a product capability, subject to plan limits.
- Recommended commercial starting point: one included outlet per subscription; additional outlets use a transparent, separately priced add-on. Final included limits and add-on price must be set only after cost/support validation.
- Keep outlet limits and capabilities in a central entitlement model, not hard-coded in screens.
- Every operational record must carry an outlet identifier where relevant: products/catalog availability, orders, payments, stock movements, recipes, tables, staff assignments, discounts, promotions, packages, shifts, expenses, and audit events.
- Workspace/business identity remains the tenant boundary; outlet is a scoped boundary within that tenant.
- Every server/database operation must validate both business membership and outlet access.
- Owner can view authorized cross-outlet summaries. Admin can manage only assigned outlets and cannot see sales dashboards/reports.
- Do not duplicate catalog data by default. Support shared catalog with per-outlet availability/price/stock policy; document any exceptions.
- Outlet creation/deactivation must preserve historical orders and audit history.

## Recipe-based stock deduction

- Recipe and ingredient inventory are Growth/Premium entitlements.
- Support units and conversion factors (e.g. kg/g, litre/ml, each); reject incompatible units.
- When a paid/committed sale becomes stock-final under the chosen order lifecycle, deduct recipe ingredients exactly once in the same database transaction as the stock ledger event.
- Reserve/consume/release semantics must be documented consistently for open orders, payment, cancellation, and failed sync. Never deduct ingredients both when reserving a menu item and again on payment.
- Store recipe version/snapshot used by each order line so later recipe edits do not alter historical consumption.
- Record ingredient movements with reason, outlet, actor, order, recipe version, and timestamp.
- Handle insufficient ingredient stock explicitly; define whether the order is blocked or a permitted negative-stock exception is owner-configured.
- Add tests for duplicate retries, concurrent orders, partial failures, cancellations, recipe edits, bundle-with-recipe composition, and outlet isolation.

## Sales report email

- Email report capability is available on all tiers.
- Owner controls ON/OFF, schedule, recipients, and which outlets are included.
- A disabled setting must suppress queued and future report deliveries according to a documented policy.
- Admin does not automatically receive sales emails and cannot change recipients or report visibility.
- Use deduplication keys per business/outlet/report period; record delivery status without storing sensitive credentials in application logs.
- Keep transactional messages (e.g. account/security notices) separate from optional sales-report email.

## Implementation sequence

1. Authorization foundation: define capability registry, Owner/Admin/Cashier/Waiter presets, database enforcement, outlet scope, and regression tests.
2. Catalog & promo UX: normalize discounts, special promos, and packages; preserve current timed-discount behaviour through a backward-compatible migration.
3. Outlet model: add outlet entities and scoped records/policies; migrate existing business data into a default outlet without losing history.
4. Recipe engine: unit conversions, recipe snapshots, ingredient ledger, atomic stock mutations, idempotency, and rollback tests.
5. Email reports: owner controls, scheduling/deduplication, recipient authorization, delivery observability.
6. Acceptance testing: real browser/mobile flows, concurrent checkout, outlet boundary tests, role escalation tests, report reconciliation, backup/restore, and physical printer validation.

## Release gates

- Admin cannot query sales dashboards/reports or execute approval functions through UI, direct database reads, or RPCs.
- Owner-only permissions cannot be assigned to custom roles.
- Discount and promotion totals reconcile exactly with receipts and reports.
- Package and recipe stock movements are atomic, idempotent, and auditable.
- Data and actions are isolated by business and outlet.
- Historical receipts remain unchanged after catalog, promotion, package, or recipe edits.
- Email OFF prevents optional sales report delivery.
- All advertised capabilities are marked as implemented only after tests and acceptance checks pass.
