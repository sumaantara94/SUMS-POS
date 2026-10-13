# Compact POS order list

POS Orders defaults to Open, with Open / Complete / Cancelled filters and counts. The list contains one tappable row per bill: table/order type, guest, bill number/time, total and item count. Clicking loads the bill in a detail dialog with line prices/notes, totals, actor trace, Print and role-permitted Pay / Cancel order actions. Completed/cancelled bills are read-only. Preparation queue text/actions move to POS Settings. Back Office report tables are preserved.

Cancel order retains the existing authenticated server RPC requiring a six-digit PIN and a nonempty reason (minimum three characters). Successful cancellation restores stock and table availability; the record remains in the cancellation report/filter. This change does not physically delete financial history or relax tenant/role restrictions.

Validation: syntax checks, existing 29 Node regressions and static build pass. Previous database integration tests cover PIN rejection, mandatory reason, stock restoration and cancellation reporting; backend contracts are unchanged in this release. Direct browser/mobile rendering verification is unavailable in this environment.
