# Restaurant operations

Back Office → Pengaturan bisnis → Restaurant & waiter enables Restaurant and waiter independently, manages a six-digit cancellation PIN, table areas/layers and table positions/capacity/availability, and checkout discounts. Areas can be named Rooftop, Front, Back or anything else. Tables occupy a slot in a 12 × 12 map per area; slots cannot overlap. No area-count cap. Deactivate an area/table to stop new seating; existing orders remain payable.

Waiter enters table → guest name → menu. Restaurant dine-in cashier orders also require a table and guest. Cashiers can create takeaway orders. One open order per table is enforced by both table row locks and a partial unique database index. Payment/cancellation releases occupancy. Appending additional rounds, table transfers and merged bills are future work; current orders have one product line per product and one shared note per product quantity.

Each item can carry a preparation note. Submission atomically reserves stock, saves the order visible to cashier, and queues category-matched Kitchen/Bar jobs. Retry requests do not duplicate orders or jobs. Server-created print jobs snapshot section config and item instructions. Paid jobs remain pending until acknowledged; cancellation removes queued jobs. Printed cancellations need operator communication to the section; no automatic cancellation slip is sent yet.

Printing on Android + Bluetooth is **not yet a direct physical integration**. The web app offers system print dialogs and an explicit operator acknowledgement. It does not infer successful output from closing a dialog. Automatic raw Bluetooth dispatch needs an Android print bridge/native integration and supported hardware; printer model is still needed. No paid printer service or Supabase upgrade was enabled. Sites remains owner-private; external staff access to the hosting layer has not been validated.

Cashier loads the order from Pesanan, chooses an active percentage or fixed discount, and records cash payment. Rules include start/end instants, minimum spend, maximum discount, and active status. Server checks current validity at checkout. No stacked discounts, voucher redemption or usage quotas yet. A cumulative proportional integer allocation makes item/category net sales sum exactly to the receipt total; HPP snapshots are unchanged.

Cancellation requires pay/orders permissions, a six-digit PIN and a 3–300 character reason, including for owner. PIN is bcrypt-hashed in a private table with no client read access. Five attempts per cashier/business per fixed 15-minute bucket; incorrect attempts return a committed denial so counters survive. Cancelled order records actor, reason and time. Paid orders cannot be cancelled. No PIN is written into audit events.

Migration 008 adds the new schema and retires legacy order/payment/cancel RPC grants. 009 fixes PL/pgSQL section naming ambiguity; 010 adds unique occupancy/map constraints and money bounds. Old tabs need reload after this release. Current endpoints: pos_place_order_v3, pos_pay_order_v2, pos_cancel_order_v2. All writes check workspace membership; new tables have read RLS and no direct client mutation grants.

Validation: npm check, 13 Node tests, build, transactional Supabase tests for restaurant rules, PIN/expiry, stock, tenant isolation, and current RPC regression tests. Fixtures are rolled back. Browser/device acceptance and Bluetooth hardware output are not yet verified. Cashier refresh remains polling at 15 seconds, with manual refresh available.

## Simplified seating setup

The default view is a responsive table list. “Jumlah & kapasitas meja” creates numbered tables from a quantity and lets the owner edit each capacity or apply it to an inclusive range. For example: 10 tables, 1–2 seats 2 guests, 3–5 seats 4 guests. Existing IDs and layouts are preserved. Decreasing quantity deactivates extra tables without deleting order history and rejects removal of tables with open orders. Inactive tables can be reactivated; up to 144 retained table records per area.

“Atur posisi · drag & drop” opens the area layout. Pointer events support mouse and touch; dropping into an occupied slot swaps the two positions. Position writes are owner-only, atomic and tenant-scoped. Waiter can view the layout but cannot rearrange it. Browser and Android gesture acceptance remain unverified; Node tests and rolled-back database tests cover quantity/range generation, persisted move/swap, save retry idempotency and occupied-table protection.
