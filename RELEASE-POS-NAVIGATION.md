# POS navigation and language

Cashiers open Orders in Restaurant mode and Products otherwise. Waiters open Tables and choose a table before the guest/product flow. Restaurant/Waiter mode remains configured in Back Office. Disabled waiter mode has no seating/order-entry screens and the staff creation form offers only Cashier; existing waiter accounts see the disabled-mode message.

The POS header displays a fixed workspace logo/name. Workspace selection, connection banners, repeated module subtitles and the Supabase badge are removed from operational screens. Printer preferences, fullscreen, installation, refresh, logout and the owner's Back Office link are grouped in Settings. Connection information is available there.

English is the default interface language. English/Indonesia can be selected in POS Settings and owner Business settings; the choice persists on the device. Screen labels, dynamic payment forms, operational dialogs and receipts use the selection. Business records (product names, guests, notes, categories, staff and table names) retain their original text. The static shell includes the language and navigation modules in its versioned cache.

Validation: JavaScript syntax checks, 27 Node tests (including mode/role home routing and localization/user-content protection), and static build pass. Mobile browser rendering and device printer acceptance have not been verified in this environment. Sites sharing and Supabase billing/schema are unchanged.
