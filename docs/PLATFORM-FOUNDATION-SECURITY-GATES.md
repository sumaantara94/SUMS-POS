# SUMS POS Platform Foundation and Security Gates

Status: engineering plan based on repository audit, 21 October 2026.
This document is a delivery contract, not a claim that every gate is already implemented or passed.

## Current verified starting point

- The repository has a PWA manifest, service worker, browser install flow, device-local outbox, offline snapshot lease, a realtime invalidation client, and a LAN Hub.
- The PWA release notes say offline shell can open but transactions need connectivity unless using the separate LAN/offline flow. Device, browser, printer, and multi-device acceptance is incomplete.
- Architecture documentation describes a browser preview using localStorage and says production requires a dedicated API/database and tenant-scoped server authorization. README and release notes describe later online features; these must be verified against the deployed environment before customer-facing claims.
- Native APK and signed desktop installers are not verified as existing release artifacts. Do not expose download buttons for missing artifacts.
- No tax line should be added to the subscription checkout at this stage, per product direction.

## Target architecture

1. **One authoritative data plane:** authenticated API/database is the source of truth for online business records. Browser storage is a cache/outbox, never a trust boundary.
2. **Tenant isolation:** derive business/outlet membership from the authenticated server session. Never trust business_id, outlet_id, role, price, discount, stock, or entitlement supplied by the browser.
3. **Atomic business operations:** server-side transactions, validated state transitions and idempotency keys for orders, settlement, refunds, inventory movements and sync replay.
4. **Realtime as invalidation, not replication:** broadcast minimal tenant-scoped signals; clients refetch authorized records. Realtime must never expose order/payment/customer payloads to unauthorized subscribers.
5. **Offline with explicit guarantees:** bounded lease, encrypted/limited local sensitive data where practical, durable outbox, stable operation IDs, replay deduplication, conflict rules and visible sync state. Never silently claim synced when pending operations remain.
6. **Distribution:** PWA first; signed Android APK and desktop installers only after reproducible builds, signing-key custody, checksums, release notes, rollback/update policy and device acceptance tests.
7. **Owner Download Center:** show only supported builds, platform/version, release date, SHA-256 checksum, installation instructions and minimum OS/browser. Links must point to actual published artifacts and enforce authenticated owner/staff policy as appropriate.

## Security gates before production sales

- [ ] Authentication and account recovery verified on deployed URLs; no demo role selector treated as real authorization.
- [ ] Database row-level security and private RPCs reviewed for every tenant-owned table/function.
- [ ] Automated cross-business and cross-outlet read/write denial tests.
- [ ] Server-derived roles and plan entitlements; reject client-side role/plan tampering.
- [ ] Server-side price, discount, stock and order-state validation.
- [ ] Idempotent order submission, payment recording, refund and outbox replay tests.
- [ ] Realtime isolation test: a second workspace receives no signal or data from the first.
- [ ] No secrets/service-role keys in frontend, logs, repository, source maps or release bundles.
- [ ] Strict input validation, output encoding, CSP/security headers, safe CORS policy, rate limits and audit logging.
- [ ] Dependency and secret scanning in CI; least-privilege GitHub/Supabase credentials.
- [ ] Backup restore drill, retention policy and incident recovery procedure.
- [ ] Mobile and desktop installation/update/rollback tests on real devices.
- [ ] Concurrent stock, disconnect/reconnect, duplicate retry and clock/time-zone tests.
- [ ] Printer and LAN Hub acceptance on the supported hardware matrix.
- [ ] Trial expiration, subscription entitlement and payment webhook tests before billing is enabled.

## Delivery sequence

### Phase A: inventory and evidence
1. Build a source-backed feature matrix for Starter, Grow, Scale and Enterprise.
2. Run unit/static/build tests and inspect CI failures; do not merge unrelated PRs merely to clear the queue.
3. Record the deployed database/auth setup and map every API/RPC to tenant and role checks.
4. Add test coverage for existing auth, RLS, sync and offline boundaries before new distribution code.

### Phase B: harden the data plane
1. Resolve tenant authorization and business-operation invariants.
2. Add cross-tenant, replay/idempotency, concurrency and realtime isolation tests.
3. Verify online/offline state transitions and make pending sync visible.
4. Validate backup/restore and monitoring.

### Phase C: device experience and distribution
1. Verify PWA on Android phones, tablets and desktop browsers.
2. Add a responsive Owner Download Center that only lists available, verified releases.
3. Establish reproducible APK/desktop build pipelines and signing-key custody.
4. Publish signed artifacts and test installation, update, rollback and version compatibility.

### Phase D: commercial controls
1. Implement 14-day trial lifecycle and server-enforced entitlements.
2. Implement checkout prices and annual discount server-side, with no checkout tax line until explicitly approved.
3. Test plan transitions, trial expiry, failed payments, renewal and cancellation.

## Definition of done

A feature is not called production-ready because a page renders or CI is green. It must have server-side enforcement, automated regression coverage, deployment evidence, user-facing error/recovery states and acceptance on the intended devices. Mark each gate with a test run or deployment reference before release.
