@0xa1b2c3d4e5f60011;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Media - playback control, metadata, volume, transport, playlists,
#         live-stream, chapters, lyrics, analytics, sync-aware.
#
# Improvements beyond the original schema:
#   - MediaPlayerId typed ID replaces raw UInt64.
#   - MediaItemId typed ID replaces bare Text.
#   - All positions/durations use T.Duration (nanosecond precision).
#   - DataHandle for artwork that may exceed 1KB.
#   - Subscription cancel method added.
#   - Pagination on listPlayers.
#   - Custom/other variants on enums for forward compatibility.
#   - Volume and rate documented with units and valid ranges.
#
# Audit-8 enhancements:
#   - Chapter markers for long-form content navigation.
#   - LyricsData with synchronized line/word timing.
#   - LiveStream for real-time broadcast with viewer analytics.
#   - Content-addressed media via contentHash on MediaItem.
#   - E2E encryption flag on MediaItem.
#   - AI-generated tags on MediaMetadata.
#   - Sync-aware playback via syncGroup on MediaPlayer.
#   - Playlist management (create, add, remove, reorder).
#   - Format negotiation and transcoding.
#   - Recommendations, analytics, sharing, download, crossfade.
# ═══════════════════════════════════════════════════════════════════════

interface Media {
    # ── Player discovery ──
    listPlayers @0 (pagination :T.Pagination) -> (players :List(MediaPlayer));
    getPlayer @1 (playerId :T.MediaPlayerId) -> (player :MediaPlayer);

    # ── Transport controls ──
    play @2 (playerId :T.MediaPlayerId) -> T.VoidResult;
    pause @3 (playerId :T.MediaPlayerId) -> T.VoidResult;
    stop @4 (playerId :T.MediaPlayerId) -> T.VoidResult;
    next @5 (playerId :T.MediaPlayerId) -> T.VoidResult;
    previous @6 (playerId :T.MediaPlayerId) -> T.VoidResult;
    seek @7 (playerId :T.MediaPlayerId, position :T.Duration) -> T.VoidResult;

    # ── Metadata / position ──
    getMetadata @8 (playerId :T.MediaPlayerId) -> (metadata :MediaMetadata);
    getPosition @9 (playerId :T.MediaPlayerId) -> (position :T.Duration, duration :T.Duration);

    # ── Volume / rate ──
    # volume: 0.0 (mute) to 1.0 (full). Values outside range are clamped.
    setVolume @10 (playerId :T.MediaPlayerId, volume :Float32) -> T.VoidResult;
    setPosition @11 (playerId :T.MediaPlayerId, position :T.Duration) -> T.VoidResult;

    # ── URI playback ──
    openUri @12 (playerId :T.MediaPlayerId, uri :T.Uri) -> T.VoidResult;

    # ── Subscription ──
    subscribePlayer @13 (playerId :T.MediaPlayerId) -> (subscription :PlayerSubscription);

    # ── Audit-8: Format negotiation ──
    getSupportedFormats @14 (playerId :T.MediaPlayerId) -> (formats :List(Text));

    # ── Audit-8: Transcoding ──
    transcode @15 (mediaId :T.MediaItemId, targetFormat :Text) -> (transcoded :T.DataHandle);

    # ── Audit-8: Recommendations ──
    getRecommendations @16 (playerId :T.MediaPlayerId) -> (items :List(MediaItem));

    # ── Audit-8: Analytics ──
    getAnalytics @17 (mediaId :T.MediaItemId) -> (analytics :MediaAnalytics);

    # ── Audit-8: Sharing ──
    shareMedia @18 (mediaId :T.MediaItemId, targetDeviceId :T.DeviceId) -> (shareLink :T.Uri);

    # ── Audit-8: Download ──
    downloadMedia @19 (mediaId :T.MediaItemId) -> (downloadId :UInt64);

    # ── Audit-8: Crossfade ──
    setCrossfade @20 (playerId :T.MediaPlayerId, duration :T.Duration) -> T.VoidResult;

    # ── Audit-8: Sync-aware playback ──
    setSyncGroup @21 (playerId :T.MediaPlayerId, syncGroup :Text) -> T.VoidResult;

    # ── Audit-8: Playlist management ──
    createPlaylist @22 (name :Text, items :List(MediaItem)) -> (playlistId :UInt64);
    addToPlaylist @23 (playlistId :UInt64, item :MediaItem) -> T.VoidResult;
    removeFromPlaylist @24 (playlistId :UInt64, index :UInt32) -> T.VoidResult;
    reorderPlaylist @25 (playlistId :UInt64, fromIndex :UInt32, toIndex :UInt32) -> T.VoidResult;

    # -- Audit-9: Recommendation scoring --
    getRecommendationsWithScores @26 (playerId :T.MediaPlayerId, page :T.Pagination)
        -> (recommendations :List(RecommendationScore), total :UInt32);

    # -- Audit-9: Sharing preview --
    getSharePreview @27 (mediaId :T.MediaItemId) -> (preview :SharePreview);

    # -- Audit-9: Download status --
    getDownloadStatus @28 (downloadId :UInt64) -> (status :DownloadStatus);
    listDownloads @29 (pagination :T.Pagination) -> (statuses :List(DownloadStatus), total :UInt32);
    pauseDownload @30 (downloadId :UInt64) -> T.VoidResult;
    resumeDownload @31 (downloadId :UInt64) -> T.VoidResult;
    cancelDownload @32 (downloadId :UInt64) -> T.VoidResult;
    subscribeDownload @33 (downloadId :UInt64) -> (subscription :DownloadSubscription);

    # -- Audit-9: Crossfade details --
    setCrossfadeConfig @34 (playerId :T.MediaPlayerId, config :CrossfadeConfig) -> T.VoidResult;
    getCrossfadeConfig @35 (playerId :T.MediaPlayerId) -> (config :CrossfadeConfig);

    # -- Audit-9: Live stream interaction --
    sendLiveInteraction @36 (streamUrl :T.Uri, interaction :LiveInteraction) -> T.VoidResult;
    subscribeLiveInteractions @37 (streamUrl :T.Uri) -> (subscription :LiveInteractionSubscription);

    # -- Audit-9: Transcoding progress --
    subscribeTranscode @38 (transcodeId :UInt64) -> (subscription :TranscodeSubscription);
}

interface PlayerSubscription {
    pull @0 () -> (events :List(PlayerEvent));
    cancel @1 () -> T.VoidResult;
}

# -- Audit-9: Download subscription --
interface DownloadSubscription {
    pull @0 () -> (status :DownloadStatus);
    cancel @1 () -> T.VoidResult;
}

# -- Audit-9: Live interaction subscription --
interface LiveInteractionSubscription {
    pull @0 () -> (interactions :List(LiveInteraction));
    cancel @1 () -> T.VoidResult;
}

# -- Audit-9: Transcode subscription --
interface TranscodeSubscription {
    pull @0 () -> (progress :TranscodeProgress);
    cancel @1 () -> T.VoidResult;
}

struct PlayerEvent {
    union {
        stateChanged @0 :PlaybackStatus;
        metadataChanged @1 :MediaMetadata;
        positionChanged @2 :T.Duration;
        volumeChanged @3 :Float32;
        # Forward compatibility: a backend reporting a playback event the
        # contract never named (a DRM licence change, a transport stall
        # class, a new interpolation mode) must still be dispatchable
        # rather than arriving as an unrecognisable union member with no
        # data (TIMELESSNESS.md:98, DESIGN_PRINCIPLES "Forward
        # compatibility"). Batch B found and deferred this gap; closed
        # here so the file honours the convention every other event union
        # in the tree already follows.
        unknown @4 :T.UnknownEvent;
    }
}

# ── Player ──────────────────────────────────────────────────

struct MediaPlayer {
    id @0 :T.MediaPlayerId;
    name @1 :Text;
    identity @2 :Text;
    status @3 :PlaybackStatus;
    shuffle @4 :Bool;
    repeat @5 :RepeatMode;
    # Playback rate: 1.0 = normal, 2.0 = double speed, 0.5 = half speed.
    rate @6 :Float32;
    metadata @7 :MediaMetadata;
    # Audit-8 additions:
    syncGroup @8 :Text;
    supportedFormats @9 :List(Text);
}

enum PlaybackStatus {
    stopped @0;
    playing @1;
    paused @2;
    forward @3;
    rewind @4;
    custom @5;
}

enum RepeatMode {
    none @0;
    one @1;
    all @2;
    custom @3;
}

# ── Metadata ────────────────────────────────────────────────

struct MediaMetadata {
    title @0 :Text;
    artist @1 :Text;
    album @2 :Text;
    albumArtist @3 :Text;
    genre @4 :Text;
    comment @5 :Text;
    year @6 :UInt32;
    trackNumber @7 :UInt32;
    discNumber @8 :UInt32;
    duration @9 :T.Duration;
    artUri @10 :Text;
    # Artwork data — use buffer handle for images >1KB.
    artData @11 :T.DataHandle;
    # Audit-8 additions:
    contentHash @12 :Data;
    encrypted @13 :Bool;
    aiTags @14 :T.StringMap;
    chapters @15 :List(Chapter);
    lyrics @16 :LyricsData;
}

# ── Item ────────────────────────────────────────────────────

struct MediaItem {
    id @0 :T.MediaItemId;
    uri @1 :T.Uri;
    metadata @2 :MediaMetadata;
    # Audit-8 additions:
    contentHash @3 :Data;
    encrypted @4 :Bool;
}

# ════════════════════════════════════════════════════════════════════════
# Audit-8 additions: live-stream, content-addressed media, chapters,
# lyrics, sync-aware playback, playlist management, format negotiation,
# transcoding, recommendations, analytics, sharing, download, crossfade.
# ════════════════════════════════════════════════════════════════════════

# ── Chapter ────────────────────────────────────────────────────────────
# Chapter markers for long-form content (audiobooks, podcasts, video series).
# Enables chapter-based navigation and display.
struct Chapter {
    title @0 :Text;
    startTime @1 :T.Duration;
    endTime @2 :T.Duration;
    description @3 :Text;
}

# ── Lyrics Data ────────────────────────────────────────────────────────
# Synchronized lyrics with timestamps. Supports line-by-line,
# word-by-word, and karaoke display modes.
struct LyricsData {
    lines @0 :List(LyricLine);
    syncType @1 :SyncType;
    language @2 :Text;
}

struct LyricLine {
    text @0 :Text;
    startTime @1 :T.Duration;
    endTime @2 :T.Duration;
}

enum SyncType {
    unsynchronized @0;
    lineSync @1;
    wordSync @2;
    custom @3;
}

# ── Live Stream ────────────────────────────────────────────────────────
# Real-time broadcast content. Low-latency delivery for radio,
# live events, and streaming with viewer analytics.
struct LiveStream {
    streamUrl @0 :T.Uri;
    latency @1 :T.Duration;
    bitrate @2 :UInt64;
    viewerCount @3 :UInt64;
    streamHealth @4 :StreamHealth;
}

enum StreamHealth {
    excellent @0;
    good @1;
    fair @2;
    poor @3;
    offline @4;
    custom @5;
}

# ── Media Analytics ────────────────────────────────────────────────────
# Playback analytics for listening habits, skip rates, and completion.
# Enables content recommendation and user behavior analysis.
struct MediaAnalytics {
    mediaId @0 :T.MediaItemId;
    playCount @1 :UInt64;
    totalListenTime @2 :T.Duration;
    skipRate @3 :Float32;
    completionRate @4 :Float32;
    lastPlayed @5 :T.Timestamp;
    averageRating @6 :Float32;
}

# ════════════════════════════════════════════════════════════════════════
# Audit-9 additions: recommendation scoring, sharing preview,
# download status, crossfade configuration, live stream interaction,
# and transcoding progress.
# ════════════════════════════════════════════════════════════════════════

# ── Recommendation Score ───────────────────────────────────────────────
# Detailed recommendation with scoring and reasoning. Answers
# "why was this item recommended?" for transparency.
struct RecommendationScore {
    mediaId @0 :T.MediaItemId;
    # Recommendation score (0.0–1.0, higher = more relevant).
    score @1 :Float32;
    # Reason for recommendation (e.g., "similar to X", "trending").
    reason @2 :Text;
    # Source algorithm (e.g., "collaborative", "content-based", "popular").
    algorithm @3 :Text;
    # Confidence in this recommendation (0.0–1.0).
    confidence @4 :Float32;
}

# ── Share Preview ──────────────────────────────────────────────────────
# Preview metadata for a shared media link. Provides thumbnail,
# title, and description for link preview rendering.
struct SharePreview {
    # Share URL.
    url @0 :T.Uri;
    # Preview title.
    title @1 :Text;
    # Preview description.
    description @2 :Text;
    # Thumbnail image data.
    thumbnail @3 :T.DataHandle;
    # MIME type of the thumbnail.
    thumbnailMime @4 :Text;
    # Duration of the media (for audio/video).
    duration @5 :T.Duration;
}

# ── Download Status ────────────────────────────────────────────────────
# Status tracking for media downloads. Enables monitoring download
# progress, pausing, and resuming.
struct DownloadStatus {
    downloadId @0 :UInt64;
    mediaId @1 :T.MediaItemId;
    # Download progress (0.0–1.0).
    progress @2 :Float32;
    # Bytes downloaded so far.
    bytesDownloaded @3 :UInt64;
    # Total bytes to download.
    totalBytes @4 :UInt64;
    # Current state of the download.
    state @5 :DownloadState;
    # Download speed in bytes per second.
    speed @6 :UInt64;
    # Estimated time remaining.
    estimatedRemaining @7 :T.Duration;
}

enum DownloadState {
    pending @0;
    downloading @1;
    paused @2;
    completed @3;
    failed @4;
    cancelled @5;
    custom @6;
}

# ── Crossfade Configuration ────────────────────────────────────────────
# Detailed crossfade control. Extends the basic crossfade duration
# with curve/easing and gapless options.
struct CrossfadeConfig {
    # Crossfade duration.
    duration @0 :T.Duration;
    # Crossfade curve (linear, exponential, equal-power).
    curve @1 :CrossfadeCurve;
    # Whether to enable gapless playback when crossfade is off.
    gapless @2 :Bool;
    # Volume adjustment during crossfade (0.0–1.0).
    volumeAdjust @3 :Float32;
}

enum CrossfadeCurve {
    linear @0;
    equalPower @1;
    exponential @2;
    sCurve @3;
    custom @4;
}

# ── Live Stream Interaction ────────────────────────────────────────────
# Interactive features for live streams. Supports chat messages,
# polls, and reactions for viewer engagement.
struct LiveInteraction {
    streamUrl @0 :T.Uri;
    type @1 :LiveInteractionType;
    # Message/poll content.
    content @2 :Text;
    # Sender identity.
    senderId @3 :T.AppId;
    timestamp @4 :T.Timestamp;
}

enum LiveInteractionType {
    chatMessage @0;
    poll @1;
    pollResponse @2;
    reaction @3;
    tip @4;
    custom @5;
}

# ── Transcode Progress ─────────────────────────────────────────────────
# Progress tracking for media transcoding operations. Enables
# monitoring transcoding progress and receiving completion events.
struct TranscodeProgress {
    transcodeId @0 :UInt64;
    mediaId @1 :T.MediaItemId;
    # Transcoding progress (0.0–1.0).
    progress @2 :Float32;
    # Current state.
    state @3 :TranscodeState;
    # Output format being transcoded to.
    outputFormat @4 :Text;
    # Estimated time remaining.
    estimatedRemaining @5 :T.Duration;
}

enum TranscodeState {
    queued @0;
    processing @1;
    completed @2;
    failed @3;
    cancelled @4;
    custom @5;
}
