# Closer hosted AI demo

Status: hosted API implementation and local tests are ready. No service has been deployed, no live Meta call has been made, and iSee data/rules have not been changed. The selected project is iseeapp-ddf3a. Google Cloud CLI and the Meta secret still need setup.

## What judges receive

- The public source and setup instructions contain only the backend URL.
- A judge receives a private app demo code through the submission's private instructions. It is not a Meta key and requires no external account.
- Closer > Us > AI demo access exchanges the code for an eight-hour session kept only in memory. It is cleared on app close/expiry/disconnect.
- The server calls only Meta models. It keeps the Meta key in its environment, supplied by Secret Manager in Cloud Run.

## Access and usage controls

The hosted entry point is server/hosted_app.py, not the older local judge_server.py HTTP server.

Every request requires a valid session, active invite, enabled/unexpired demo policy and a unique request ID. Atomic persistent reservations enforce per-invite and global lifetime limits, separate image limits, a global per-minute limit, at most two simultaneous provider calls and one in-flight call per session. Repeated IDs cannot make a second model call. Failed upstream calls count conservatively and are not automatically retried/refunded. Reconnecting/restarting/redeploying does not reset budgets.

Default initialization: 100 total calls, 5 image calls, 14 days. Default invite: 20 total calls, 1 image call, 6 sessions, 14 days (capped by global expiry). Tune these deliberately for the judging period; once exhausted, live AI stops and practice remains available. Counts are not a dollar spending cap and do not prevent hosting/database charges or all denial-of-service attacks.

Codes/tokens are stored only as hashes. Transcripts, photos and generated results are not stored in the security database or request logs. The server processes uploads in memory and sends them to Meta after app consent. store:false is not a guarantee about all provider retention policies.

## Cloud setup in the existing iSee project

Use separate named resources. Do not replace iSee app entries, its default database or its existing rules.

1. Ensure billing is enabled and install/sign into Google Cloud CLI. Install backend requirements in a Python environment (`pip install -r server/requirements-dev.txt`).
2. In project iseeapp-ddf3a, enable Cloud Run, Cloud Build, Artifact Registry, Secret Manager and Firestore APIs.
3. Create a NEW native Firestore database named us-demo-backend in your chosen region. This holds only private demo security/quota records. server/demo_storage.py explicitly selects this database; it does not default to iSee's database.
4. Deploy server/firestore-demo.rules to that named database only:

```powershell
firebase deploy --only firestore:rules --config server/firebase-backend.json --project iseeapp-ddf3a
```

The configuration names only us-demo-backend. Do not replace it with a generic deploy of iSee's rules. Mobile clients must have no read/write access to security records.

5. Create service account us-demo-runtime in the project. Grant roles/datastore.user ONLY with an IAM condition limiting its database access:

```text
resource.name == 'projects/iseeapp-ddf3a/databases/us-demo-backend'
```

6. Create Secret Manager secret us-meta-api-key. Enter your Meta key privately in Secret Manager, never in this repository or chat. Grant the runtime service account Secret Accessor on THIS secret only. Pin the deployed secret version.
7. Create an Artifact Registry Docker repository named us-demo in the same region. Ensure the Cloud Build identity can push to it. Configure application-default credentials for the following operator-only admin steps.
8. Initialize the persistent policy ONCE and create private judging codes. These commands do not call Meta:

```powershell
$env:BUDGET_STORE = 'firestore'
$env:GOOGLE_CLOUD_PROJECT = 'iseeapp-ddf3a'
$env:FIRESTORE_DATABASE = 'us-demo-backend'
python server/demo_admin.py init --calls 100 --images 5 --hours 336
python server/demo_admin.py invite --label 'Judge 1' --calls 20 --images 1 --sessions 6 --hours 336
```

The invite command prints its private code once and an invite ID. Share the code privately; keep the ID for revocation. Re-running init refuses to reset existing counters.

9. After resources/permissions/secret/policy are ready, build and deploy using the explicit project ID. Review the selected region and secret version first:

```powershell
./server/deploy.ps1 -ProjectId iseeapp-ddf3a -Region asia-southeast1 -MetaSecretVersion 1
```

The script builds an allowlisted Docker context, uses the dedicated runtime identity, enables public HTTPS transport with application-level session authentication, limits Cloud Run to two instances, and mounts the Meta secret. It does not change iSee's app registrations or default database rules. Source/build/runtime billing still applies.

10. Copy Cloud Run's HTTPS URL. Build/run Closer with ONLY that public address:

```powershell
flutter run --dart-define=BACKEND_URL=https://YOUR_CLOUD_RUN_SERVICE_URL
```

No Meta key, private judge code or static shared token goes in this build command. Enter the private code inside the app at runtime. Do not use the old COURT_DEMO_TOKEN scheme for public hosting.

11. Verify health, invalid-code rejection, one private login, and a single real Meta text/image call before handing the demo to judges. Check persistent counts, then verify revocation and the disabled state. Container, Firestore/IAM rules, mobile-device and live-provider behavior have not been verified in the cloud yet.

## Operator controls

Run with the same project/database environment and operator credentials:

```powershell
python server/demo_admin.py status
python server/demo_admin.py revoke --id INVITE_ID_FROM_CREATION
python server/demo_admin.py disable
python server/demo_admin.py enable
```

Disable/revoke blocks subsequent requests across instances. Requests already running at Meta may finish. No administrative operation is exposed through the public HTTP API.

## Local verification without cloud or Meta calls

```powershell
python -m venv .venv-backend
.venv-backend/Scripts/python.exe -m pip install -r server/requirements-dev.txt
.venv-backend/Scripts/python.exe -m unittest discover -s server
flutter test --no-pub
```

Tests mock Meta calls and use temporary SQLite records for persistent/concurrent quota tests. Production Cloud Run refuses the SQLite mode and requires Firestore. These tests do not verify the actual cloud IAM/database deployment.

## Scope

This is the secured AI proxy for a publicly runnable judging demo. It does not implement partner pairing, shared chat, cross-phone case synchronization or production app accounts. Those Firebase features remain separate work.

References:
- https://firebase.google.com/docs/firestore/manage-databases
- https://docs.cloud.google.com/run/docs/configuring/services/secrets
- https://docs.cloud.google.com/sdk/gcloud/reference/run/deploy
