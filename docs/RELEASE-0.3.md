# Categories, costs and printing

Implemented persistent category master with stable IDs, rename/archive, category filters in products/POS/reports, category-group sales/HPP/gross-profit reporting and CSV line-level export. Business type remains distinct from product categories. Existing products migrated to matching categories.

Product purchase_cost is nullable; missing means unknown, not zero. New order lines snapshot purchase cost and category. Historical orders remain untouched. Reports label HPP/gross profit incomplete when costs are missing. Net sales differs from gross profit (net sales minus HPP); operating costs are not part of gross profit. Discounts/refunds/taxes are not yet implemented.

Business settings can upload raster logos (PNG/JPEG/WebP, maximum 200 KB), select default 58/80 mm width and define preparation sections with category assignment and printer labels. Each POS user saves local device width/printer preferences. Cashier prints complete receipt with logo; waiter selects section to print category-matched items without prices. Browser print handles physical printer selection; direct Bluetooth connection, unattended routing and print completion/retry tracking are not implemented. OS paper settings must match the selected width. Existing orders lacking a category snapshot use current product category for routing only.

Additional workspace creation is gated in UI and server until upgrade entitlement/payment flow is implemented. Existing workspaces remain available.

Verified transactional database tests: category rename, immutable snapshots after price/category changes, print settings persistence, SVG rejection, tenant isolation and additional-workspace gate. Test fixtures rolled back. Syntax/build and existing demo transaction tests passed. Browser/printer hardware validation remains outstanding. Security advisory: leaked-password protection is disabled; no authentication settings changed in this release.
