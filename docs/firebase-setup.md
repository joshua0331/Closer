# Firebase setup for Closer — do this when ready

Use one Firebase project for Android and iOS. Two phones install the same app but sign in to separate accounts. Do not create a separate Firebase project per phone.

## Console setup

1. Open https://console.firebase.google.com/ and select your existing project `iseeapp-ddf3a` (iseeapp), as requested. Add Closer as new app registrations; do not replace the iSee app entries. Applications in this project share Authentication, billing and other project resources.
2. Copy the Project ID from Project settings > General.
3. Open Authentication > Get started > Sign-in method and enable Email/Password. Email-link sign-in is not needed for the first version.
4. Open Firestore Database > Create database, choose Standard edition if asked, Production mode, and a suitable region near users. Keep access restricted until the app's membership rules are deployed.
5. For shared photos and deployed Cloud Functions, upgrade to Blaze and link billing, then create a Cloud Storage bucket. Use restricted rules. Set budget alerts; they do not automatically cap bills. Firebase charges are separate from Meta hackathon credits.
6. In Project overview, register the Android app using the CURRENT exact package name `com.jcm.closer`. App nickname: Closer Android. Download google-services.json into android/app/google-services.json. Email/password does not require a SHA-1 entry.
7. Register the iOS app in the SAME project using the CURRENT exact bundle identifier `com.jcm.closer`. App nickname: Closer iOS. Download GoogleService-Info.plist into ios/Runner/GoogleService-Info.plist. FlutterFire/Xcode target configuration still needs to be completed; copying a plist alone is not the complete iOS setup.
8. Send the Project ID in this chat and confirm which configuration files are in place. Do not send your Google password, a service-account private key or your Meta key.

The visible name Closer is independent of these technical identifiers. Changing package/bundle IDs later means registering/configuring new Firebase app entries.

## Code integration after creation

- Configure Android/iOS with FlutterFire and initialize Firebase.
- Add real accounts and one-time partner invitations with revocable membership.
- Sync shared chat, summons, cases and turn deadlines through Firestore.
- Store private photos, evidence and Muse scenes in Cloud Storage with couple/case access rules.
- Move Meta calls and secrets to authenticated cloud functions, with quotas and duplicate-request protection.
- Enforce roles/turn transitions, deadlines, both approvals and appeal state on the server.
- Add push notifications, then optional consent-based location sharing with clear pause controls.

Both phones must use the same cloud case, not separate copies of the current local hearing. The current local demo token is not production authentication. Android/iOS need separate device testing; an iOS build needs macOS/Xcode.

Official references checked during this chat:
- https://firebase.google.com/docs/flutter/setup
- https://firebase.google.com/docs/auth/flutter/password-auth
- https://firebase.google.com/docs/firestore/quickstart
- https://firebase.google.com/docs/storage/flutter/start
- https://firebase.google.com/docs/functions/get-started
- https://firebase.google.com/docs/functions/config-env
