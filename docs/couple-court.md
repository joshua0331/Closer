> Current connected implementation: see [connected-app.md](connected-app.md). The backend is deployed; real accounts, pairing, shared chat/photos/locations and server-owned court state are implemented. Spark and Wonder were live-tested on October 31, 2026. Earlier local-only setup notes below describe the legacy development path.

# Couple Court

A Flutter prototype with a pixel-art courtroom, Muse Image character generation and a multimodal Muse Spark judge for voluntary everyday disputes.

## Hearing flow

1. **File the case:** claimant and respondent names, disagreement, requested compensation/action, and a 1/2/3-minute turn limit.
2. **Characters:** optionally select both portraits and consent to a Muse Image upload. The model redraws both people into one complete pixel-art scene. The result is cached locally; there are no photographic face overlays.
3. **Openings and evidence:** each person gives a statement and may attach evidence photos with captions. Up to two exhibits per person, four total, 1 MB each. Both can inspect all submitted exhibits, identified as E1, E2, etc.
4. **Cross-examination:** each person asks one question; the other answers during a separate timed turn.
5. **Rebuttals:** each can clarify/challenge the other account and submit evidence if they still have a slot.
6. **Judge's questions:** review the record and explicitly consent to sending testimony and evidence images to Muse Spark. The judge examines each exhibit, states visible observations and limitations, and asks one question per person.
7. **Answers and ruling:** each answers within a timed turn. A second consented request sends the complete record for a final proposed outcome: grant, reduce, increase, deny or alternative. Original requested compensation remains unchanged beside the proposal.
8. **Accept or appeal:** both can accept, or the respondent can appeal. One appeal per prototype case includes grounds, claimant's response, any additional available exhibits and the prior ruling. The judge reviews the full record again. Revised acceptance starts fresh. Either person can leave the case unresolved.
9. **History:** accepted/unresolved outcome, transcript, exhibit references, judge findings and ruling/appeal history are saved locally.

Timers begin automatically on each speaking turn. They can be paused, but not reset mid-turn. Expiry locks editing and evidence submission; an empty turn is explicitly recorded as no response, not invented testimony. Native photo selection still needs a phone check.

## AI and privacy

- `muse-image-1.0`: reference courtroom plus two consented portraits generate a cohesive character scene. Character portraits do not go to the judge.
- `muse-spark-1.3`: actual evidence images are sent as multimodal input blocks alongside captions, role attribution, requested compensation, openings, cross-examination, rebuttals, judge answers and appeal material.
- Each judge upload needs explicit consent. The server accepts inline PNG/JPEG only, not arbitrary external URLs, and checks exhibit limits, IDs and owners.
- Every returned exhibit must have an observation and limitation. Unknown/missing exhibit references, changed original requests and malformed results are rejected.
- The judge is instructed not to authenticate photos/screenshots, infer motive from appearance, or treat captions as fact. Live model behavior still needs evaluation.
- Outcomes are voluntary, with no real legal/financial enforcement, medical/therapy advice, personality scoring, coercive penalties or automatic compensation payments.
- The practice flow is explicitly scripted. It does not inspect photos or issue a real AI finding.

## Run

```powershell
flutter pub get
flutter run
```

Without API setup the app shows reference artwork and supports practice hearings. For live Muse Image and Muse Spark, see server/README.md. MODEL_API_KEY stays on the server.

The app still runs both roles on one device. Remote accounts, invitations, server-authoritative timers and separate-phone sessions are not connected. Current case testimony and exhibits stay in memory until closed; closed records and generated scenes persist in this installation. Local preferences are not encrypted production storage. Uninstall/clear app data removes them.

## Checks

```powershell
flutter analyze --no-pub
flutter test --no-pub
python -m unittest discover -s server
```

Tests use synthetic evidence and mocked Meta responses. No live API call has been made without a configured key. Earlier app source is retained in archive/our-space-before-court.zip.

## Hackathon

The supplied guide explicitly includes Muse Image and Muse Spark. Couple Court targets Build for Your World as a playful everyday-dispute experience. Public repo, event-built work disclosures, asset rights and an accessible three-minute demo remain submission requirements; see docs/hackathon.md.


## Additional models — October 29, 2026

Questions and first rulings use Muse Spark; appeals route server-side to `muse-wonder-1.0` with the full prior record. No automatic Spark fallback is used for appeals.

`POST /segment` accepts one base64 exhibit and a short concrete object prompt. It calls `sam-3.1` through the Responses streaming API, validates complete output and returns normalized object boxes (not decoded pixel masks). The evidence viewer offers upload consent and a highlights toggle; the original remains unchanged and the judge still receives original evidence. SAM boxes do not authenticate evidence and are not treated as judge findings. No-match output is valid; malformed/incomplete output fails. This endpoint uses the existing session, total-call budget, deduplication and concurrency controls; it does not consume image-generation quota. Highlights are temporary and can be requested again, consuming another call. Live Meta validation remains pending.

Official formats: https://dev.meta.ai/docs/models and https://dev.meta.ai/docs/sam/reading-segmentation.
