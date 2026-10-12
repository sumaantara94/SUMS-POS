# Owner-managed staff usernames

Owner creates staff with name, globally unique case-insensitive username, password (10–128 characters) and cashier/waiter role. Staff does not need a real email, signup or confirmation. Backend provisions a confirmed internal Auth identity with a non-delivery placeholder address; Auth stores password hashes. Plaintext passwords are not written to POS tables, source, logs or response payloads.

staff-access Edge Function supports unauthenticated password verification for login; provisioning separately requires a verified bearer user and active owner membership. Service role stays in Edge Function secrets. SQL staff finalization is service-role-only, validates owner membership and commits profile/membership/audit together. Failed finalization compensates only its new Auth identity. Usernames resolve through a service-only query and inactive staff are rejected with a generic login error. Attempt counters impose 10 attempts per username and 50 per forwarded-IP hash per fixed 15-minute bucket, in addition to Auth controls. Account deactivation must remain enforced through membership RLS; valid JWTs alone grant no tenant access.

Staff lands in Online POS and cannot bootstrap an owner workspace. Existing owner signup/email confirmation stays unchanged. Existing email-based memberships remain in place. This release adds staff creation/listing; password reset and full employee lifecycle UI remain future work.

Verification: 11 code tests passed, service-only SQL provisioning and staff workspace-denial tests passed with rolled-back fixtures, deployed endpoint rejected unauthenticated creation. Real owner-created staff signup/login needs browser acceptance; no real staff credentials were generated or requested in chat.
