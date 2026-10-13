# Separate owner and staff login

Back Office entry: /?app=office (also default /). Owner email + password, owner signup and demo. Staff entry: /?app=pos, username + password, password visibility control without cross-portal links or role labels. Signup and promotional hero are removed from staff login. Field labels use separate block rows with full-width inputs; the password control stays centred inside its field.

The staff login uses an app-like 100dvh shell, safe-area padding, touch-sized controls and 16px inputs, with an internal scroll area for short screens and the keyboard. Android resize-content viewport is requested; tablet form width is capped at 400px. PWA installation still starts at the staff entry. Existing authenticated memberships determine authorization and navigation; cashier/waiter URLs normalize to POS on session restore and refresh. Owner capability to operate POS with an authorized existing session remains available.

Validation: portal markup/credential tests, full Node suite, syntax checks and static build. Direct Android/tablet rendering and keyboard behavior are unverified because the required browser capability is unavailable.

Keyboard follow-up: remove decorative card icon and helper copy; align the form near the top. Follow VisualViewport height/offsetTop on resize/scroll, with delayed focus settling for keyboard animations. Compact header/card and hide footer during input focus. Keep a 64px clearance below the focused field using the internal scroll container. Listeners and timers are removed when leaving login. Actual Safari/Android hardware behavior remains unverified.
