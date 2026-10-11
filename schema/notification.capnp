@0xa1b2c3d4e5f60013;

# ═══════════════════════════════════════════════════════════════════════
# Notification - system notification display, actions, lifecycle.
#
# WHAT THIS IS
#   The ONE notification service, and the DND authority. Content, channels,
#   threading, attestation, scheduling, history and change subscription.
#   The shell delegates here; it no longer carries a rival notification model
#   (its copy had no channels, so a shell-posted notification escaped channel
#   routing entirely).
#
# WHAT WAS FIXED
#   - `show` and `schedule` used to return a bare `T.NotificationId`. Sending
#     can fail — no channel, quota exceeded, invalid attestation — so an app
#     "posted" a notification that was rejected and held a tombstone id. Both
#     now return a result union carrying `T.Error` with `retryable`, the
#     pattern appindex.capnp's `LaunchResult` established.
#   - Every list answer now carries a total, and the thread getters are
#     paginated: a notification-centre UI can render "12 of 40" and stop
#     paging, instead of paging until empty on every open. A chatty group
#     thread used to return its entire chain.
#   - `AttestationVerification.error` was `Text`. A consumer could not route
#     on it; it is now `T.Error`.
#   - There were THREE priority vocabularies in one file — `UrgencyLevel` for
#     display, `QueuePriority` for delivery, and an `aiPriority :Float32` in
#     the send path. There is now one: `UrgencyLevel`. `QueuePriority` and the
#     queue machinery it served are deleted, and the AI score is a
#     service-reported value that is ignored on write (its presence in the
#     send path invited every backend to either run a scorer or invent a
#     number).
#
# WHAT WAS DELETED, AND WHY
#   - The inter-service notification path (`sendInterServiceNotification` and
#     its `NotificationSource`/`InterServiceNotification` model): a second way
#     to emit a notification, with no channels, no actions and no threads, so
#     a receiver needed two dispatch tables.
#   - Delivery tracking (`getDeliveryTracking`, `subscribeDeliveryTracking`,
#     `DeliveryTracking*`) and the priority queue (`getQueueStats`,
#     `reprioritizeNotification`, `listQueuedNotifications`,
#     `QueueStats`, `NotificationQueueEntry`): a notification SERVER's
#     internals exposed as contract, with no consumer protocol behind them.
#     Delivery observability belongs to a diagnostics service.
#   - `getAnalytics` and `NotificationAnalytics`: same class.
#   - `delegate @10 (handlerId :Text)`: routing addressed by free text, with
#     no way to enumerate handlers, so every implementer hardcoded strings.
#   - `NotificationChannel.lightColor`: a notification LED is a component
#     that existed on 2010 phones. A display-only or audio-only device has
#     none, and the field's semantics ("0 = no light") presumed it.
#
# REPLACEMENT/UPDATE SEMANTICS, STATED SO NO BACKEND GUESSES
#   `show` with an id the app already holds REPLACES that notification
#   (same id, same position, new content). That is what a progress
#   notification needs, and it is the rule rather than an implementation
#   detail. Posting a fresh notification means posting an id the app does not
#   hold.
#
# SNOOZE PERSISTENCE, STATED SO NO BACKEND GUESSES
#   A snoozed notification is the service's responsibility: it survives a
#   service restart, and the service re-shows it after the duration elapses.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

interface Notifications {
    # Post a notification. Replaces a notification whose id the caller
    # already holds (see the header).
    show @0 (notification :NotificationData) -> (result :ShowResult);
    dismiss @1 (id :T.NotificationId) -> T.VoidResult;
    dismissAll @2 () -> T.VoidResult;

    getActive @3 (pagination :T.Pagination)
              -> (notifications :List(NotificationData), total :UInt64);
    clear @4 (id :T.NotificationId) -> T.VoidResult;

    subscribeNotifications @5 () -> (subscription :NotificationsSubscription);

    invokeAction @6 (id :T.NotificationId, actionId :T.NotificationActionId)
                 -> T.VoidResult;

    # Temporarily dismiss and re-show later. The service persists the snooze
    # across its own restarts.
    snooze @7 (id :T.NotificationId, duration :T.Duration) -> T.VoidResult;

    # Notification history — view past notifications.
    getHistory @8 (filter :NotificationFilter, pagination :T.Pagination)
               -> (notifications :List(NotificationData), total :UInt64);

    # Schedule a future notification.
    schedule @9 (notification :NotificationData, triggerTime :T.Timestamp)
              -> (result :ShowResult);

    # ── Channel management ────────────────────────────────────
    # Channels group notifications by category with independent settings.

    createChannel @10 (channel :NotificationChannel) -> (result :ChannelResult);
    updateChannel @11 (channelId :T.ChannelId, channel :NotificationChannel)
                   -> T.VoidResult;
    deleteChannel @12 (channelId :T.ChannelId) -> T.VoidResult;
    listChannels @13 (pagination :T.Pagination)
                 -> (channels :List(NotificationChannel), total :UInt64);
    getChannel @14 (channelId :T.ChannelId) -> (result :ChannelResult);
    getChannelStats @15 (channelId :T.ChannelId) -> (stats :ChannelStats);

    # ── Notification Graphs & Threading ─────────────────────────

    # Get the full notification thread (parent + children chain).
    getNotificationThread @16 (notificationId :T.NotificationId,
                               pagination :T.Pagination)
                          -> (notifications :List(NotificationData), total :UInt64);

    # Get child notifications for a parent.
    getChildNotifications @17 (parentId :T.NotificationId,
                               pagination :T.Pagination)
                          -> (notifications :List(NotificationData), total :UInt64);

    # Get all notifications in a thread/conversation.
    getThreadNotifications @18 (threadId :Text, pagination :T.Pagination)
                           -> (notifications :List(NotificationData), total :UInt64);

    # ── Attestation Verification ────────────────────────────────

    verifyAttestation @19 (notificationId :T.NotificationId)
                      -> (result :AttestationCheck);

    # ── Do Not Disturb (this service is THE DND authority) ───────
    # Channel `bypassDnd` is evaluated against this one switch. The shell
    # reads and writes it here rather than keeping a second copy.

    getDoNotDisturb @20 () -> (enabled :Bool);
    setDoNotDisturb @21 (enabled :Bool) -> T.VoidResult;
}

interface NotificationsSubscription {
    pull @0 (maxEvents :UInt32) -> (notifications :List(NotificationData));
    cancel @1 () -> T.VoidResult;
}

# ── Results ───────────────────────────────────────────────────

struct ShowResult {
    union {
        id      @0 :T.NotificationId;
        error   @1 :T.Error;
        unknown @2 :Void;
    }
}

struct ChannelResult {
    union {
        channel @0 :NotificationChannel;
        error   @1 :T.Error;
        unknown @2 :Void;
    }
}

struct AttestationCheck {
    union {
        verified   @0 :AttestationVerification;
        unverified @1 :T.Error;
        unknown    @2 :Void;
    }
}

# ── Notification Data ────────────────────────────────────────

struct NotificationData {
    id @0 :T.NotificationId;
    appName @1 :Text;
    # Application icon — buffer reference for images >1KB.
    appIcon @2 :T.DataHandle;
    title @3 :Text;
    body @4 :Text;
    icon @5 :T.DataHandle;
    image @6 :T.DataHandle;
    # Sound identifier (typed for cross-backend compatibility).
    sound @7 :T.SoundId;
    category @8 :Text;
    urgency @9 :UrgencyLevel;
    actions @10 :List(NotificationAction);
    hints @11 :T.StringMap;
    # Time after which the notification expires. Zero means no expiration.
    expireTimeout @12 :T.Duration;
    # Whether the notification is transient (auto-dismissed, not persisted).
    transient @13 :Bool;

    # Group related notifications into summaries. Caller-chosen correlation
    # key, not a service-issued handle.
    batchId @14 :Text;
    # Parent notification for chaining into workflows.
    parentId @15 :T.NotificationId;
    # Encrypted notification content for sensitive data: an opaque blob the
    # service stores and never parses.
    encryptedPayload @16 :T.DataHandle;
    # Signed notification for provenance verification.
    attestation @17 :Data;
    # Group notifications by conversation.
    threadId @18 :Text;
    # Multi-flow notification workflow identifier.
    workflowId @19 :Text;
    # Channel this notification belongs to.
    channel @20 :T.ChannelId;
    # Rich preview content.
    preview @21 :PreviewContent;
    # Service-reported ranking. IGNORED ON WRITE: the service decides
    # ordering, and a caller-supplied score is an invitation to fiction.
    reportedRank @22 :Float32;
}

# ── Notification Action ──────────────────────────────────────

struct NotificationAction {
    id @0 :T.NotificationActionId;
    label @1 :Text;
    # Action icon — buffer reference for images >1KB.
    icon @2 :T.DataHandle;
    # Action payload — actions that carry data.
    payload @3 :T.DataHandle;
}

# ── Urgency Level ────────────────────────────────────────────
# The one priority vocabulary in this file.

enum UrgencyLevel {
    # Absent means the backend decides; it must never silently mean a
    # specific paradigm value.
    any @0;
    low @1;
    normal @2;
    critical @3;
    custom @4;
}

# ── Notification Filter ──────────────────────────────────────

struct NotificationFilter {
    # Filter by app name.
    appName @0 :Text;
    # Filter by category.
    category @1 :Text;
    # Filter by urgency level.
    urgency @2 :UrgencyLevel;
    # Only notifications after this timestamp.
    since @3 :T.Timestamp;
    # Only notifications before this timestamp.
    before @4 :T.Timestamp;
    # Filter by thread (conversation grouping).
    threadId @5 :Text;
    # Filter by batch (grouped notifications).
    batchId @6 :Text;
}

# ── Preview Content ──────────────────────────────────────────

struct PreviewContent {
    # Whether the notification has expandable preview.
    expanded @0 :Bool;
    # Preview image.
    image @1 :T.DataHandle;
    # Preview actions.
    actions @2 :List(NotificationAction);
    # Preview body text (richer than notification body).
    body @3 :Text;
}

# ── Notification Channel ─────────────────────────────────────

struct NotificationChannel {
    # Unique channel identifier.
    id @0 :T.ChannelId;
    # Human-readable channel name.
    name @1 :Text;
    # Channel description.
    description @2 :Text;
    # Importance level for this channel.
    importance @3 :UrgencyLevel;
    # Sound to play for notifications on this channel.
    sound @4 :T.SoundId;
    # Whether to vibrate for notifications on this channel.
    vibration @5 :Bool;
    # Whether notifications on this channel bypass Do Not Disturb.
    bypassDnd @6 :Bool;
    # Whether notifications on this channel are enabled.
    enabled @7 :Bool;
    # Whether notifications on this channel show on lock screen.
    showOnLockScreen @8 :Bool;
    # Max notifications to show from this channel before compressing.
    maxVisible @9 :UInt32;
}

# ── Channel Stats ────────────────────────────────────────────

struct ChannelStats {
    channelId @0 :T.ChannelId;
    # Total notifications shown on this channel.
    totalShown @1 :UInt64;
    # Total notifications dismissed.
    totalDismissed @2 :UInt64;
    # Total actions invoked.
    totalActions @3 :UInt64;
    # Average time to dismiss (user attention span).
    avgTimeToDismiss @4 :T.Duration;
    # Last notification timestamp.
    lastNotificationAt @5 :T.Timestamp;
}

# ── Attestation Verification ─────────────────────────────────

struct AttestationVerification {
    valid @0 :Bool;
    signer @1 :Text;
    timestamp @2 :T.Timestamp;
}
