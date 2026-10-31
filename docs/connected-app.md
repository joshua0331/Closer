# Connected Closer — October 31, 2026

The production entry point now initializes Firebase and requires real sign-in and pairing. The illustrated map/local store are retained only for legacy tests and local prototype compatibility; they are not the normal connected app path.

## Infrastructure

- Project: `iseeapp-ddf3a`.
- Runtime: `closer-demo-backend`, Cloud Run, Singapore.
- Database: `closer-demo-backend`, private named Firestore database.
- Shared app collections: `closer_profiles`, `closer_couples` (messages, memories, photos and hearings below each couple), `closer_pair_invites`, `closer_app_limits`.
- Existing private demo quota collection: `closer_demo_security`.
- Media bucket: `iseeapp-ddf3a-closer-media`, uniform bucket access with public access prevented; runtime has object-user access.
- No changes to iSee's default Firestore rules, existing app registrations or media bucket.

App authentication uses Firebase email/password, already enabled in the project. Shared API requests use Firebase ID tokens. The backend verifies those tokens and checks the signed-in account's couple membership on each operation. Mobile clients have no direct access to the private Firestore database. AI requests also require an active private demo session and quota reservation. Shared-space limits are 90 requests/minute/account and 20 photo uploads/day/account. Each photo is capped at 4 MB; court evidence/portraits are capped at 1 MB.

## Using the app

Create separate accounts, enter names and pair using a private invitation. Send text/photos and add memories from either phone. Share location only after the map's explicit permission/consent prompt. Reopen a summons from both phones to join the same hearing. Roles and deadlines are enforced on the server. Use Closer → AI demo access to connect the private AI code before a judge/artwork/highlights request.

The public backend URL is the default. `BACKEND_URL` remains overridable for self-hosting. Firebase options were generated from the existing Closer Android/iOS app configurations. They contain public app identification, not the private Meta key.

## Honest limits

- Shared state polls every 8 seconds while active; court polls every 5. The current history view is capped at 150 entries per collection.
- No push notifications/read receipts are fabricated. Push delivery remains unimplemented.
- Location is foreground/map-only. Last-known markers show age and can be removed. Background tracking is not implemented.
- Pairing is persistent. Unpairing, account/data deletion/export and retention policies need implementation before a public production release.
- Live Spark and Wonder requests were verified with fictional material. Muse Image/SAM remain integrated but need live image-quality testing.
- Cloud API tests used separate synthetic accounts, shared photos/memories, location removal, role enforcement and isolation. They do not replace testing two real phones and iOS signing.
- This Windows PC's shared Gradle cache is corrupt/locked. `tool/run-android.ps1` uses `.gradle-closer` instead; the directory and build logs are excluded from Git. Gradle memory was lowered to 2 GB with two workers for this 8 GB PC.

## Verification

The opt-in operator smoke test `server/smoke_shared.py` creates and deletes synthetic test accounts/data. It consumes Firebase/Cloud Storage usage, but does not call Meta. Model tests otherwise use mocks. Run native gallery/GPS and shared-court checks on physical devices before publishing a demo as fully device-verified.

The full shared hearing was also exercised through the deployed API with two synthetic accounts and real Spark questions/verdict, Wonder appeal and both participant approvals. `server/smoke_shared.py --ai` repeats this optional three-model-request check and consumes Meta credits; its default mode makes no Meta calls. Test data/accounts and temporary AI access were removed/revoked after verification.

The Android debug APK built successfully on October 31, 2026 after isolating the corrupted shared Gradle cache and reducing build memory. Device gallery/GPS checks still require an attached Android device/emulator.
