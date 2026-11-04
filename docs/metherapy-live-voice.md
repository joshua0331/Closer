# Metherapy live voice

Android streams the existing WebRTC microphone through the authenticated Closer backend to Muse Voice Transcribe (ENDPOINTING, 16 kHz mono PCM). Both partners must explicitly join with audio consent. No raw audio is saved by Closer. Transcripts become shared session records and reach Muse Spark.

After detected speech ends, three seconds without a new speechStart finishes the input. End turn performs the same flush. Empty transcription does not submit a fabricated statement. Disconnects, stale turns, missing consent, and wrong speakers are rejected. Audio is bounded to one stream per turn, 4 MB, and about two minutes, with existing account AI quotas applied.

Replies use each phone’s installed text-to-speech voice. Both phones acknowledge playback before the next microphone opens; playback is coordinated, not sample-synchronized. This is not Meta-generated speech. Use Continue after spoken response if local speech playback fails.

Deploy with `powershell -ExecutionPolicy Bypass -File server\update-backend.ps1 -ProjectId iseeapp-ddf3a`, then rebuild/install the app on both Android phones. No additional API key is embedded in the app. The existing Secret Manager key must have Muse Voice Transcribe access and quota.

Device verification: join on both phones, hear opening, speak on the active phone, pause three seconds, confirm the transcript and AI reply on both phones. Test End turn, mute, backgrounding, loss of network, empty speech, and each selected language. The WebRTC connection still uses STUN only; networks requiring TURN need a TURN service configured before reliable cross-network calling. iOS capture is not implemented; its UI reports this rather than pretending to transcribe.

Reference: https://dev.meta.ai/docs/api-reference/voice/realtime
