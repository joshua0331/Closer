import 'package:flutter/material.dart';

class LegalPage extends StatelessWidget {
  const LegalPage({super.key, required this.kind});
  final String kind;
  static void open(BuildContext context, String kind) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => LegalPage(kind: kind)));
  static const content = <String, List<List<String>>>{
    "terms": [
      [
        "Agreement and operator",
        "These terms govern the Closer app operated by Joshua Christian Mirang, reachable at joshuachristianmirang@gmail.com. By using Closer, you agree to these terms and acknowledge the privacy policy.",
      ],
      [
        "Accounts and pairing",
        "Use an account you control and pair only with a consenting partner. Keep credentials and invitation details private. Do not access another couple’s records, impersonate others, harass anyone or track a person without consent.",
      ],
      [
        "Your content",
        "You retain rights to your content and grant the permissions needed to store, display, deliver and process it for features you choose. Only upload content you have permission to share with your partner and applicable service providers. Shared-memory deletion affects both partners; local originals and partner copies may remain.",
      ],
      [
        "AI features",
        "Meta services may process requested chat drafts, memory photos, shared session context and speech for enabled AI features. Review suggested replies before sending. Image tags are probabilistic and can miss or mislabel objects. Metherapy provides supportive conversation prompts, not professional medical, mental-health, legal or emergency advice. Do not rely on AI output as a diagnosis, binding ruling or guarantee of a relationship outcome.",
      ],
      [
        "Notifications and permissions",
        "Enabled notifications may display message text, sender names, invitation topics and sent times, including on a lock screen. Firebase processes notification data to deliver these features. You control notification visibility and permissions through your phone settings. Delivery, location updates and device-status freshness depend on connectivity, permissions and device behavior.",
      ],
      [
        "Availability and ending use",
        "Features may be interrupted, limited or changed. You may stop using Closer or request account deletion. We may restrict access for misuse or to protect the service. No clause excludes rights or remedies that applicable law does not allow us to exclude. Contact us with disputes or service concerns.",
      ],
      [
        "Changes",
        "We will date updates to these terms. Material changes should be reviewed before continued use.",
      ],
    ],
    "privacy": [
      [
        "Operator",
        "Closer is operated by Joshua Christian Mirang. Contact joshuachristianmirang@gmail.com for support, privacy, access, correction or deletion requests.",
      ],
      [
        "Data and private couple spaces",
        "We process account and profile information, pairing records, chats, photos, memories, session topics and contributions. Optional features process shared location, saved places, battery percentage, charging state and connection type. The backend checks account identity and couple membership before providing shared records. Couple spaces are not public. They are not end-to-end encrypted: authorized operators and service providers can process data to operate the service. Your partner can save or screenshot content.",
      ],
      [
        "Notifications",
        "When notifications are enabled, Google Firebase Cloud Messaging processes device registration identifiers and notification payloads. Notifications may contain the sender name, message preview, Metherapy invitation topic and sent time. These previews can appear on your lock screen or connected devices. Use your phone notification settings to disable notifications or hide sensitive previews. Delivery is not guaranteed.",
      ],
      [
        "Meta AI processing",
        "When you request reply suggestions, recent chat text is sent through our backend to Meta. When you enable photo tagging or choose Analyze photos, memory photos are sent to Meta to identify visible objects for search; this is not facial recognition. Tags can be incomplete or incorrect. Joining a Metherapy AI session authorizes processing of the shared topic and submitted turns; live transcription sends speech audio for transcription while the feature is active. Relevant photos are processed when submitted for AI review. API credentials remain on the backend. Provider processing and retention follow their applicable terms; we do not promise zero provider retention.",
      ],
      [
        "Storage and sharing",
        "Firebase and Google Cloud provide authentication, database, media storage, hosting and notifications. Meta provides AI processing. Operational logs and provider processing may occur outside your country. Local device storage can contain cached photos, settings and authentication credentials. We do not publish your couple chats as a public feed.",
      ],
      [
        "Deletion and choices",
        "You can delete individual photos or albums from shared Memories. This removes the memory records for both partners, but does not guarantee immediate removal of underlying uploaded media, backups, logs, notification copies or copies saved by your partner. Contact us for cloud media or account deletion. Unpairing or signing out is not account deletion. Shared content is retained until deleted or removed through maintenance or a verified request; no fixed automatic deletion schedule is promised. You can revoke location and notification permissions in device settings.",
      ],
      [
        "Audience and updates",
        "Closer is intended for adults. Metherapy is an AI conversation guide, not a licensed therapist or emergency service. We will date changes to this notice. Contact the operator with questions or to exercise applicable privacy rights.",
      ],
    ],
    "help": [
      [
        "Getting started",
        "Create an account, pair with your partner using an invitation, and allow only the permissions you want to use.",
      ],
      [
        "Metherapy",
        "Both partners must join the voice call. Wait for the AI to finish speaking, then speak on your turn. Tap End turn to hand over. If audio fails, reconnect both phones and check microphone permission.",
      ],
      [
        "Memories",
        "Search captions, album names or image tags. Choose Update photo search index to analyze older photos with Meta. Open an album and tap a photo’s delete button to remove it.",
      ],
      [
        "Notifications and location",
        "Enable notifications in phone settings. Location sharing is optional. Battery and connection status require your partner’s updated app to sync; readings can be stale when it is closed.",
      ],
      [
        "Support",
        "Contact Joshua Christian Mirang at joshuachristianmirang@gmail.com. Include the error and app version, but never send passwords or API keys.",
      ],
    ],
  };
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFFFAF7),
    appBar: AppBar(
      title: Text(
        kind == 'terms'
            ? 'Terms of Service'
            : kind == 'privacy'
            ? 'Privacy Policy'
            : 'Help',
      ),
      backgroundColor: const Color(0xFFFFFAF7),
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (kind != 'help') const Text('Updated November 5, 2026'),
        for (final section in content[kind] ?? content['help']!) ...[
          const SizedBox(height: 24),
          Text(section[0], style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          SelectableText(section[1], style: const TextStyle(height: 1.5)),
        ],
        const SizedBox(height: 24),
        Wrap(
          children: [
            for (final entry in {
              'terms': 'Terms',
              'privacy': 'Privacy',
              'help': 'Help',
            }.entries)
              TextButton(
                onPressed: () => open(context, entry.key),
                child: Text(entry.value),
              ),
          ],
        ),
      ],
    ),
  );
}
