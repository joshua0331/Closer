# Closer album fix: deployment handoff

The mobile app has album creation/addition and deletion code, but the hosted
backend must also save `album` and `memoryDate`, accept `delete_memories`, and
report `memory_capabilities`. An older backend ignores album fields and rejects
deletion. Updating/restarting the phone app cannot update Cloud Run.

The backend owner should use this updated checkout and run from the project root
in PowerShell, while signed into Google Cloud CLI:

```powershell
./server/update-backend.ps1 -ProjectId iseeapp-ddf3a
```

Confirm the project belongs to your Closer deployment first. This project ID and
the `asia-southeast1` region come from the repository's deployment documentation.
The script builds the current backend and updates only the existing
`closer-demo-backend` service image, preserving its settings and secrets. It
requires Cloud Build/Artifact Registry/Cloud Run deployment permissions. No
passwords or secret keys need to be sent to the app developer.

This deploys the current backend files in this checkout, including other existing
backend changes. Review those files before releasing. In Cloud Run, verify that
traffic reaches the new revision; an existing pinned traffic configuration may
still send requests to an older revision.

After deployment, use a temporary album to verify:

1. Add a photo, open that album, and add another with a different caption.
2. Confirm the album contains two photos, including after reopening the app.
3. Confirm the partner sees the same album.
4. Cancel deletion and confirm both photos remain.
5. Confirm deletion and verify the album disappears on both devices.

Previously saved photos whose album information was discarded cannot be reliably
regrouped automatically. Do not delete real photos while verifying deployment.

## Copy-paste command for the backend owner

```powershell
Set-Location C:\Users\ASUS\Documents\GitHub\Closer
powershell -NoProfile -ExecutionPolicy Bypass -File server\update-backend.ps1 -ProjectId iseeapp-ddf3a -Region asia-southeast1
```

The existing database and runtime permissions are reused. Firebase Messaging
permissions are for push notifications, not Memories. This update does not
create a new database or change the Meta secret version.

Cloud Run command reference: https://docs.cloud.google.com/sdk/gcloud/reference/run/services/update

## Files integrated in this update

- lib/screens/couple_home.dart: Memories calendar, timeline, albums, camera/gallery creation, search, photo viewer, adding photos and confirmed deletion.
- lib/models/couple_store.dart: local album metadata, identifiers and deletion persistence.
- lib/models/cloud_couple_store.dart: shared album metadata, backend compatibility checks, deletion and tag error messages.
- server/couple_data.py: album/date persistence, authenticated deletion, capability reporting and search tags.
- server/hosted_app.py: authenticated memory-tag route.
- README.md and docs/connected-app.md: restored Memories feature documentation.
- server/test_memory_deletion.py and test/memory_deletion_test.dart: regression checks.
- server/update-backend.ps1 and this document: deployment handoff.

The app must also be rebuilt from this checkout to show the restored Memories UI.
No cloud deployment was performed during this integration.

## Verification on November 4, 2026

- Memories Flutter persistence test passed; all five Memories backend tests passed.
- Deployment PowerShell syntax passed.
- Full backend suite: all 48 tests pass after supplying the required therapy language in the shared test fixture. Production court protocol was not changed.
- Notification calls now use the installed package API. App test harnesses and guest-chat mocks match the current interfaces. Memories and guest-chat regression tests pass.
- Additional repair files: lib/services/notification_service.dart, lib/screens/courtroom_preview.dart, test/closer_app_test.dart, test/guest_room_test.dart, server/test_court_protocol.py.
- Live two-device sync and cloud deployment still require the backend owner.
