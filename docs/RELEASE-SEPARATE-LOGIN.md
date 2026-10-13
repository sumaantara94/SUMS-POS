# Separate owner and staff login

Back Office entry: /?app=office (also default /). Owner email + password, owner signup and demo. Staff entry: /?app=pos, username + password, password visibility control and a quiet owner-login link. Signup and promotional hero are removed from staff login.

The staff login uses an app-like 100dvh shell, safe-area padding, touch-sized controls and 16px inputs, with an internal scroll area for short screens and the keyboard. Android resize-content viewport is requested; tablet form width is capped at 400px. PWA installation still starts at the staff entry. Existing authenticated memberships determine authorization and navigation; cashier/waiter URLs normalize to POS on session restore and refresh. Owner capability to operate POS with an authorized existing session remains available.

Validation: portal markup/credential tests, full Node suite, syntax checks and static build. Direct Android/tablet rendering and keyboard behavior are unverified because the required browser capability is unavailable.
