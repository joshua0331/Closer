# Lasting couple connection — next implementation

## Product flow

1. Each partner creates their own account.
2. One creates a short-lived invitation. It can be shared as a code or link.
3. The recipient signs in, reviews who invited them and explicitly accepts.
4. A single couple ID is attached to both accounts. Signing in on another phone restores this membership. There is no room creation for daily use.
5. Either can revoke an invitation or unpair later. “Lasting” does not mean irrevocable.

The shared couple space contains chat, memories, court cases and optional location sharing. It is private to those two accounts. The current local preview is not a real membership and should not be silently uploaded after signup; offer an explicit migration choice.

## Proposed Firebase layout

- users/{uid}: profile, coupleId (set by server), notification preferences.
- pairingInvites/{tokenHash}: inviter, expiry, redeemedBy; server-only lookup and redemption.
- couples/{coupleId}: two member IDs, creation time, active/unpaired state.
- couples/{coupleId}/messages/{id}: author, text or court reference, server creation time.
- couples/{coupleId}/memories/{id}: author, caption, storage path, creation time.
- couples/{coupleId}/cases/{id}: creator, topic, participants, acceptance, stage, active speaker, timer timestamps, proposed agreement and separate approvals.
- couples/{coupleId}/locations/{uid}: latest coordinates, accuracy, observed time and consent state; accessible only while sharing is enabled.
- users/{uid}/devices/{id}: notification tokens, owner-managed and excluded from partner reads.

Photo files belong under a couple-specific storage path. Their access policy must follow current couple membership; avoid permanent public URLs for private photos. Access rules and server functions must be tested before connecting real users. This design does not claim end-to-end encryption.

## Server-owned operations

- Create/revoke invitation: cryptographically random token, short expiry, hash stored server-side, rate-limited requests and no case data exposed through an invite.
- Accept invitation: authenticated transaction checks expiry, distinct users, both still unpaired, and invitation unused; creates one couple and updates both users atomically. Concurrent redemption must yield one winner.
- Unpair: remove active access for both, revoke pending invites/tokens and define retained/deleted data explicitly.
- Summon: validate membership, create case plus referenced chat entry atomically, then queue a deduplicated notification. A notification is a prompt; the database is authoritative.
- Accept/decline summons: partner chooses whether to attend. Either can leave. Only start once both are ready.
- Transition hearing: validate actor, current stage and case version. Use server timestamps plus duration/paused remainder, never independent client countdowns. Reject stale/repeated transitions and handle reconnects.
- Agreement: keep separate approvals for the same agreement version; an edit resets both approvals. Mark closed only after both accept.

## Optional distance

Ask each person separately before location access. Begin with foreground-only updates, with clear pause/revoke controls. Show distance only when both consent and both samples are recent; otherwise show unavailable or last updated. Revoke partner reads immediately when sharing stops or the couple unpairs. Do not display simulated distance. Background tracking needs a separate product decision and platform setup.

## Notification behavior

Use push notifications when the app is closed, and live data subscriptions when open. Opening a summons notification loads the referenced case and rechecks membership and status. Hide disagreement text from lock-screen previews by default. Muting notifications must not break chat or case delivery.

## Delivery sequence

1. Firebase project and Android/iOS registration; authentication and recovery.
2. Invitation create/accept/unpair functions with emulator-tested access rules.
3. Shared chat with server ordering, reconnect state and duplicate-safe sends.
4. Private photo uploads with ownership, size/type limits and deletion.
5. Online hearing state, both approvals and push notifications.
6. Optional foreground distance with explicit consent and stale-state handling.

## Acceptance checks before online release

- Both devices keep the same membership after restart/sign-in.
- A third account cannot read messages, images, cases or locations.
- Expired/reused invitations fail; simultaneous accepts cannot create multiple memberships.
- A summons appears in both chats and opens the same case.
- Reconnection restores the correct speaker and countdown; duplicate taps do not skip stages.
- One partner cannot approve for the other.
- Unpairing or stopping sharing revokes relevant access.
- Photo permission denial/cancellation and upload failure are recoverable.
