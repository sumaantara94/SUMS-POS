# v0.2 verification and remaining work

Dedicated SUMS-POS Supabase project; organization plan verified Free. Eight RLS-protected tables. Public invoker endpoints delegate to private functions with fixed search paths and membership checks. No anonymous mutation grants or server secret in the browser. Owners assign roles to registered users; invitations are not sent.

Passed server SQL tests with generated users and rolled back fixtures: cross-business reads/writes denied, waiter payment and membership updates denied, direct stock update denied, overselling and underpayment rejected, duplicate orders/payments and stock release handled. Six demo unit tests and syntax/build checks passed. Security advisors returned no findings. Missing foreign-key indexes were added.

Browser end-to-end checks are unavailable here and remain required. Signup email confirmation, two-device concurrency, password reset, calendar/timezone reporting, and physical printer behavior are not verified. Frontend polls every 15 seconds; event-based realtime is not implemented. History and reports currently use the latest 1,000 orders.

Hosting starts owner-private for development. Configure Supabase Authentication Site URL and allowed redirects to the deployed origin before signup callbacks. After email confirmation return to the site and sign in. Custom SMTP for unrestricted customer delivery is not configured; keep email confirmation enabled.

Remaining: outlets, service products, tax/discount rules, refunds, shifts, offline sync, backup/restore, scalable server reports, and Bluetooth bridge. This is a development release, not production acceptance.
