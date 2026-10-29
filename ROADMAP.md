# Closer roadmap

Last updated: October 29, 2026. Checkboxes describe implementation status, not promises of completed live validation. The immediate goal is a reliable Meta-powered Couple Court demo; the wider couple app follows on the same foundation.

## 1. Foundation — implemented locally

- [x] Closer branding, peach theme and Android/iOS display names.
- [x] Map, Court, Memories, Chat and Us navigation.
- [x] Saved profile names and anniversary.
- [x] Local text/photo chat, replies, heart reactions and court summons.
- [x] Local photo memories and captions.
- [x] Illustrative map with explicit preview labels.
- [x] Per-summons court drafts and case outcomes linked back to chat.

**Boundary:** none of these shared-looking features currently synchronize between phones.

## 2. Meta-powered court — integration implemented; live validation pending

- [x] Muse Image scene-generation request from a courtroom reference and two consented portraits.
- [x] Saved personalized scene with model/response/prompt metadata.
- [x] Timed opening, cross-examination and rebuttal stages.
- [x] Photo exhibits with ownership, captions, IDs and upload limits.
- [x] Muse Spark multimodal requests containing actual evidence images.
- [x] Judge questions for both participants.
- [x] Structured evidence review and remedy proposal tied to the original request.
- [x] Muse Wonder appeal with prior ruling, grounds and the other participant's response.
- [x] Optional SAM 3.1 object-box highlights, original-photo toggle and separate upload consent.
- [ ] Verify live SAM results and overlay alignment on real photos.
- [x] Separate acceptance by both participants or an unresolved closure.
- [x] Validation and mocked tests for requests, exhibits and rulings.
- [ ] Configure private Meta credentials and verify model access.
- [ ] Verify a real Muse Image generation, including both identities and visual consistency.
- [ ] Verify real Spark questions, exhibit observations, verdict and appeal end to end.
- [ ] Evaluate ambiguous screenshots, conflicting accounts, prompt injection and inappropriate remedy requests.
- [ ] Check latency, request limits, provider errors and remaining credits on real devices.

**Ready when:** a consented or fictional case completes with actual Meta responses, useful exhibit limitations and no fabricated live-model labels.

## 3. Reviewable hosted demo — before handing it to judges

- [x] FastAPI backend and public-URL-only Flutter configuration.
- [x] Private invite-code login, hashed tokens and expiring sessions.
- [x] Persistent usage reservations, image budgets, deduplication and concurrency controls.
- [x] Operator revocation and global disable controls.
- [x] Container, deployment script and isolated Firestore configuration.
- [ ] Provision the dedicated database, runtime identity and secret without changing existing app data.
- [ ] Deploy Cloud Run and check HTTPS, IAM and database isolation.
- [ ] Verify budgets survive redeployment and work across service instances.
- [ ] Verify invalid/expired/revoked access, exhausted budgets and disabled-demo behavior.
- [ ] Give reviewers private codes and test the exact public setup instructions.

**Ready when:** a fresh installation reaches live AI using a private demo code, with no Meta key in source or app binaries, and revocation/quota controls work in the hosted environment.

## 4. Two-phone foundation — next core product milestone

- [ ] Register/configure Android and iOS Firebase apps.
- [ ] Add account sign-in, sign-out and recovery.
- [ ] Pair partners through a one-time invitation that creates lasting membership.
- [ ] Define consent, unpairing, account deletion and ownership behavior.
- [ ] Implement tested Firestore/Storage rules that restrict data to the correct couple.
- [ ] Move chat and memory metadata to shared cloud state; store photos with access controls.
- [ ] Add real delivery/read states only after acknowledgments exist.
- [ ] Synchronize summons, testimony, exhibits, questions, rulings and approvals.
- [ ] Make hearing roles, deadlines and transitions server-authoritative.
- [ ] Handle simultaneous actions, reconnects and interrupted uploads without duplicate actions.
- [ ] Add notification delivery for messages and court summons.

**Ready when:** two separate accounts on two phones pair once, exchange a photo/message, and finish the same hearing with consistent timers and outcomes. A user outside the couple cannot read or modify their records.

## 5. Broader Closer experience — after shared data is reliable

- [ ] Shared memories with deletion and upload-progress handling.
- [ ] Anniversary and profile changes synchronized between partners.
- [ ] Optional location sharing with clear permissions, pause/revoke controls and stale-location labels.
- [ ] Real distance calculated only from consented locations.
- [ ] Accessibility review: screen readers, text scaling, contrast and reduced motion.
- [ ] Improve loading, empty, offline and recovery states.
- [ ] Review retention, deletion/export, backups and abuse reporting.

**Ready when:** both participants can understand what is shared, stop sharing, and recover from common network failures without losing control of their data.

## 6. Platform and submission readiness

- [ ] Verify Android gallery access, timers, background/resume and release build on a physical phone.
- [ ] Build/sign/test iOS on a Mac and physical iPhone.
- [ ] Record a three-minute demo showing only verified features and clearly identified event work.
- [ ] Document live versus practice behavior and disclose reused foundations/assets.
- [ ] Audit public source for credentials, private codes, portraits and personal conversations.
- [ ] Select a project license after reviewing third-party asset rights.
- [ ] Verify repository access, video access and clean-machine setup instructions.
- [ ] Confirm the organizer's current submission requirements before submitting.

## Delivery order

Prioritize real Meta calls and the secured hosted court demo before expanding features. Then complete account pairing and two-phone court/chat synchronization. Location sharing and other optional couple features come after those foundations.

The November 4 build target is a planning goal, not a claim that every milestone above will be complete. If time is limited, present a truthful local court experience with verified live AI rather than imply unfinished multiplayer features are connected.
