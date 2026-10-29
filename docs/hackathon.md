# Hackathon implementation notes — October 29, 2026

Source: the participant guide pasted by the user from https://cerebralvalley.ai/e/meta-ai-developer-hackathon/details.

The supplied guide explicitly includes Muse Spark, Muse Wonder, Muse Image, Muse Voice Transcribe, SAM 3.1 and eligible Meta open-weight models. This app uses:

- muse-image-1.0 through Meta Model API: two consented portraits plus the courtroom reference become a cohesive pixel-art scene, not photographic overlays. Model, response ID and prompt version are saved with the scene.
- muse-spark-1.3 through Meta Model API: both written statements become a fair summary and practical suggestion. The response carries actual provider model attribution. Scripted practice is clearly separated.

Problem statement: Build for Your World. Product scope: playful discussion of ordinary everyday disagreements. The guide bans AI medical/mental-health advice products and personality analyzers. Do not market Couple Court as therapy, diagnose users, infer personality from photographs or produce medical advice. The judge prompt excludes these behaviors; prompt adherence still needs live evaluation.

Guide requirements to satisfy before submitting:

- Public source repository; do not include credentials, portraits or private conversations.
- Accessible three-minute demo video highlighting only features/code/functionality built during the event.
- Clearly identify original event work and disclose any reused foundation. Use development history rather than assuming creation dates.
- Use only code/data/assets you have rights to use; obtain consent for participant portraits and demo recordings.
- List all contributors; maximum four team members. One representative submits a team project.
- Submit by November 4, 2026 at 9 PM EST, equivalent to November 5 at 10 AM Singapore time. Keep November 4 as the build target.

The guide's Best Creative Build award specifically recognizes Muse Image or Muse Wonder, but using a model does not guarantee eligibility or an award.

Artwork provenance: assets/court/courtroom.png is the supplied reference created earlier using an external image-generation tool, not a Meta-generated original. It is sent as a layout/style reference when Muse Image creates new scenes. Disclose the reference and other tools used; do not claim the original reference was generated with Muse Image.

Technical docs checked:
- https://dev.meta.ai/docs/quickstart
- https://dev.meta.ai/docs/image-generation
- https://dev.meta.ai/docs/api-reference/images/edit-image

API integration and rules alignment are implemented, but full submission compliance also depends on actual live operation, rights, accepted event terms and truthful demo disclosures. No live Meta call has been made until an API key is configured.

## Expanded hearing scope

The current courtroom collects evidence photos, cross-examination, rebuttals and judge questions, then returns a voluntary compensation proposal tied to the claimant's original request. Muse Spark receives actual image input blocks and is prompted to state visual observations separately from unverifiable context. It does not authenticate screenshots, diagnose users, score personalities or enforce penalties.

One appeal re-examines the prior ruling, grounds, the other participant's response and exhibits. Demo the actual image observations/uncertainty and an adjustment on appeal after a real API run; do not present scripted practice results or mocked tests as live model findings. Get consent for any evidence or portraits shown in a public demo.
