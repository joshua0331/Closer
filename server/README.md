> Current connected implementation: see [connected-app.md](../docs/connected-app.md). The backend is deployed; real accounts, pairing, shared chat/photos/locations and server-owned court state are implemented. Spark and Wonder were live-tested on October 31, 2026. Earlier local-only setup notes below describe the legacy development path.

# Local Meta judge demo

The judge uses Meta Model API directly: https://api.meta.ai/v1/responses, with muse-spark-1.3 by default. Only Meta Muse Spark variants can be selected at server startup. No Llama, Groq or non-Meta fallback is used.

1. In the Meta Model API dashboard, create your API key. Add MODEL_API_KEY to your local environment. Do not paste it in chat, commit it or put it in Flutter.
2. Generate a random temporary COURT_DEMO_TOKEN (at least 24 characters). Set it in the server environment.
3. Run `python server/judge_server.py` from the project root. Python 3.10+ is sufficient; no pip dependencies.
4. Launch Flutter with the judge URL and the SAME temporary demo token:

```powershell
flutter run --dart-define=JUDGE_URL=http://10.0.2.2:8787/judge --dart-define=COURT_DEMO_TOKEN=YOUR_TEMPORARY_DEMO_TOKEN
```

10.0.2.2 is the Android emulator's host-computer address. For Windows desktop use http://127.0.0.1:8787/judge. The Android cleartext exception is debug-only and limited to these local development addresses. For a physical phone, use a private HTTPS proxy/tunnel to the local server and pass its /judge URL; do not expose this prototype publicly.

The token in the demo app is recoverable from its build. This is a local development access check, not production authentication. Public deployment needs authenticated users, server-side session authorization, HTTPS, and per-account quotas. The server binds to loopback only, limits request size and calls, and never logs testimony or API keys.

The user explicitly confirms sending names, topic and both statements before each live judge request. Portraits are excluded from judge requests; the separate Muse Image upload requires its own consent. `store: false` requests no server-managed response storage; it is not a promise about Meta's overall retention policy. Consult your account's policy before using real private conversations.

No live request has been tested until an API key is configured. All automated upstream tests use mocks, not hackathon credits.

Docs verified October 29, 2026:
- https://dev.meta.ai/docs/quickstart
- https://dev.meta.ai/events/global-hackathon

The participant guide supplied by the user explicitly allows Muse Spark and Muse Image. Public-repository, new-work, rights and three-minute-demo requirements are summarized in docs/hackathon.md. The reference courtroom was created with an external image-generation tool before this pivot; document that provenance and replace it with Muse Image output if the rules require it. Do not describe it as Meta-generated artwork.

## Muse Image characters

The same server now accepts POST /characters. The Flutter app derives this URL from JUDGE_URL; optionally override it with --dart-define=CHARACTER_URL=https://YOUR_SERVER/characters.

The server calls Meta's Responses endpoint with model muse-image-1.0, store:false, and three ordered reference images: bundled courtroom, left participant portrait, right participant portrait. It requests a complete PNG scene with both faces redrawn in pixel art. There is no face-overlay fallback. Web/image search and shell tools are disabled. The result is returned as base64 with model, response ID and prompt version; the app validates it, saves it locally and reuses it.

The app asks both people to consent before upload. Portraits are limited to 1 MB each (the picker downsizes them to 512 px). They must be PNG/JPEG. No portraits or generated outputs are written by the proxy server or logged. The model provider still receives these photos: store:false is not a blanket promise about provider retention. Read Meta's account policy before using private images. Character portraits are excluded from the judge; hearing evidence photos are uploaded separately after consent.

Timeouts are 180 seconds upstream and 200 seconds in the app. Cancelled consent sends nothing. A request failure leaves the previous scene intact. Changing a source portrait clears the saved personalized scene selection. A new manual generation is required.

The participant guide is now available from the user's pasted text. See docs/hackathon.md for the updated requirements; its account of the guide supersedes the earlier note that private rules were unavailable. Muse Image and Muse Spark are expressly listed. No live key has been used yet. Automated tests use synthetic image fixtures and mocked model responses, not participant photos or API credits.

## Multimodal hearings and appeals

The app now derives POST /hearing from JUDGE_URL. The legacy /judge route remains for the earlier text-only client, but the active courtroom uses /hearing for questions, verdict and appeal.

Each call supplies action and a bounded case record. Evidence images are inline base64 PNG/JPEG, max 1 MB each, four total/two per owner, with unique IDs and captions. The server turns these into real input_image content parts for muse-spark-1.3. Names, claimant request, openings, cross questions/answers, rebuttals, judge questions/answers and appeal material are sent alongside. Only evidence photos are sent; character portraits are excluded.

The judge returns validated structured JSON. Every exhibit must have a matching observation and limitation. Unsupported IDs, missing reviews, malformed fields, incomplete responses and alterations to the original requested remedy fail without replacing the prior ruling. An appeal must include the previous ruling and both the respondent's grounds and claimant's response.

The UI requests explicit consent before each case/evidence upload. The server processes evidence in memory and suppresses request logs. The app saves accepted/unresolved records locally with transcript, file references and both ruling versions. Upload consent does not make evidence authentic; the judge prompt explicitly treats images/captions as unverified and rules out appearance-based guilt/personality inference.

One appeal is available in the prototype. Both people accept the proposed remedy before closure, and appeal results reset both approvals. They can also decline. There are no real payouts, mandatory punishments or legal decisions. Timer and role enforcement are local UI behavior; production multi-device use needs authenticated participants and authoritative server state.

Hearing request limit: 6.1 MB; Meta timeout 75 seconds; app timeout 90 seconds. Test coverage includes ordered image parts, testimony completeness, exhibit limits/references, preserving original requests, appeal prerequisites, a full UI hearing/appeal and expired-turn input locking. No upstream API credits or private images are used in tests.

Official vision format: https://dev.meta.ai/docs/image-understanding

## Hosted judging demo

For the new private-code, expiring-session hosted API, use hosted_app.py and follow docs/hosted-demo.md. The older judge_server.py remains a local-only developer proxy. The public app build contains BACKEND_URL only; judges enter their private demo code inside Closer. The selected Firebase/Google Cloud project is iseeapp-ddf3a, with a separate closer-demo-backend database planned to avoid changing iSee's default data/rules. Nothing is deployed yet.



## Additional models — October 29, 2026

Questions and first rulings use Muse Spark; appeals route server-side to `muse-wonder-1.0` with the full prior record. No automatic Spark fallback is used for appeals.

`POST /segment` accepts one base64 exhibit and a short concrete object prompt. It calls `sam-3.1` through the Responses streaming API, validates complete output and returns normalized object boxes (not decoded pixel masks). The evidence viewer offers upload consent and a highlights toggle; the original remains unchanged and the judge still receives original evidence. SAM boxes do not authenticate evidence and are not treated as judge findings. No-match output is valid; malformed/incomplete output fails. This endpoint uses the existing session, total-call budget, deduplication and concurrency controls; it does not consume image-generation quota. Highlights are temporary and can be requested again, consuming another call. Live Meta validation remains pending.

Official formats: https://dev.meta.ai/docs/models and https://dev.meta.ai/docs/sam/reading-segmentation.
