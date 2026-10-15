# SUMS POS: device outbox and cash operations

## Delivered

- IndexedDB catalogue snapshots and immutable order/cash commands, partitioned by authenticated user and outlet. No passwords, PINs, access tokens or refresh tokens are stored in IndexedDB. Cached catalogue omits purchase costs and staff directories. Only open remote bills are retained for seating context.
- Cached public application shell through the service worker. Its build cache version is now content-derived, so future application changes invalidate the shell correctly.
- New local orders and local cash payments survive reload in the same signed-in browser tab. The authorization snapshot expires after 12 hours. First login, refreshing a lost login, and switching to an uncached outlet require connectivity.
- Device queue banner, manual retry, review status, local receipt markings and downloadable JSON recovery records. There is no automatic delete/rewrite of a rejected cash transaction.
- Synchronization uses the same immutable command ID and payload across retries. Database advisory/row locks, permission checks and private command receipts prevent duplicate orders, stock reservations and cash payments after a lost response. Cash commands depend on their original order's acknowledgement.
- Database validates current product prices, stock, charges and table/reservation state. Conflicts remain on the device for review; local physical cash receipt does not imply that server reconciliation succeeded. Reconnect retries pending records; explicit manual retry rechecks records marked for review.
- Shift opening and closing per cashier/outlet, actual vs expected cash, mandatory variance note, immutable cash entries and separate business expenses funded by cash or bank. Owner sees up to 30 recent shifts / 50 recent entries; cashier sees their own. Cash payments and completed cash refunds attach to the active shift; cash tender/change and noncash payments are not counted as drawer revenue.
- Basic Owner Brief: actual low-stock count (fixed threshold 15), open bills, pending refund approvals. No forecasting or AI claims.

## Where to use

- POS Settings → Kas & pengeluaran: open shift, record cash movements/expenses, count and close shift.
- Back Office Overview → Owner Brief → Kas, shift & pengeluaran: review recent operational records and open the owner's own shift.
- Persistent top banner → Sinkronisasi: pending/review records, retry, recovery download.

## Offline scope and limitations

Only new device-local orders and cash settlement of those orders are supported. Historical/server bills require connectivity to pay. QRIS/cards/transfers, discounts, refund/void authorization, configuration changes and shift operations require connectivity. QRIS and card payment gateways are not provided by this change.

Open the outlet online once, wait for its catalogue to load and for the service worker to activate, then remain signed in. Close/reopen old POS tabs after deploying an update so an older shell is not retained. Do not clear browser data/private browsing storage while records remain unconfirmed. Browser/OS storage eviction or a lost device can remove unsynced data; persistent-storage permission is requested opportunistically, not guaranteed.

Permissions can only be revalidated at the server when reconnected. The offline lease uses last verified membership for up to 12 hours. No cross-device stock/table coordination exists while disconnected; conflicts require reconciliation. Web Locks and IndexedDB must be available; unsupported/blocked storage fails visibly rather than acknowledging an unsaved transaction. Logged-out users cannot restore a snapshot until signing in online again.

All devices must finish syncing before shift close. The local close control checks this user's current-outlet device queue, but cannot inspect another disconnected device. A payment synced without an open shift is left unassigned. Device-created time is retained in pos_orders.client_created_at and command receipts; canonical server created_at/paid_at and existing daily reporting use server receipt/sync time. Cross-midnight offline sales therefore need review; this release does not backdate authoritative reports.

Expenses are an operational ledger. They are not yet a complete general ledger, historical expense report/export, or net-profit calculation. Stock recipes, configurable minimums, supplier purchasing and loyalty remain separate follow-up modules.

## Database deployment

Additive schema scripts database/offline-infrastructure.sql and database/cash-operations.sql were applied once to dedicated POS project rhebbdxgdzyvnwkvnqsh. Do not reapply. No SUMS Studio database or repository was modified. Existing payment/stock authorization remains in force. Private command receipts use RLS with no client policy or table grants; only permission-checked private functions access them. Public entry points are security invoker wrappers with anonymous execution revoked.

Security advisors: no new warning-level finding. The private command ledger intentionally reports INFO for RLS without a client policy. Existing pg_net/public-schema and leaked-password-protection warnings remain unchanged; see Supabase database linter 0014 and Auth password security guidance. No auth plan or paid setting was changed.

## Validation

- npm run check; npm test (52 passing); npm run build; git diff --check.
- tests/offline.sql executed against POS with rollback: duplicate replay, changed payload/actor, changed prices/totals, rejected oversell rollback, exact cash change, duplicate cash, outsider/waiter/revoked access.
- tests/cash-operations.sql executed with rollback: one open shift, idempotent opening/entry/closing, split-cash reconciliation excluding change/QR, cash vs bank expenses, incoming/outgoing float, completed cash refund, variance reason and role/row isolation.
- Tests/offline.test.mjs simulates response loss, dependency blocking, stock projection, tenant isolation, lease expiration and pending-payment visibility.
- Direct mobile/browser storage lifecycle, airplane-mode UI, multi-tab browser behavior and physical printers have not been tested in this environment. Current checks do not certify production readiness.
