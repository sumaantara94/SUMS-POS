# SUMS POS Feature Matrix: Evidence-Based Baseline

Status: preliminary source/documentation audit, 21 October 2026.
This is not a final sales feature promise. “Present in repository” means there is code or release documentation; it does not certify production deployment or complete device acceptance.

| Capability | Evidence-based current status | Package recommendation | Verification required before marketing |
|---|---|---|---|
| Core POS/order flow | Code and release docs present; production readiness not certified | Starter+ | End-to-end sale, cancellation, receipt, authorization |
| Product/catalog and variants | Code/migrations and release docs present | Starter+ | CRUD, permissions, historical order snapshots |
| Cash settlement and shift/cash operations | Code/docs present; no payment gateway authorization stated in README | Starter+ basic, Grow+ advanced controls | Cash ledger reconciliation, shift-close tests |
| Sales reports | Reports exist; README warns order history/reporting currently has 1,000-record and date-range limitations | Starter basic, Grow/Scale advanced | Full server-side calendar reports and timezone tests |
| Realtime cross-device refresh | Realtime invalidation client and migrations/docs exist | All paid tiers, subject to service limits | Two-device tests, workspace isolation, reconnect and missed-event recovery |
| Offline / local LAN Hub | Device outbox and Hub exist; acceptance limits remain | Optional add-on or Grow+ after validation | Replay dedupe, disconnect/reconnect, conflict, supported hardware tests |
| Android installable PWA | Manifest/service worker/browser install flow exists | All tiers | Real Android installation and upgrade tests |
| Tablet layout | Responsive/touch-oriented app shell exists; broad device acceptance not verified | All tiers | Supported screen-size and touch tests |
| Desktop PWA | Browser app is available in repository; native installer not verified | All tiers | Windows/macOS browser and print acceptance |
| Native Android APK | No verified release artifact in repository audit | Future distribution | Signed reproducible build, checksum, update and rollback |
| Native desktop installer | No verified release artifact in repository audit | Future distribution / Enterprise support | Signed packages for supported OS, update/rollback |
| Owner Download Center | Not verified in current Owner UI audit | All owner accounts | Authenticated artifact list, version/checksum, installation docs |
| Restaurant tables/waiter workflow | Restaurant/table modules and docs present | Grow+ recommendation | Full waiter/cashier end-to-end acceptance |
| Recipe ingredient auto-deduction | Must be verified against current inventory implementation | Grow/Scale candidate | Recipe consumption, void/refund reversals and concurrency |
| COGS/margin intelligence | Purchase cost and insights code may exist; completeness not certified | Scale candidate | Formula validation, data coverage, reports |
| Multi-outlet consolidated controls | Outlet grouping/code exists; full entitlements/reporting not certified | Scale; Enterprise custom | Tenant/outlet isolation and consolidated reporting |
| Customer CRM/loyalty | Roadmap describes as planned/later work | Future | Do not market as available until implemented |
| Subscription checkout and plan enforcement | Not confirmed active | All packages require later implementation | Server entitlements, payment state machine, webhook verification |
| 14-day trial lifecycle | Marketing copy exists; automatic lifecycle not confirmed active | Trial | Server start/end, reminders, expiry and data retention |
| Tax on SUMS POS subscription checkout | Explicitly deferred | None | Do not add tax line until separately approved and tax treatment confirmed |

## Package guardrails

- **Starter:** essential selling, catalog and basic sales visibility only after each item passes acceptance.
- **Grow:** operational controls such as stock, shifts, and business-type-specific workflows only where implemented and tested.
- **Scale:** advanced reporting, margin/stock intelligence and multi-outlet capabilities only after correctness and access controls are verified.
- **Enterprise:** custom rollout/support and verified organization-level controls. “Custom” pricing does not mean missing capabilities can be promised.
- **Offline Mode:** do not promise universal offline transactions or printer support. Publish a supported-device matrix and explicit limits first.

Feature assignment is a proposed commercial boundary, not an implemented plan-entitlement system. Entitlements must ultimately be enforced by the server, not hidden only in the UI.
