# SUMS POS

Dedicated web POS for multiple independent businesses.

## Application surfaces

- Back office: owner dashboard, products, inventory, reporting, business personalization and staff permissions.
- Online POS: cashier checkout, waiter orders, receipts and preparation tickets.

## Infrastructure

Use a dedicated database and hosting configuration separate from SUMS Studio. Backend authorization must validate tenant membership and outlet-scoped permissions. Payments and inventory changes require atomic server-side transactions and an audit trail. Owner dashboards consume persisted sales events.

## Delivery plan

1. Implement and validate interactive back office and POS flows.
2. Connect dedicated authentication and database; enforce tenant isolation and configurable roles.
3. Verify receipt and order printing on actual printer hardware. Bluetooth integration depends on operating system, browser and printer protocol; browser printing is the initial fallback.
4. Deploy and validate security, concurrent checkout, backups and recovery.

No real payment processing or production database is configured yet. CI deployment workflows will be enabled only after infrastructure is ready.
