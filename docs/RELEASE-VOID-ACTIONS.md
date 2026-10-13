# Direct void actions and single POS identity

Open POS bills show a separate Delete / Void button in the list and loaded bill. It opens a confirmation form with the bill reference, the existing six-digit cancellation PIN and a required note. Presets cover customer cancellation and unavailable ingredients; notes remain editable. Only open bills and authorized cashiers/owners receive the action.

Reports now has prominent Sales / Cancel / Void selectors. Cancellation reporting retains cancellation time, creator, cancellation actor, reason and original bill value, with daily/7-day/30-day periods and CSV export. Voided bills are retained for audit and excluded from collected revenue; stock is restored and the table freed by the existing server RPC. This is whole-bill cancellation, not paid-bill refund or individual line voiding.

POS sidebar branding is removed; workspace logo/name appears once in the header across desktop, tablet and mobile. Back Office keeps its existing identity/workspace selector.

Validation: syntax checks, 29 existing Node regression tests and static build pass. The server PIN, mandatory reason, stock restoration, role and tenant checks are unchanged from previously verified database tests. Browser/mobile rendering remains unverified in this environment.
