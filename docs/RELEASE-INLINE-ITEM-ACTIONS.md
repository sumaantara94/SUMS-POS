# Inline item actions and left workspace identity

Workspace logo/name appears once in the left POS navigation, with subtle graphics and active navigation colours derived from the workspace accent. Mobile uses one compact identity row above navigation. The repeated upper workspace header and outside-card Delete / Void strip are removed.

Loaded bills have a trash button after each eligible item price. Open-item void requires the existing cancellation PIN and a mandatory reason; only cashier/owner with orders/payment permission can use it. Full line quantity is voided, stock restored once, and subtotal/tax/service recalculated. Voided lines remain marked with reason/actor for audit. The last active line cancels the bill and releases the table. Whole-bill cancellation skips already-voided lines to prevent duplicate stock restoration.

Complete-item trash opens the owner approval refund form with that item preselected; other available items can be added. Paid invoices are not directly altered. Voided unpaid lines are excluded from later discount allocation, receipts, sales calculations and refund requests. Open-item voids have a separate item audit table/CSV in Reports → Cancel / Void.

Kitchen jobs waiting for print exclude voided items. Already-printed jobs receive a separate queued VOID correction slip, showing cancelled product and reason without prices. Physical printing still needs the existing system dialog and operator action; it cannot retract a previously printed ticket.

Validation: 32 Node tests including paid/open item action templates and history, rolled-back database tests for PIN/role/tenant guards, partial and final-line void, exactly-once stock, fees/discounts, cancel skip, paid-refund boundaries and pending/printed kitchen routing; existing refund approval integration is rerun. Syntax/static build pass. Direct browser/mobile and physical printer rendering remain unverified.
