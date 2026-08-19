@0xa1b2c3d4e5f60013;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Notification - system notification display, actions, lifecycle.
#
# Improvements beyond the original schema:
#   - NotificationActionId typed ID replaces bare Text.
#   - T.Duration for expireTimeout (was raw Int32 milliseconds).
#   - DataHandle for icons/images that may exceed 1KB.
#   - Subscription cancel method added.
#   - Pagination on getActive.
#   - Custom variant on UrgencyLevel.
#   - actionId in invokeAction uses typed NotificationActionId.
#
# Improvements (audit-7):
#   - NotificationChannel struct for per-category settings.
#   - NotificationData: batchId, parentId, aiPriority, encryptedPayload,
#     attestation, threadId, workflowId, channel.
#   - NotificationAction.payload for data-carrying actions.
#   - NotificationFilter for history/snooze queries.
#   - PreviewContent for rich notification previews.
#   - Snooze, getHistory, schedule, delegate methods.
#   - NotificationChannel management (false positive from
#     notification_channel.capnp): create, configure, monitor channels.
# ═══════════════════════════════════════════════════════════════════════

interface Notifications {
    show @0 (notification :NotificationData) -> (id :T.NotificationId);
    dismiss @1 (id :T.NotificationId) -> T.VoidResult;
    dismissAll @2 () -> T.VoidResult;

    getActive @3 (pagination :T.Pagination) -> (notifications :List(NotificationData));
    clear @4 (id :T.NotificationId) -> T.VoidResult;

    subscribeNotifications @5 () -> (subscription :NotificationsSubscription);

    invokeAction @6 (id :T.NotificationId, actionId :T.NotificationActionId) -> T.VoidResult;

    # ── Audit-7 additions ────────────────────────────────────

    # Temporarily dismiss and re-show later.
    snooze @7 (id :T.NotificationId, duration :T.Duration) -> T.VoidResult;

    # Notification audit trail — view past notifications.
    getHistory @8 (filter :NotificationFilter, pagination :T.Pagination) -> (notifications :List(NotificationData));

    # Schedule a future notification.
    schedule @9 (notification :NotificationData, triggerTime :T.Timestamp) -> (id :T.NotificationId);

    # Route notification to a different handler.
    delegate @10 (id :T.NotificationId, handlerId :Text) -> T.VoidResult;

    # ── Channel management (false positive: notification_channel) ─
    # Create a notification channel.
    createChannel @11 (channel :NotificationChannel) -> (channelId :T.ChannelId);

    # Update channel settings.
    updateChannel @12 (channelId :T.ChannelId, channel :NotificationChannel) -> T.VoidResult;

    # Delete a notification channel.
    deleteChannel @13 (channelId :T.ChannelId) -> T.VoidResult;

    # List all notification channels.
    listChannels @14 (pagination :T.Pagination) -> (channels :List(NotificationChannel));

    # Get a specific channel.
    getChannel @15 (channelId :T.ChannelId) -> (channel :NotificationChannel);

    # Get channel health/metrics.
    getChannelStats @16 (channelId :T.ChannelId) -> (stats :ChannelStats);

    # ── Notification Graphs & Threading ─────────────────────────

    # Get the full notification thread (parent + children chain).
    getNotificationThread @17 (notificationId :T.NotificationId) -> (thread :List(NotificationData));

    # Get child notifications for a parent.
    getChildNotifications @18 (parentId :T.NotificationId) -> (children :List(NotificationData));

    # Get all notifications in a thread/conversation.
    getThreadNotifications @19 (threadId :Text) -> (notifications :List(NotificationData));

    # ── Notification Analytics ───────────────────────────────────

    # Get analytics for a channel or app.
    getAnalytics @20 (filter :NotificationFilter) -> (analytics :NotificationAnalytics);

    # ── Attestation Verification ────────────────────────────────

    # Verify the attestation of a notification.
    verifyAttestation @21 (notificationId :T.NotificationId) -> (result :AttestationVerification);

    # ── Inter-Service Notifications (audit-10) ───────────────────

    # Send a notification between system services.
    sendInterServiceNotification @22 (notification :InterServiceNotification) -> (id :T.NotificationId);

    # ── Delivery Tracking (audit-10) ─────────────────────────────

    # Get delivery tracking for a notification.
    getDeliveryTracking @23 (notificationId :T.NotificationId) -> (tracking :DeliveryTracking);

    # Subscribe to delivery state changes.
    subscribeDeliveryTracking @24 (filter :DeliveryTrackingFilter) -> (subscription :DeliveryTrackingSubscription);

    # ── Priority Queue (audit-10) ────────────────────────────────

    # Get notification priority queue stats.
    getQueueStats @25 () -> (stats :QueueStats);

    # Reprioritize a notification in the queue.
    reprioritizeNotification @26 (notificationId :T.NotificationId, priority :QueuePriority) -> T.VoidResult;

    # List notifications in the priority queue.
    listQueuedNotifications @27 (pagination :T.Pagination) -> (entries :List(NotificationQueueEntry));
}

interface NotificationsSubscription {
    pull @0 () -> (notifications :List(NotificationData));
    cancel @1 () -> T.VoidResult;
}

interface DeliveryTrackingSubscription {
    pull @0 () -> (trackings :List(DeliveryTracking));
    cancel @1 () -> T.VoidResult;
}

# ── Notification Data ────────────────────────────────────────

struct NotificationData {
    id @0 :T.NotificationId;
    appName @1 :Text;
    # Application icon — use buffer handle for images >1KB.
    appIcon @2 :T.DataHandle;
    title @3 :Text;
    body @4 :Text;
    # Notification icon — use buffer handle for images >1KB.
    icon @5 :T.DataHandle;
    # Inline image attachment — use buffer handle for images >1KB.
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

    # ── Audit-7 additions ────────────────────────────────────
    # Group related notifications into summaries.
    batchId @14 :Text;
    # Parent notification for chaining into workflows.
    parentId @15 :T.NotificationId;
    # AI-assigned priority score (0.0 = low, 1.0 = critical).
    aiPriority @16 :Float32;
    # Encrypted notification content for sensitive data.
    encryptedPayload @17 :T.DataHandle;
    # Signed notification for provenance verification.
    attestation @18 :Data;
    # Group notifications by conversation.
    threadId @19 :Text;
    # Multi-flow notification workflow identifier.
    workflowId @20 :Text;
    # Channel this notification belongs to.
    channel @21 :T.ChannelId;
    # Rich preview content (audit-8: PreviewContent integrated into NotificationData).
    preview @22 :PreviewContent;
}

# ── Notification Action ──────────────────────────────────────

struct NotificationAction {
    id @0 :T.NotificationActionId;
    label @1 :Text;
    # Action icon — use buffer handle for images >1KB.
    icon @2 :T.DataHandle;
    # Action payload — actions that carry data (audit-7).
    payload @3 :T.DataHandle;
}

# ── Urgency Level ────────────────────────────────────────────

enum UrgencyLevel {
    low @0;
    normal @1;
    critical @2;
    custom @3;
}

# ── Notification Filter (audit-7) ────────────────────────────

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

# ── Preview Content (audit-7) ────────────────────────────────

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

# ── Notification Channel (audit-7 / false positive) ──────────
# Notification channel management is a feature of notification.capnp,
# not a separate schema. Channels group notifications by category
# with independent settings.

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
    # Light color for notification LED (0 = no light).
    lightColor @9 :UInt32;
    # Max notifications to show from this channel before compressing.
    maxVisible @10 :UInt32;
}

# ── Channel Stats (audit-7) ──────────────────────────────────

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

# ── Notification Analytics (audit-9) ───────────────────────

struct NotificationAnalytics {
    # Total notifications sent.
    totalSent @0 :UInt64;
    # Total notifications delivered.
    totalDelivered @1 :UInt64;
    # Delivery rate (delivered/sent).
    deliveryRate @2 :Float32;
    # Total notifications opened.
    totalOpened @3 :UInt64;
    # Open rate (opened/delivered).
    openRate @4 :Float32;
    # Total action completions.
    totalActionsCompleted @5 :UInt64;
    # Action completion rate.
    actionCompletionRate @6 :Float32;
    # Average time to open (from delivery).
    avgTimeToOpen @7 :T.Duration;
    # Average time to dismiss.
    avgTimeToDismiss @8 :T.Duration;
    # Time period for these stats.
    period @9 :T.TimeRange;
}

# ── Attestation Verification (audit-9) ─────────────────────

struct AttestationVerification {
    valid @0 :Bool;
    signer @1 :Text;
    timestamp @2 :T.Timestamp;
    error @3 :Text;
}

# ─── Inter-Service Notifications (audit-10) ───────────────

struct NotificationSource {
    sourceId @0 :Text;
    sourceType @1 :Text;
    # Whether this source is a system service.
    isSystemService @2 :Bool;
}

struct InterServiceNotification {
    source @0 :NotificationSource;
    targetService @1 :Text;
    eventType @2 :Text;
    payload @3 :T.DataHandle;
    priority @4 :UrgencyLevel;
}

# ─── Delivery Tracking (audit-10) ─────────────────────────

enum DeliveryState {
    pending @0;
    sent @1;
    delivered @2;
    opened @3;
    dismissed @4;
    failed @5;
    custom @6;
}

struct DeliveryTracking {
    notificationId @0 :T.NotificationId;
    state @1 :DeliveryState;
    sentAt @2 :T.Timestamp;
    deliveredAt @3 :T.Timestamp;
    openedAt @4 :T.Timestamp;
    dismissedAt @5 :T.Timestamp;
    failureReason @6 :Text;
    retryCount @7 :UInt32;
}

struct DeliveryTrackingFilter {
    notificationId @0 :T.NotificationId;
    states @1 :List(DeliveryState);
    since @2 :T.Timestamp;
    before @3 :T.Timestamp;
}

# ─── Priority Queue (audit-10) ─────────────────────────────

enum QueuePriority {
    low @0;
    normal @1;
    high @2;
    critical @3;
    custom @4;
}

struct NotificationQueueEntry {
    notificationId @0 :T.NotificationId;
    priority @1 :QueuePriority;
    enqueuedAt @2 :T.Timestamp;
    # Estimated processing time.
    estimatedProcessingAt @3 :T.Timestamp;
}

struct QueueStats {
    totalPending @0 :UInt32;
    totalProcessing @1 :UInt32;
    totalCompleted @2 :UInt64;
    totalFailed @3 :UInt64;
    avgWaitTimeMs @4 :Float32;
    oldestPendingAge @5 :T.Duration;
}
