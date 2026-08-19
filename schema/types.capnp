@0xa1b2c3d4e5f60001;

# ── Identity ─────────────────────────────────────────────────

struct NodeId         { id @0 :UInt64; }
struct SessionId      { id @0 :UInt64; }
struct SurfaceId      { id @0 :UInt64; }
struct BufferId       { id @0 :UInt64; }
struct OutputId       { id @0 :UInt64; }
struct WindowId       { id @0 :UInt64; }
struct WorkspaceId    { id @0 :UInt64; }
struct ClientId       { id @0 :UInt64; }
struct CaptureId      { id @0 :UInt64; }
struct ImeContextId   { id @0 :UInt64; }
struct AccessNodeId   { id @0 :UInt64; }
struct DragSessionId  { id @0 :UInt64; }
struct InhibitHandle  { id @0 :UInt64; }
struct NotificationId { id @0 :UInt64; }
struct ClipboardId    { id @0 :UInt64; }
struct EventId        { id @0 :UInt64; }
struct PackageId      { id @0 :UInt64; }
struct ServiceId       { id @0 :UInt64; }
struct JobId          { id @0 :UInt64; }
struct TimerId        { id @0 :UInt64; }
struct PrintJobId     { id @0 :UInt64; }
struct ProcessId      { id @0 :UInt64; }
struct FileId         { id @0 :UInt64; }
struct SearchProviderId { id @0 :UInt64; }
struct SettingKey     { id @0 :UInt64; }
struct AppId          { id @0 :UInt64; }
struct BackupId       { id @0 :UInt64; }
struct BiometricId    { id @0 :UInt64; }
struct AuthMethodId   { id @0 :UInt64; }
struct AuthTokenId    { id @0 :UInt64; }
struct PermissionId   { id @0 :UInt64; }
struct BootStageId    { id @0 :UInt64; }
struct DeviceAddress  { id @0 :UInt64; }
struct UpgradeId      { id @0 :UInt64; }
struct ContactId      { id @0 :UInt64; }
struct GroupId        { id @0 :UInt64; }
struct ClipboardSourceId { id @0 :UInt64; }
struct SensorId          { id @0 :UInt64; }
struct SpeechVoiceId     { id @0 :UInt64; }
struct TrayIconId        { id @0 :UInt64; }
struct SocketId          { id @0 :UInt64; }
struct CertificateId     { id @0 :UInt64; }
struct AccessId          { id @0 :UInt64; }
struct AccessBackendId   { id @0 :UInt64; }
struct AccessCredentialId  { id @0 :UInt64; }
struct MfaChallengeId    { id @0 :UInt64; }
struct MfaEnrollmentId   { id @0 :UInt64; }
struct SmartCardId       { id @0 :UInt64; }
struct RuntimeInstanceId { id @0 :UInt64; }
struct FramebufferId     { id @0 :UInt64; }
struct PlaneId           { id @0 :UInt64; }
struct CrtcId            { id @0 :UInt64; }
struct AudioStreamId     { id @0 :UInt64; }
struct AudioFocusId      { id @0 :UInt64; }
struct AudioDeviceId     { id @0 :UInt64; }
struct CodecId           { id @0 :UInt64; }

# ── Versioning ───────────────────────────────────────────────

struct Version {
    major      @0 :UInt32;
    minor      @1 :UInt32;
    patch      @2 :UInt32;
    preRelease @3 :Text;
    buildMetadata @4 :Text;
    epoch @5 :UInt32;
}

# ── Geometry ─────────────────────────────────────────────────

struct Vec2  { x @0 :Float32; y @1 :Float32; }
struct Vec2i { x @0 :Int32;   y @1 :Int32;   }
struct Vec3  { x @0 :Float32; y @1 :Float32; z @2 :Float32; }
struct Vec4  { x @0 :Float32; y @1 :Float32; z @2 :Float32; w @3 :Float32; }

struct Quaternion { x @0 :Float32; y @1 :Float32; z @2 :Float32; w @3 :Float32; }

struct Rect3D {
    position @0 :Vec3;
    size     @1 :Vec2;
    rotation @2 :Quaternion;
}

struct Region    { rectangles @0 :List(Rect); }
struct Insets    { top @0 :UInt32; right @1 :UInt32; bottom @2 :UInt32; left @3 :UInt32; }
struct Size      { width @0 :UInt32; height @1 :UInt32; }
struct CornerRadius { topLeft @0 :Float32; topRight @1 :Float32; bottomRight @2 :Float32; bottomLeft @3 :Float32; }

struct Transform2D {
    m00 @0 :Float32; m01 @1 :Float32; m02 @2 :Float32;
    m10 @3 :Float32; m11 @4 :Float32; m12 @5 :Float32;
}

# ── Color ────────────────────────────────────────────────────
# The Color struct definition lives later in this file under
# "Color Space - Extended Color". The original RGBA-only definition
# was replaced by color-space-aware variant (Color with colorSpace field)
# and ExtendedColor for HDR/WCG precision.

# ── Time ─────────────────────────────────────────────────────

struct Timestamp { nanoseconds @0 :UInt64; }
struct Duration  { nanoseconds @0 :UInt64; }

# Monotonic timestamp immune to system clock adjustments (NTP, DST, manual changes).
# Use for timeouts, benchmarks, interval measurement.
struct MonotonicTimestamp { nanoseconds @0 :UInt64; }

struct FrameRate {
    numerator   @0 :UInt32;
    denominator @1 :UInt32;
}

# ── Pixel Formats ────────────────────────────────────────────

enum PixelFormat {
    argb8888      @0;
    xrgb8888      @1;
    abgr8888      @2;
    xbgr8888      @3;
    rgba8888      @4;
    rgbx8888      @5;
    rgb888        @6;
    bgr888        @7;
    argb2101010   @8;
    xrgb2101010   @9;
    abgr16161616f @10;
    yuyv          @11;
    nv12          @12;
    yuv420        @13;
    gray8         @14;
    gray16        @15;
    custom        @16;
}

# ── Maps ──────────────────────────────────────────────────────

struct StringMap {
    entries @0 :List(StringMapEntry);
}

struct StringMapEntry {
    key @0 :Text;
    value @1 :Text;
}

struct StringDataMap {
    entries @0 :List(StringDataMapEntry);
}

struct StringDataMapEntry {
    key @0 :Text;
    value @1 :Data;
}

# ── Memory Permissions ───────────────────────────────────────

enum MemoryPerms {
    read @0;
    write @1;
    execute @2;
}

# ── Modifier State ───────────────────────────────────────────

struct ModifierState {
    ctrl @0 :Bool;
    shift @1 :Bool;
    alt @2 :Bool;
    super @3 :Bool;
    capsLock @4 :Bool;
    numLock @5 :Bool;
    scrollLock @6 :Bool;
}

# ── Error Model ──────────────────────────────────────────────

struct VoidResult {
    union {
        success @0 :Void;
        error @1 :Error;
    }
}

struct BoolResult {
    union {
        ok @0 :Bool;
        error @1 :Error;
    }
}

struct Error {
    code @0 :ErrorCode;
    message @1 :Text;
    context @2 :Text;
    retryable @3 :Bool;
}

enum ErrorCode {
    notFound @0;
    permissionDenied @1;
    failed @2;
    temporary @3;
    unavailable @4;
    limitExceeded @5;
    outOfMemory @6;
    invalidArgument @7;
    timeout @8;
    cancelled @9;
    alreadyExists @10;
    notSupported @11;
    conflict @12;
    unknown @13;
    # Hardware/driver-specific codes (consolidated from error.capnp).
    hardwareFault @14;
    driverError @15;
    protocolViolation @16;
    busError @17;
    thermalThrottling @18;
    powerStateFailure @19;
}

# ── Metadata ─────────────────────────────────────────────────

struct Meta {
    key @0 :Text;
    value @1 :MetaValue;
}

struct MetaValue {
    union {
        text @0 :Text;
        integer @1 :Int64;
        real @2 :Float64;
        boolean @3 :Bool;
        bytes @4 :Data;
    }
}

# ── Filters ──────────────────────────────────────────────────

enum BoolFilter { any @0; yes @1; no @2; }

struct Pagination {
    offset @0 :UInt32;
    limit @1 :UInt32;
}

# ── Log Levels ──────────────────────────────────────────────

enum LogLevel {
    trace @0;
    debug @1;
    info @2;
    warn @3;
    error @4;
    fatal @5;
    silent @6;
    crash @7;
    security @8;
    audit @9;
    custom @10;
}

# ── Resource Usage ──────────────────────────────────────────
# The ResourceUsage struct definition lives later in this file under
# "Extended Resource Usage with Timestamp" (added with acquiredAt
# field for lifecycle/expiry tracking).

# ── Cursor Shapes ────────────────────────────────────────────
# 35 variants matching matrix-mimo completeness.
# Existing 18 ordinals (0-17) preserved. New variants at 18-34.

enum CursorShape {
    default @0;
    pointer @1;
    text @2;
    crosshair @3;
    move @4;
    resizeN @5;
    resizeS @6;
    resizeE @7;
    resizeW @8;
    resizeNE @9;
    resizeNW @10;
    resizeSE @11;
    resizeSW @12;
    wait @13;
    help @14;
    notAllowed @15;
    grab @16;
    grabbing @17;
    none @18;
    contextMenu @19;
    progress @20;
    cell @21;
    verticalText @22;
    alias @23;
    copy @24;
    noDrop @25;
    resizeEw @26;
    resizeNs @27;
    resizeNesw @28;
    resizeNwse @29;
    allScroll @30;
    zoomIn @31;
    zoomOut @32;
    colResize @33;
    rowResize @34;
}

# ── Surface Transforms ───────────────────────────────────────

enum SurfaceTransform {
    none @0;
    rotate90 @1;
    rotate180 @2;
    rotate270 @3;
    flipX @4;
    flipY @5;
    flipXY @6;
}

# ── Buffer Transform ─────────────────────────────────────────
# Matches matrix-mimo compositor.capnp BufferTransform.

enum BufferTransform {
    normal           @0;
    rotate90         @1;
    rotate180        @2;
    rotate270        @3;
    flipped          @4;
    flippedRotate90  @5;
    flippedRotate180 @6;
    flippedRotate270 @7;
}

# ── Window Layer ─────────────────────────────────────────────
# Matches matrix-mimo windowmanager.capnp WindowLayer.

enum WindowLayer {
    desktop      @0;
    below        @1;
    normal       @2;
    above        @3;
    dock         @4;
    overlay      @5;
    notification @6;
    system       @7;
}

# ── Touch Gestures ───────────────────────────────────────────

enum TouchGesture {
    none @0;
    tap @1;
    doubleTap @2;
    longPress @3;
    pinch @4;
    rotate @5;
    swipe @6;
    edgeSwipe @7;
}

struct GestureEvent {
    gesture @0 :TouchGesture;
    position @1 :Vec2i;
    scale @2 :Float32;
    rotation @3 :Float32;
    velocity @4 :Vec2;
    fingerCount @5 :UInt32;
}

# ── Data Handles ─────────────────────────────────────────────
# For payloads that may exceed 1KB. Use inline for small data,
# buffer reference for large data (images, video, file contents).

struct DataHandle {
    union {
        inline @0 :Data;       # Small payloads (<1KB) — serialized in-message
        buffer @1 :BufferId;   # Large payloads — reference to shared memory buffer
    }
}

# ── Calendar Identity ────────────────────────────────────────

struct CalendarId   { id @0 :UInt64; }
struct ReminderId   { id @0 :UInt64; }
struct AttendeeId   { id @0 :UInt64; }

# ── Camera Identity ──────────────────────────────────────────

struct CameraId     { id @0 :UInt64; }
struct RecordingId  { id @0 :UInt64; }

# ── Content Identity ──────────────────────────────────────────

struct ContentId          { id @0 :UInt64; }
struct ContentSubscriptionId { id @0 :UInt64; }

# ── Database Identity ─────────────────────────────────────────

struct DatabaseId         { id @0 :UInt64; }
struct NamespaceId        { id @0 :UInt64; }

# ── Device Identity ───────────────────────────────────────────

struct DeviceId           { id @0 :UInt64; }

# ── Extension Identity ────────────────────────────────────────

struct ExtensionId        { id @0 :UInt64; }

# ── Display Identity ──────────────────────────────────────────

struct LogicalMonitorId   { id @0 :UInt64; }
struct ColorProfileId     { id @0 :UInt64; }
struct DisplayModeId      { id @0 :UInt64; }

# ── DNS Identity ──────────────────────────────────────────────

struct DnsSubscriptionId  { id @0 :UInt64; }

# ── HAL Identity ─────────────────────────────────────────────

struct HalDeviceId       { id @0 :UInt64; }
struct DmaChannelId      { id @0 :UInt64; }
struct HookId            { id @0 :UInt64; }

# ── Input Identity ───────────────────────────────────────────

struct InputMethodId     { id @0 :UInt64; }
struct KeyboardLayoutId  { id @0 :UInt64; }
struct KeyBindingId      { id @0 :UInt64; }
struct BiometricTemplateId { id @0 :UInt64; }
struct GestureId         { id @0 :UInt64; }

# ── Intent Identity ──────────────────────────────────────────

struct IntentId          { id @0 :UInt64; }
struct ActivityId        { id @0 :UInt64; }
struct ServiceHandleId   { id @0 :UInt64; }

# ── Service Identity ─────────────────────────────────────────

struct ServiceName       { id @0 :UInt64; }
struct ManifestName      { id @0 :UInt64; }
struct SchemaId          { id @0 :UInt64; }

# ── Media Identity ──────────────────────────────────────────

struct MediaPlayerId  { id @0 :UInt64; }

# ── Module Identity ─────────────────────────────────────────

struct ModuleId        { id @0 :UInt64; }

# ── Network Identity ────────────────────────────────────────

struct NetworkInterfaceId { id @0 :UInt64; }
struct VpnProfileId      { id @0 :UInt64; }
struct VpnConnectionId   { id @0 :UInt64; }

# ── NFC Identity ────────────────────────────────────────────

struct NfcTagId       { id @0 :UInt64; }
struct NfcServiceId   { id @0 :UInt64; }

# ── Notification Identity ───────────────────────────────────

struct NotificationActionId { id @0 :UInt64; }

# ── Power Identity ──────────────────────────────────────────

struct PowerProfileId { id @0 :UInt64; }

# ── Print Identity ──────────────────────────────────────────

struct PrinterId      { id @0 :UInt64; }

# ── Process Identity ────────────────────────────────────────

struct UserId         { id @0 :UInt64; }
struct ThreadId       { id @0 :UInt64; }

# ── Queue Identity ──────────────────────────────────────────

struct QueueId        { id @0 :UInt64; }
struct QueueMessageId { id @0 :UInt64; }

# ── Physical Quantities ─────────────────────────────────────
# All physical quantities declare their unit in the wrapper struct.
# No bare floats without explicit units.

# Temperature in Kelvin. 0.0 = absolute zero. 273.15 = freezing point of water.
struct TemperatureKelvin { kelvin @0 :Float32; }

# Electric potential difference in Volts.
struct Voltage { volts @0 :Float32; }

# Electric current in Amperes.
struct Current { amperes @0 :Float32; }

# ── Signal Kind ─────────────────────────────────────────────
# Cross-platform signal types. No POSIX signal numbers.
# Used by process.capnp and signal.capnp (when implemented).

enum SignalKind {
    terminate @0;
    interrupt @1;
    kill @2;
    hangUp @3;
    userDefined1 @4;
    userDefined2 @5;
    userDefined3 @6;
    userDefined4 @7;
    custom @8;
    # Process lifecycle signals — cross-platform equivalents of POSIX
    # SIGCHLD, SIGSTOP, SIGCONT. Added in Batch 10 (Audit-4) to
    # eliminate local SignalKind duplication in kernel.capnp.
    child @9;
    stop @10;
    continue @11;
}

# ── Exit Status ─────────────────────────────────────────────
# Cross-platform process exit semantics. Replaces raw Int32 exit codes.
# Used by process.capnp, kernel.capnp, cli.capnp, init.capnp.

struct ExitStatus {
    union {
        # Process exited with this code. 0 = success, non-zero = failure.
        exited @0 :Int32;
        # Process was killed by this signal.
        signaled @1 :SignalKind;
        # Process timed out (for deadlines).
        timedOut @2 :Void;
        # Backend-specific termination without standardized meaning.
        custom @3 :Data;
    }
}

# ── Trust Level ─────────────────────────────────────────────
# Used by capability.capnp and runtime_search.capnp.

enum TrustLevel {
    # Backend-default trust.
    system @0;
    # Signed by a known platform key.
    platform @1;
    # Installed via package system.
    installer @2;
    # User installed or user space.
    user @3;
    # Lower-trust sandboxed plugin.
    untrusted @4;
}

# ── Identifier Aliases for Access + Runtime ─────────────────
# The canonical names exist above; these aliases are kept for
# readability in access.capnp and runtime_search.capnp.
# CredentialId is an alias for AccessCredentialId.

# ── Subscription Error ─────────────────────────────────────
# Standardized subscription pull response.

struct SubscriptionOk {
    ok @0 :Bool;
}

# ── Capability Handle ─────────────────────────────────────
struct CapabilityHandle { handle @0 :UInt64; }

# ══════════════════════════════════════════════════════════════
# BATCH 9 — Missing Primitives
# All types below were identified as missing during audit-2
# across multiple build cycles. They are cross-schema
# primitives that prevent raw Text/UInt64/Data being used
# as identifiers or domain values.
# ══════════════════════════════════════════════════════════════

# ── Font Identity ────────────────────────────────────────────
# Promoted from font.capnp local definition to enable cross-schema
# references (e.g., compositor referencing loaded fonts for rendering).

struct FontId { id @0 :UInt64; }

# ── File Handle Identity ─────────────────────────────────────
# files.capnp uses raw UInt64 for file handles. This typed ID
# prevents confusion with other UInt64 handles (buffers, sockets, etc.).

struct FileHandleId { id @0 :UInt64; }

# ── Tag Identity ─────────────────────────────────────────────
# content.capnp tags are List(Text). A typed TagId enables
# cross-schema tag references without string comparison.

struct TagId { id @0 :UInt64; }

# ── Subsystem Identity ──────────────────────────────────────
# klog.capnp KLogMessage.source and logging.capnp LogEntry.domain
# use bare strings. A typed SubsystemId enables cross-schema
# subsystem references (e.g., dashboard filtering by subsystem).

struct SubsystemId { id @0 :UInt64; }

# ── Mapped Region Identity ──────────────────────────────────
# hal.capnp HalService.map returns raw UInt64 as an opaque handle.
# Typed ID enables safe passing of mapped region handles between processes.

struct MappedRegionId { id @0 :UInt64; }

# ── Layer Identity ───────────────────────────────────────────
# compositor.capnp LayerInfo.id uses raw UInt64.
# Typed ID enables safe cross-schema layer references.

struct LayerId { id @0 :UInt64; }

# ── Contact Sub-Entry Identity ──────────────────────────────
# contacts.capnp EmailEntry.id, PhoneEntry.id, AddressEntry.id
# incorrectly use T.ContactId. These are sub-entity IDs within a
# contact, not contact IDs themselves. Dedicated types prevent
# accidental cross-use.

struct EmailEntryId { id @0 :UInt64; }
struct PhoneEntryId { id @0 :UInt64; }
struct AddressEntryId { id @0 :UInt64; }

# ── Sound Identity ──────────────────────────────────────────
# notification.capnp sound field is bare Text.
# Typed ID enables cross-schema sound references.

struct SoundId { id @0 :UInt64; }

# ── Telephony Identity ──────────────────────────────────────
# telephony.capnp defines CallId, ConferenceId, MessageId locally.
# Promoted to types.capnp for cross-schema references.

struct CallId { id @0 :UInt64; }
struct ConferenceId { id @0 :UInt64; }
struct TelephonyMessageId { id @0 :UInt64; }

# ── Theme Identity ──────────────────────────────────────────
# theme.capnp ThemeTokens.id is bare Text.
# Typed ID enables cross-schema theme references.

struct ThemeId { id @0 :UInt64; }

# ── Secret Identity ─────────────────────────────────────────
# secret.capnp namespace and key are bare Text.
# Typed IDs enable structured secret addressing.

struct SecretNamespaceId { id @0 :UInt64; }
struct SecretKeyId { id @0 :UInt64; }

# ── Media Item Identity ─────────────────────────────────────
# media.capnp uses T.ContentId for media items which is semantically
# wrong — ContentId is for content discovery, not playlist items.

struct MediaItemId { id @0 :UInt64; }

# ── Location Source Identity ─────────────────────────────────
# location.capnp has no typed source identifier.
# Typed ID enables cross-schema location source references.

struct LocationSourceId { id @0 :UInt64; }

# ── Language ─────────────────────────────────────────────────
# Referenced by translation.capnp (T.Language) and speech.capnp
# (via Translation.Language). This struct was missing from
# types.capnp despite being used. The Language struct enables
# cross-schema language identification without duplication.

struct Language {
    code @0 :Text;     # ISO 639-1 code (e.g., "en", "fr", "de")
    name @1 :Text;     # Human-readable name (e.g., "English", "French")
    nativeName @2 :Text;  # Name in the language itself (e.g., "English", "Français")
}

# ── Date ─────────────────────────────────────────────────────
# contacts.capnp Contact.birthday uses T.Timestamp, but birthdays
# are date-only — time-of-day is irrelevant and misleading.
# calendar.capnp also benefits from a date-only type.
# T.Timestamp implies time-of-day precision that dates don't need.

struct Date {
    year @0 :UInt32;   # 1–9999 (ISO 8601)
    month @1 :UInt8;   # 1–12
    day @2 :UInt8;     # 1–31
}

# ── Warning ──────────────────────────────────────────────────
# module.capnp LoadResult.warnings uses List(Text).
# A T.Warning struct provides structured advisory information,
# similar to T.Error but non-fatal. Enables typed warning codes
# and machine-readable advisory data.

struct Warning {
    code @0 :UInt32;   # Warning code (backend-defined, 0 = generic)
    message @1 :Text;  # Human-readable warning description
    context @2 :Text;  # Optional additional context
}

# ── URI ──────────────────────────────────────────────────────
# media.capnp openUri and module.capnp Source.url use bare Text.
# A typed URI prevents malformed resource references and enables
# scheme validation at the protocol level.

struct Uri {
    scheme @0 :Text;      # e.g., "http", "https", "file", "rtsp", "content"
    authority @1 :Text;   # host:port or authority component
    path @2 :Text;        # path component
    query @3 :Text;       # query string (without '?')
    fragment @4 :Text;    # fragment (without '#')
}

# ── File Path ────────────────────────────────────────────────
# package.capnp install path is bare Text.
# A typed FilePath distinguishes filesystem paths from URIs
# and enables backend-agnostic path handling.

struct FilePath {
    path @0 :Text;        # Platform-independent path (POSIX-style with '/')
    isAbsolute @1 :Bool;  # Whether path is absolute
}

# ── IP Address ───────────────────────────────────────────────
# dns.capnp uses Data for IPv4/IPv6 addresses.
# network.capnp Subnet.address and DnsServer.address use bare Text.
# Typed address structs prevent malformed data and enable typed
# comparison without string parsing.

struct IpAddressV4 {
    octets @0 :Data;  # Exactly 4 bytes: a.b.c.d
}

struct IpAddressV6 {
    octets @0 :Data;  # Exactly 16 bytes: full 128-bit address
}

struct IpAddress {
    union {
        v4 @0 :IpAddressV4;
        v6 @1 :IpAddressV6;
        text @2 :Text;    # Human-readable fallback (e.g., "::1", "127.0.0.1")
        custom @3 :Data;  # Backend-specific address format
    }
}

# ── Port ─────────────────────────────────────────────────────
# dns.capnp SrvRecord.port and network.capnp DnsServer.port
# are raw UInt16. A typed Port distinguishes port numbers from
# other UInt16 values.

struct Port {
    number @0 :UInt16;  # 0–65535
}

# ── Bluetooth Address ────────────────────────────────────────
# network.capnp BluetoothDevice.address is bare Text.
# A typed struct enforces the 6-byte MAC format and enables
# privacy-aware address handling (public vs random).

struct BluetoothAddress {
    address @0 :Text;  # 6 colon-separated hex octets (e.g., "AA:BB:CC:DD:EE:FF")
}

# ── MIME Type ────────────────────────────────────────────────
# speech.capnp audio encoding, telephony.capnp MmsPart.contentType,
# and other schemas use bare Text for MIME types.
# A typed struct enables structured MIME handling.

struct MimeType {
    type @0 :Text;       # e.g., "audio", "video", "image", "application"
    subtype @1 :Text;    # e.g., "pcm", "opus", "jpeg", "json"
    parameters @2 :StringMap;  # e.g., {"rate": "16000", "channels": "1"}
}

# ── Frequency ────────────────────────────────────────────────
# display.capnp refreshRate is Float32 Hz.
# A typed struct documents the unit and enables cross-schema
# frequency references (sensor sampling rates, display refresh, etc.).

struct Frequency {
    hertz @0 :Float64;  # Value in Hertz. 60.0 = 60 Hz display refresh.
}

# ── Point ──────────────────────────────────────────────────────
# Semantic distinction: Point = pixel coordinate (discrete, origin at top-left),
# Vec2 = geometric vector (continuous, origin arbitrary). Prevents accidental
# mixing of coordinate space and vector math operations.
# Point uses Int32 for pixel coordinates (sub-pixel via Float32 in Vec2).

struct Point {
    x @0 :Int32;
    y @1 :Int32;
}

# ── Point3D ────────────────────────────────────────────────────
# 3D point for 3D coordinate spaces (compositor layers, AR/VR).

struct Point3D {
    x @0 :Float32;
    y @1 :Float32;
    z @2 :Float32;
}

# ── Rect with Degenerate Variant ──────────────────────────────
# Rect with explicit degenerate state. Zero width/height rects are
# semantically distinct from "empty" rects (e.g., empty clip region
# vs zero-size widget). The degenerate flag makes this explicit.

struct Rect {
    x @0 :Int32;
    y @1 :Int32;
    width @2 :UInt32;
    height @3 :UInt32;
    degenerate @4 :Bool;  # True = empty region (distinct from 0x0 rect at a position)
}

# ── Resolution ─────────────────────────────────────────────────
# DPI / PPI / DPCM resolution with explicit unit. Replaces bare UInt32 DPI
# in print.capnp and enables cross-schema resolution references.

enum ResolutionUnit {
    dpi @0;   # Dots per inch (print)
    ppi @1;   # Pixels per inch (display)
    dpcm @2;  # Dots per centimeter
    custom @3;
}

struct Resolution {
    value @0 :Float32;
    unit @1 :ResolutionUnit;
}

# ── Color Space ────────────────────────────────────────────────
# Extended color support beyond sRGB. ColorSpace enum enables
# multi-color-space pipelines (HDR, print, wide-gamut).

enum ColorSpace {
    srgb @0;           # Standard sRGB (default)
    displayP3 @1;      # Apple Display P3
    adobeRgb @2;       # Adobe RGB
    rec2020 @3;        # ITU-R BT.2020 (HDR/WCG)
    rec2100 @4;        # ITU-R BT.2100 (HDR, includes PQ/HLG)
    dciP3 @5;          # DCI-P3 (digital cinema)
    aces @6;           # ACES (Academy Color Encoding System)
    cieXyz @7;         # CIE XYZ (device-independent)
    cieLab @8;         # CIE L*a*b* (perceptually uniform)
    cmyk @9;           # CMYK (print)
    custom @10;
}

struct Color {
    red @0 :Float32;
    green @1 :Float32;
    blue @2 :Float32;
    alpha @3 :Float32;
    colorSpace @4 :ColorSpace;  # Defaults to sRGB if absent (default = 0)
}

# ── Extended Color (for HDR/WCG) ──────────────────────────────
# Extended precision color for HDR/WCG workflows. Uses Float32
# components with explicit color space. Components may exceed 1.0
# for HDR (e.g., PQ: 0.0–10000.0 nits mapped to 0.0–1.0 via EOTF).

struct ExtendedColor {
    comp0 @0 :Float32;  # R / X / L / C
    comp1 @1 :Float32;  # G / Y / a / M
    comp2 @2 :Float32;  # B / Z / b / Y
    alpha @3 :Float32;
    colorSpace @4 :ColorSpace;
}

# ── Ordered String Map ────────────────────────────────────────
# StringMap preserves insertion order. Use when iteration order
# matters (e.g., CSS property order, HTTP header order, config).

struct OrderedStringMap {
    entries @0 :List(StringMapEntry);
}

# ── Resource Usage with Timestamp ─────────────────────────────
# Extended resource usage with acquisition timestamp for lifecycle
# tracking (expiry, sampling windows, billing windows).

struct ResourceUsage {
    cpuTime @0 :Duration;
    memoryBytes @1 :UInt64;
    peakMemoryBytes @2 :UInt64;
    ioReadBytes @3 :UInt64;
    ioWriteBytes @4 :UInt64;
    networkRxBytes @5 :UInt64;
    networkTxBytes @6 :UInt64;
    acquiredAt @7 :Timestamp;  # When this sample was captured
}

# ── Subscription Result ───────────────────────────────────────
# Standardized subscription pull result. Replaces ad-hoc
# SubscriptionOk and inline result unions across schemas.

struct SubscriptionResult {
    union {
        ok @0 :SubscriptionData;
        empty @1 :Void;       # No data available (not an error)
        ended @2 :Void;       # Stream ended (clean completion)
        error @3 :Error;
    }
}

struct SubscriptionData {
    data @0 :DataHandle;
    sequence @1 :UInt64;      # Monotonic sequence for ordering/dedup
    timestamp @2 :Timestamp;  # When data was produced
}

# ── Key Code ─────────────────────────────────────────────────
# input.capnp emulateKey takes raw UInt32 scancode/keycode.
# A typed KeyCode improves cross-platform key emulation.
# The backend translates platform-specific codes; the protocol
# defines a cross-platform semantic key space.

struct KeyCode {
    code @0 :UInt32;  # Cross-platform semantic key code
}

# ── Capability Identity ──────────────────────────────────────
# runtime_search.capnp Capability.id is bare Text.
# Typed ID enables structured capability references and prevents
# confusion with other Text identifiers.

struct CapabilityId { id @0 :UInt64; }

# ── Fence Handle Identity ───────────────────────────────────
# surface.capnp SyncFence.handle is raw UInt64.
# Typed ID prevents confusion with other UInt64 handles.

struct FenceHandle { id @0 :UInt64; }

# ── MMS Part Identity ───────────────────────────────────────
# telephony.capnp MmsPart.id is raw UInt64.
# Typed ID prevents confusion with other UInt64 message handles.

struct MmsPartId { id @0 :UInt64; }

# ── Task Group Identity ─────────────────────────────────────
# task_scheduler.capnp TaskFilter.taskGroup and ScheduledTask.taskGroup
# are bare Text. Typed ID enables structured task group references.

struct TaskGroupId { id @0 :UInt64; }

# ══════════════════════════════════════════════════════════════
# BATCH 11 — Cross-Schema Identity Promotions
# All types below were identified as locally-defined schemas
# in audit-4 that should be promoted to types.capnp for
# cross-schema references. Promoting prevents type duplication
# and enables safe cross-schema entity identification.
# ══════════════════════════════════════════════════════════════

# ── Seat Identity ────────────────────────────────────────────
# input.capnp BindingScope.seatId is bare Text.
# Typed ID enables cross-schema seat references (e.g., session.capnp
# seat management, compositor.capnp seat assignment).
# Priority: P3 (cross-schema reference, not yet critical).

struct SeatId { id @0 :UInt64; }

# ── Task Name Identity ──────────────────────────────────────
# kernel.capnp TaskFilter.name is bare Text.
# Typed ID enables cross-schema task name references (e.g., task_scheduler.capnp,
# service.capnp task identification). Tasks are also referenced by T.ProcessId,
# but names provide human-readable cross-schema identification.

struct TaskName { id @0 :UInt64; }

# ── Component Name Identity ─────────────────────────────────
# intent.capnp ComponentInfo.name and Intent.component are bare Text.
# Typed ID enables cross-schema component references (e.g., app.capnp
# component activation, accessibility.capnp component identification).

struct ComponentName { id @0 :UInt64; }

# ── Tunnel Identity ─────────────────────────────────────────
# tunnel.capnp defines local SchemaId and TunnelId structs.
# Promoted to types.capnp for cross-schema tunnel references
# (e.g., network.capnp tunnel service, discovery.capnp tunnel endpoints).

struct TunnelId { id @0 :UInt64; }

# ── Alarm Identity ──────────────────────────────────────────
# time.capnp defines local AlarmId struct.
# Promoted to types.capnp for cross-schema alarm references
# (e.g., notification.capnp alarm notifications, calendar.capnp
# alarm-linked events).

struct AlarmId { id @0 :UInt64; }

# ── Task Identity ───────────────────────────────────────────
# task_scheduler.capnp defines local TaskId struct.
# Promoted to types.capnp for cross-schema task references
# (e.g., init.capnp task scheduling, service.capnp background tasks).

struct TaskId { id @0 :UInt64; }

# ── Search Action Identity ──────────────────────────────────
# system_search.capnp SearchAction.id uses T.EventId which is
# semantically incorrect — action IDs are not events.
# Typed ID provides accurate semantic typing for search actions
# (e.g., shell.capnp action invocation, app.capnp action handling).

struct ActionId { id @0 :UInt64; }

# ══════════════════════════════════════════════════════════════
# BATCH 13 — AUDIT-7 ZERO-COST PRIMITIVES
# All types below were identified during audit-6 review or surfaced
# by new schemas added in Batch 13 (archive, crypto, diagnostics,
# endpoint, mount, sandbox, storage, timezone, vcard). They complete
# the foundation so that all schemas can speak the contract without
# local type duplication.
# ══════════════════════════════════════════════════════════════

# ── Cryptographic Key Identity ────────────────────────────────
# Cross-schema crypto key reference. key_management.capnp defined
# a local `KeyId` struct; crypto.capnp, signature.capnp, and
# backup.capnp use bare `Text` or `Data` for `keyId` fields
# (audit-6 flagged this as a cross-schema gap). Promoted to
# T.KeyId so that signing keys, encryption keys, backups, and
# crypto operations all share the same typed identifier.
#
# Cross-schema impact:
#   - key_management.capnp: KeyId (replace local definition)
#   - crypto.capnp: GenerateKeyPairRequest.keyId, GenerateKeyPairResult.keyId
#   - signature.capnp: Signature.keyId, SignRequest.keyId
#   - backup.capnp: EncryptionInfo.keyId

struct KeyId { id @0 :UInt64; }

# ── Cryptographic Key Fingerprint ────────────────────────────
# A fingerprint is the public hash of a key used for
# out-of-band identification (e.g., PGP-style key lookup by
# fingerprint, SSH known_hosts). signature.capnp stores
# `keyId :Data` which is the fingerprint but with no
# declaring algorithm — backend must guess. T.KeyFingerprint
# pairs the bytes with the algorithm explicitly so the
# fingerprint is self-describing and verifiable.
#
# Common uses:
#   - SSH known_hosts (SHA-1 fingerprint of server key)
#   - X.509 issuer/issuerKeyId (SHA-1/SHA-256 of pubkey DER)
#   - PGP key lookup by 32-byte SHA-256 fingerprint
#   - TUF root-of-trust keyid (typically SHA-256 hex)
#
# Cross-schema impact:
#   - signature.capnp: Signature.keyId, Certificate.issuerKeyId
#   - key_management.capnp: cross-reference by fingerprint

struct KeyFingerprint {
    # Hash algorithm that produced this fingerprint.
    # 0 = unspecified (use keyId length as heuristic; legacy)
    algorithm @0 :UInt16;
    # Raw fingerprint bytes (typical: 20 bytes SHA-1, 32 bytes SHA-256).
    bytes @1 :Data;
}

# ── Endpoint Identity ─────────────────────────────────────────
# Cross-schema endpoint reference. endpoint.capnp (new in Batch 13)
# defines a local `EndpointId` struct used by EndpointAddress.
# discovery.capnp uses `List(Text)` for endpoint strings in
# ServiceDescriptor (audit-6 noted this as gap). Promoted to
# T.EndpointId so discovery, network, and tunnel carry the same
# identifier when referring to an endpoint handle (vs the inline
# union value).
#
# Cross-schema impact:
#   - endpoint.capnp: EndpointId (replace local definition)
#   - discovery.capnp: endpoints could carry T.EndpointId handles
#     alongside the typed EndpointAddress union
#   - network.capnp: connection endpoint references
#   - tunnel.capnp: tunnel endpoint handles

struct EndpointId { id @0 :UInt64; }

# ── Mount Identity ────────────────────────────────────────────
# Promoted from mount.capnp (new in Batch 13). A mount point is
# referenced by files.capnp (getDiskUsage), storage.capnp (block
# devices), and filesystem.capnp (mount options). Typed ID
# prevents accidental string-comparison between mount points and
# arbitrary file paths.
#
# Cross-schema impact:
#   - mount.capnp: MountId (replace local definition)
#   - files.capnp: getDiskUsage mount references
#   - storage.capnp: BlockDevice.mountPoint references

struct MountId { id @0 :UInt64; }

# ── Filesystem Identity ───────────────────────────────────────
# Companion to T.MountId. Filesystem instances (the runtime
# mount state of a filesystem, not the on-disk label) are
# referenced by mount.capnp and storage.capnp. Typed ID enables
# safe filesystem references (e.g., "this snapshot belongs to
# filesystem X" in backup workflows).
#
# Cross-schema impact:
#   - mount.capnp: FilesystemId (replace local definition)
#   - storage.capnp: StoragePool.filesystem references
#   - backup.capnp: snapshot-by-filesystem queries

struct FilesystemId { id @0 :UInt64; }

# ── Sandbox Identity ──────────────────────────────────────────
# Promoted from sandbox.capnp (new in Batch 13). Sandboxes are
# referenced by process.capnp (sandboxed execution), init.capnp
# (service isolation), and capability.capnp (sandbox-scoped
# capability grants). Typed ID prevents confusion with
# ProcessId (a sandbox is not a process).
#
# Cross-schema impact:
#   - sandbox.capnp: SandboxId (replace local definition)
#   - process.capnp: spawn options sandbox handle
#   - capability.capnp: sandbox-scoped grants

struct SandboxId { id @0 :UInt64; }

# ── Storage Pool Identity ─────────────────────────────────────
# Promoted from storage.capnp (new in Batch 13). Storage pools
# (LVM volume groups, ZFS pools, btrfs pools, RAID arrays) are
# referenced by storage.capnp itself and by filesystem.capnp
# (pool-backed mount sources).
#
# Cross-schema impact:
#   - storage.capnp: StoragePoolId (replace local definition)
#   - filesystem.capnp: mount options referencing storage pool
#   - backup.capnp: backup destination pool handle

struct StoragePoolId { id @0 :UInt64; }

# ── Volume Identity ───────────────────────────────────────────
# Promoted from storage.capnp (new in Batch 13). A volume is a
# logical storage unit (LVM logical volume, ZFS dataset, btrfs
# subvolume). Referenced by storage.capnp, mount.capnp, and
# backup.capnp (volume-level backups vs file-level backups).
#
# Cross-schema impact:
#   - storage.capnp: VolumeId (replace local definition)
#   - mount.capnp: source/destination volume references
#   - backup.capnp: volume-level backup operations

struct VolumeId { id @0 :UInt64; }

# ── Snapshot Identity ─────────────────────────────────────────
# Promoted from storage.capnp (new in Batch 13). Storage
# snapshots (ZFS, btrfs, LVM thin) are referenced by
# storage.capnp, backup.capnp (PIT backups), and
# filesystem.capnp (snapshot-aware operations).
#
# Cross-schema impact:
#   - storage.capnp: SnapshotId (replace local definition)
#   - backup.capnp: snapshot-based backup references
#   - filesystem.capnp: snapshot-aware mount operations

struct SnapshotId { id @0 :UInt64; }

# ── Hash Output ───────────────────────────────────────────────
# A typed wrapper for cryptographic hash output. Multiple
# schemas (crypto.capnp HashResult.hash, signature.capnp
# SignedContents.payloadHash) return Data for hash bytes.
# T.HashOutput adds semantic clarity and a consistent field
# for "did this hash from this algorithm" pairs.
#
# This is a Send-side primitive; receive-side consumers can
# keep using bare Data for backwards compatibility.

struct HashOutput {
    algorithm @0 :UInt16;  # HashAlgorithm ordinal value (from signature.capnp/crypto.capnp local enums)
    bytes @1 :Data;        # Raw hash bytes (length depends on algorithm)
}

# ── Byte Range ────────────────────────────────────────────────
# Generic byte range for sub-buffer/payload operations. Used
# wherever a method needs to reference part of a larger buffer
# (e.g., partial reads, partial HMACs, packet slicing in
# network operations). Zero-cost: just an offset+length pair.
#
# Cross-schema impact:
#   - files.capnp: partial file read parameters
#   - network.capnp: packet payload ranges
#   - crypto.capnp: constant-time copy region hints

struct ByteRange {
    offset @0 :UInt64;
    length @1 :UInt64;
}

# ── Frame Timing (Animation Pipeline Primitive) ───────────────
# A single frame timing descriptor used by animation/UI
# pipelines. windowmanager.capnp (Audit-6) noted animation
# timing fields inline; compositor.capnp carries frame-related
# primitives. This struct centralizes the concept so that any
# animation/UI surface (windowmanager, compositor, shell preview
# animations) can speak the same vocabulary.
#
# Why now: Audit-7 mandates feature-richness for windowmanager
# (animation pipelines, gesture timing, AR/VR frame timing).
# T.FrameTiming is the shared primitive for all of them.

struct FrameTiming {
    # Target frame duration (e.g., 16.67ms for 60Hz, 11.11ms for 90Hz).
    targetInterval @0 :Duration;
    # Predicted next frame presentation time (when render will hit screen).
    predictedPresentation @1 :Timestamp;
    # Frame interval jitter tolerance — frames outside this range drop.
    jitterTolerance @2 :Duration;
    # Frame rate numerator/denominator for non-integer rates (e.g., 23.976).
    rate @3 :FrameRate;
}

# ── Animation Spec (Primitive for Animation Pipelines) ───────
# An animation specification shared across windowmanager, shell,
# compositor, and theme. Animation specs are part of UX contracts:
# they describe duration, easing, and target value semantics.
# Before this primitive, animation timing lived inline in
# individual schemas (windowmanager animation events, shell
# completion animations). Centralizing enables cross-schema
# animation playback (e.g., shell uses windowmanager's animation
# pipeline for modal presentation).
#
# Cross-schema impact:
#   - windowmanager.capnp: animation events reference T.Animation
#   - shell.capnp: completion animations
#   - compositor.capnp: surface transition animations
#   - theme.capnp: theme-driven transition durations

enum AnimationEasing {
    linear @0;
    easeIn @1;
    easeOut @2;
    easeInOut @3;
    cubicIn @4;
    cubicOut @5;
    cubicInOut @6;
    bezier @7;       # Custom cubic-bezier control points
    spring @8;       # Physics-based spring
    steps @9;        # Stepped / discrete
    custom @10;
}

struct CubicBezier {
    p1x @0 :Float32;
    p1y @1 :Float32;
    p2x @2 :Float32;
    p2y @3 :Float32;
}

struct SpringSpec {
    # Damping ratio (< 1 underdamped, = 1 critical, > 1 overdamped).
    dampingRatio @0 :Float32;
    # Natural frequency in radians per second.
    frequency @1 :Float32;
    # Initial displacement from equilibrium.
    initialDisplacement @2 :Float32;
    # Initial velocity.
    initialVelocity @3 :Float32;
}

struct AnimationSpec {
    # Total animation duration.
    duration @0 :Duration;
    # Easing curve.
    easing @1 :AnimationEasing;
    union {
        # Custom cubic-bezier control points (when easing = bezier).
        bezier @2 :CubicBezier;
        # Spring parameters (when easing = spring).
        spring @3 :SpringSpec;
        # Stepped animation interval (when easing = steps).
        stepInterval @4 :UInt32;
        # Backend-specific parameters.
        custom @5 :StringMap;
    }
    # Number of times to repeat (0 = once, UInt32 max = forever).
    repeatCount @6 :UInt32;
    # Whether to reverse on alternate iterations.
    autoreverse @7 :Bool;
    # Total delay before animation begins.
    delay @8 :Duration;
}

# ── Display Configuration (Spatial/AR/VR Pipeline Primitive) ──
# Centralized display configuration for spatial, AR, and VR
# scenarios. windowmanager (Audit-7 special attention) requires
# AR/VR primitives on equal footing with desktop primitives.
# T.DisplayConfiguration captures stereoscopic and spatial
# metadata that single-display configs do not.
#
# Cross-schema impact:
#   - windowmanager.capnp: AR/VR/surface configurations
#   - compositor.capnp: presentation mode descriptors
#   - display.capnp: 3D-aware display descriptors
#   - input.capnp: gaze/eye-tracking mapping

enum DisplayStereoscopicMode {
    mono @0;                 # Single-eye (2D)
    stereoSideBySide @1;     # Left/right halves
    stereoTopBottom @2;      # Top/bottom halves
    stereoAnaglyph @3;       # Red/cyan or similar
    mvhevc @4;               # MV-HEVC video stream
    custom @5;
}

enum DisplayRefreshMode {
    fixed @0;                # Fixed refresh (60Hz, 90Hz)
    variable @1;             # VRR / adaptive sync
    custom @2;
}

struct DisplayConfiguration {
    # Display name (user-readable).
    name @0 :Text;
    # Physical dimensions (mm).
    physicalWidthMm @1 :Float32;
    physicalHeightMm @2 :Float32;
    # Refresh rate.
    refreshRate @3 :Frequency;
    refreshMode @4 :DisplayRefreshMode;
    # Field of view (degrees) for stereoscopic displays.
    fovHorizontal @5 :Float32;
    fovVertical @6 :Float32;
    # Distance between user eyes (mm) for IPD.
    interpupillaryDistanceMm @7 :Float32;
    # Stereoscopic 3D mode.
    stereoscopic @8 :DisplayStereoscopicMode;
    # Preferred color space (HDR caps, wide gamut).
    preferredColorSpace @9 :ColorSpace;
    # Default frame timing.
    frameTiming @10 :FrameTiming;
}

# ══════════════════════════════════════════════════════════════
# BATCH 14 — UNIVERSAL CROSS-DOMAIN PRIMITIVES
# All types below were identified as missing during audit-7 review
# across all 90 schemas. They are cross-domain primitives that
# prevent bare Text/Data/UInt64 being used for structured values.
# ══════════════════════════════════════════════════════════════

# ── Monetary Primitives ─────────────────────────────────────
# Financial apps, e-commerce, billing, and payment schemas
# currently use bare Text or UInt64 for monetary values.
# FiatAmount provides typed monetary representation with
# currency code and precision metadata.

enum Currency {
    usd @0;
    eur @1;
    gbp @2;
    jpy @3;
    cny @4;
    krw @5;
    inr @6;
    brl @7;
    rub @8;
    btc @9;
    eth @10;
    custom @11;
}

struct FiatAmount {
    # Amount in the smallest currency unit (cents, pence, etc.)
    # to avoid floating-point precision issues.
    amount @0 :UInt64;
    # Currency code (see Currency enum above).
    currency @1 :Currency;
    # Number of decimal places in amount (e.g., 2 for USD cents).
    decimalPlaces @2 :UInt8;
    # Optional exchange rate for multi-currency arithmetic.
    exchangeRate @3 :Float64;
    exchangeRateCurrency @4 :Currency;
    exchangeRateTimestamp @5 :Timestamp;
}

# ── Global Identifiers ──────────────────────────────────────
# UUID (RFC 4122) and ULID for globally unique identifiers.
# Many schemas use bare Text for cross-system IDs that would
# benefit from structured representation.

struct Uuid {
    timeLow @0 :UInt32;
    timeMid @1 :UInt16;
    timeHiAndVersion @2 :UInt16;
    clockSeqAndNode @3 :Data;
}

struct Ulid {
    # 48-bit timestamp: milliseconds since Unix epoch.
    # Fits in UInt64; only the lower 48 bits are used.
    timestamp @0 :UInt64;
    # 80-bit (10 bytes) cryptographically secure randomness.
    # Stored as Data because no UInt80 type exists in Cap'n Proto.
    randomness @1 :Data;
}

# ── Communication Identifiers ───────────────────────────────
# Email addresses and phone numbers used as bare Text across
# contacts, auth, notification, and telephony schemas.

struct EmailAddress {
    local @0 :Text;    # Part before @
    domain @1 :Text;   # Part after @
    raw @2 :Text;      # Full email address (for display/legacy)
}

struct PhoneNumber {
    countryCode @0 :UInt16;
    nationalNumber @1 :Text;
    raw @2 :Text;       # E.164 format (e.g., "+12025551234")
}

# ── Network Primitives ──────────────────────────────────────
# IP ranges for firewall and network rules. Used by network.capnp
# and dns.capnp for CIDR notation.

struct Ipv4Range {
    start @0 :IpAddressV4;
    end @1 :IpAddressV4;
}

struct Ipv6Range {
    start @0 :IpAddressV6;
    end @1 :IpAddressV6;
}

# ── Geographic Primitives ───────────────────────────────────
# Latitude/longitude used as bare Float32 pairs in location
# schemas. GeoCoordinate provides structured geo representation.

struct GeoCoordinate {
    latitude @0 :Float64;
    longitude @1 :Float64;
    altitude @2 :Float32;       # meters above sea level
    accuracyMeters @3 :Float32;
    source @4! :union {
        gps @5 :Void;
        network @6 :Void;
        user @7 :Void;
        custom @8 :Data;
    }
}

# ── File Primitives ─────────────────────────────────────────
# File extensions used as bare Text in files, content, media.
# FileExtension provides structured file type identification.

struct FileExtension {
    extension @0 :Text;          # e.g., ".pdf", ".jpg"
    mimeType @1 :MimeType;       # Associated MIME type
    isExecutable @2 :Bool;
}

# ── Encoding Primitives ─────────────────────────────────────
# Encoded data used as bare Text in crypto, signature, archive.
# Base64 and HexString provide structured encoding.

struct Base64 {
    data @0 :Text;       # Base64-encoded string
    padding @1 :Bool;    # Whether padding characters present
}

struct HexString {
    data @0 :Text;       # Hex-encoded string (0-9, a-f)
}

# ── Regex ───────────────────────────────────────────────────
# Patterns used as bare Text in search, filter, validation.
# Structured regex for type-safe pattern matching.

struct Regex {
    pattern @0 :Text;    # Regular expression pattern
    flags @1 :Text;      # Optional flags (e.g., "i", "m", "s")
}

# ── Numeric Primitives ──────────────────────────────────────
# BigInteger for arbitrary-precision integers. Crypto operations
# and big-number math need precision beyond 64-bit range.

struct BigInteger {
    bytes @0 :Data;      # Big-endian two's complement
    sign @1 :Bool;       # True = negative
}

# ── Ordered Map ─────────────────────────────────────────────
# Generic ordered map with typed keys. OrderedStringMap exists
# but no generic ordered map with arbitrary key types.

struct OrderedMapEntry {
    key @0 :Text;
    value @1 :MetaValue;
}

struct OrderedMap {
    entries @0 :List(OrderedMapEntry);
}

# ── Subnet Identity ─────────────────────────────────────────
# network.capnp uses bare Text for subnet references.
# Typed ID enables cross-schema subnet references.

struct SubnetId { id @0 :UInt64; }

# ── Policy Identity ─────────────────────────────────────────
# auth.capnp, capability.capnp, and device.capnp reference
# policies as bare Text. Typed ID for cross-schema policy refs.

struct PolicyId { id @0 :UInt64; }

# ── Firmware Identity ───────────────────────────────────────
# boot.capnp and device.capnp reference firmware as bare Text.
# Typed ID for cross-schema firmware references.

struct FirmwareId { id @0 :UInt64; }

# ── Channel Identity ────────────────────────────────────────
# notification.capnp channels are bare Text. Typed ID enables
# cross-schema notification channel references.

struct ChannelId { id @0 :UInt64; }

# ── Rule Identity ───────────────────────────────────────────
# Contacts, calendar, and other schemas define rules as bare
# Text. Typed ID enables cross-schema rule references.

struct RuleId { id @0 :UInt64; }

# ── Template Identity ───────────────────────────────────────
# capability.capnp and auth.capnp reference templates as bare
# Text. Typed ID for cross-schema template references.

struct TemplateId { id @0 :UInt64; }

# ── Scope Identity (Audit-9 / Batch 2) ───────────────────────
# auth.capnp AuthRequest.scopes, PermissionGrant / AuthToken.scopes
# are List(Text). Typed ID enables structured scope identifiers
# and prevents accidental cross-system scope comparison.

struct ScopeId { id @0 :UInt64; }

# ── Time Range ────────────────────────────────────────────────
# Used by notification, diagnostics, and timezone schemas.
struct TimeRange {
    start @0 :UInt64;  # Unix timestamp in milliseconds
    end @1 :UInt64;    # Unix timestamp in milliseconds
}

# ── Device Group Identity ──────────────────────────────────────
# Used by update.capnp for device group management.
struct DeviceGroupId { id @0 :UInt64; }

# ── TLS Version ───────────────────────────────────────────────
# Used by socket.capnp for TLS session information.
enum TlsVersion {
    ssl30 @0;
    tls10 @1;
    tls11 @2;
    tls12 @3;
    tls13 @4;
}

# ── Search Bookmark Identity ────────────────────────────────────
# Used by system_search.capnp for bookmark references.
struct SearchBookmarkId { id @0 :UInt64; }

# ═══════════════════════════════════════════════════════════════════════
# Driver Framework Foundation (v0.0.2 additions)
#
# These are the runtime contract types for drivers that exist as
# smart-protocol capabilities. They are agnostic to whether the driver
# is in-kernel, in-process, sandboxed, or remote. Implementations
# choose how to expose them.
# ═══════════════════════════════════════════════════════════════════════

# ── SMP / Multi-core ──────────────────────────────────────────
# Used by kernel.capnp and device.capnp to describe compute topology.
# Drivers and schedulers consume these; consumers do not otherwise
# depend on topology.

struct CpuId {
    id @0 :UInt32;
}

struct NumaDomain {
    domainId @0 :UInt32;
    memoryBytes @1 :UInt64;
    cpus @2 :List(CpuId);
}

struct SmpTopology {
    totalCpus @0 :UInt32;
    onlineCpus @1 :UInt32;
    domains @2 :List(NumaDomain);
}

# ── Driver Identity ───────────────────────────────────────────
# Typed driver identifiers. Capability references to drivers
# reuse the existing capability.capnp authority model; these
# IDs are how the driver framework DTRs drivers (separate concern).

struct DriverId {
    id @0 :UInt64;
}

# Class of driver. Per-class providers (DisplayProvider, AudioProvider,
# NicProvider, BlockProvider, UsbHostProvider, FsProvider) extend these
# with class-specific affordances.
enum DriverClass {
    display     @0;
    audio       @1;
    network     @2;
    block       @3;
    usb         @4;
    filesystem  @5;
    input       @6;
    sensor      @7;
    power       @8;
    thermal     @9;
    crypto      @10;
    accelerator @11;
    generic     @12;
    # New driver classes land in future schema versions.
    custom      @13;
}

# Lifecycle state. probe->bind->start is the happy path. The
# `crashed` and `restarting` states enable driver recovery without
# OS restart.
enum DriverState {
    unknown     @0;
    probing     @1;
    probed      @2;
    binding     @3;
    bound       @4;
    starting    @5;
    running     @6;
    pausing     @7;
    paused      @8;
    stopping    @9;
    stopped     @10;
    unbinding   @11;
    crashed     @12;
    restarting  @13;
    # Terminal failure — driver cannot recover on its own.
    failed      @14;
    custom      @15;
}

# Health snapshot. Drivers emit these periodically; recoverers
# use them to decide restart policy.
struct DriverHealth {
    state @0 :DriverState;
    uptimeMs @1 :UInt64;
    lastErrorMessage @2 :Text;
    lastErrorAt @3 :UInt64;
    restartCount @4 :UInt32;
    # Free-form metrics (counters, queues, etc.) — implementation-defined.
    metrics @5 :List(DriverMetric);
}

struct DriverMetric {
    name @0 :Text;
    # Tag selects the value union — int, float, or text.
    union {
        intValue @1 :Int64;
        floatValue @2 :Float64;
        textValue @3 :Text;
    }
}

# ── Bus & DMA Foundation ─────────────────────────────────────
# Capability-capable bus addressing. The contract is a tagged bus
# address; implementations decide how to walk the bus topology.

enum BusType {
    unknown    @0;
    pci        @1;
    pcie       @2;
    usb        @3;
    i2c        @4;
    spi        @5;
    i3c        @6;
    uart       @7;
    can        @8;
    platform   @9;
    acpi       @10;
    dtb        @11;
    mmio       @12;
    # Backend-defined bus not modeled above.
    custom     @13;
}

struct BusAddress {
    busType @0 :BusType;
    # Domain, bus, device, function for PCIe; addr for I2C; etc.
    address @1 :UInt64;
    # Backend decides sub-addressing beyond address (function, lane, ...).
    subAddress @2 :UInt64;
    # Bus-specific slot/port (e.g., USB port, PCI slot).
    port @3 :UInt32;
}

struct DmaHandle {
    # Implementation-defined identifier. Cannot be used across address
    # spaces — each side maps DMA handles independently.
    id @0 :UInt64;
    # Physical address visible to the device.
    physicalAddress @1 :UInt64;
    # Requested direction (the implementation may round-trip).
    direction @2 :UInt8;  # 0=to-device, 1=from-device, 2=bidirectional
}

# ── IRQ ───────────────────────────────────────────────────────
# Cookies are the kernel-issued opaque tokens drivers use to
# reference their IRQ registration across calls.

struct IrqCookie {
    id @0 :UInt64;
}

# ── Audio Foundation ─────────────────────────────────────────
struct AudioSampleFormat {
    union {
        pcm @0 :PcmFormat;
        compressed @1 :Text;
        # Backend-defined encoding (e.g. opus ID).
        custom @2 :Void;
    }
}

struct PcmFormat {
    sampleRateHz @0 :UInt32;
    channels @1 :UInt16;
    bitsPerSample @2 :UInt16;
    isFloat @3 :Bool;
    isBigEndian @4 :Bool;
    # Use T.PixelFormat-equivalent flag: signed vs unsigned sample.
    isUnsigned @5 :Bool;
}

# ── Driver Registry Result Types ─────────────────────────────
# Used by DriverRegistry.register and friends.

struct DriverRegistration {
    driverId @0 :DriverId;
    # Stable handle for the registered capability.
    handle @1 :UInt64;
    # Server-issued timestamp.
    registeredAt @2 :UInt64;
}

struct DriverBinding {
    driverId @0 :DriverId;
    deviceId @1 :DeviceId;
    # 0 = new binding, anything else = existing.
    bindingId @2 :UInt64;
    boundAt @3 :UInt64;
}

# ══════════════════════════════════════════════════════════════
# CYBERSPACE PROTOCOL — Foundation Types
# Added for timeless, platform-agnostic service lifecycle.
# ══════════════════════════════════════════════════════════════

# Resource quota for a service. Replaces Linux cgroups.
struct Quota {
    memoryBytes @0 :UInt64;
    cpuPercent @1 :Float32;
    ioReadBytesPerSec @2 :UInt64;
    ioWriteBytesPerSec @3 :UInt64;
    pids @4 :UInt32;
    wallClockBudget @5 :Duration;
}

# Where a process is isolated. Replaces namespace/cgroup configs.
enum TierClass {
    kernel @0;
    platform @1;
    system @2;
    application @3;
    sandbox @4;
    custom @5;
}

struct IsolatedScope {
    tier @0 :TierClass;
    scopeId @1 :UInt64;
}

enum BinaryFormat {
    elf @0;
    pe @1;
    wasm @2;
    wasiSnapshot @3;
    fdtWrappedElf @4;
    custom @5;
}

# A userland binary descriptor. Init iterates these.
struct UserlandImage {
    name @0 :Text;
    format @1 :BinaryFormat;
    moduleIndex @2 :UInt32;
    baseVaddr @3 :UInt64;
    entryOffset @4 :UInt64;
    sizeBytes @5 :UInt64;
    hash @6 :Data;
    manifest @7 :Data;
    signature @8 :Data;
    channelIndex @9 :UInt32;
    isolation @10 :IsolatedScope;
}

# Abstract CPU entry state. Kernel writes once, switches, jumps.
struct EntryContext {
    rsp @0 :UInt64;
    rip @1 :UInt64;
    pageTableRoot @2 :UInt64;
    bootstrapPointer @3 :UInt64;
    argPointer @4 :UInt64;
    envPointer @5 :UInt64;
    auxvPointer @6 :UInt64;
}

# Unified outcome across every interface. Replaces ad-hoc VoidResult one-offs.
struct StateOutcome {
    union {
        success @0 :Void;
        error @1 :Error;
    }
}

# ═══════════════════════════════════════════════════════════════════════
# BATCH 15 — Audit-5 Typed Hardware Abstraction Primitives
# Backend-agnostic, platform-agnostic, device-agnostic, language-agnostic.
# ═══════════════════════════════════════════════════════════════════════

# ── Address Space Mode ────────────────────────────────────────
# Paging mode for virtual address spaces. Used by address_space.capnp
# and kernel.capnp for page table management.

enum AddressSpaceMode {
    identity @0;
    shallow @1;
    deep @2;
    auto @3;
}

# ── Page Flags ────────────────────────────────────────────────
# Per-page attributes for virtual memory mappings. Arch-agnostic
# core flags. Architecture-specific bits go in archSpecific.

struct PageFlags {
    readable @0 :Bool;
    writable @1 :Bool;
    executable @2 :Bool;
    userAccessible @3 :Bool;
    cached @4 :Bool;
    writeThrough @5 :Bool;
    global @6 :Bool;
    archSpecific @7 :Data;
}

# ── Failure Report ────────────────────────────────────────────
# Structured failure information for device/driver crash reporting.
# Used by respawn.capnp for typed failure classification.

struct FailureReport {
    timestamp   @0 :Timestamp;
    reason      @1 :FailureReason;
    severity    @2 :FailureSeverity;
    context     @3 :Text;
    diagnosticData @4 :Text;
    suggestedAction @5 :RecoveryAction;
    lastKnownGoodState @6 :Text;
}

# ── Interrupt Mode ────────────────────────────────────────────
# Delivery mechanism for device interrupts. Used by interrupt.capnp
# and hal.capnp for interrupt resource management.

enum InterruptMode {
    ioapic @0;     # x86 I/O APIC pin-based
    msi @1;        # Message Signaled Interrupts
    msix @2;       # MSI with per-vector masking
    legacy @3;     # ISA PIC-compatible
    custom @4;     # Backend-defined
}

# ═══════════════════════════════════════════════════════════════════════
# BATCH 16 — Consolidated Device/Interrupt/Respawn/Lifecycle Primitives
# (Schema consolidation Step 1 — audit-005)
#
# Content formerly split across error.capnp, respawn.capnp,
# interrupt.capnp, address_space.capnp and device_descriptor.capnp has
# been merged here so `types.capnp` is the one source of truth. Existing
# canonical types (Error, ErrorCode, AddressSpaceMode, PageFlags,
# InterruptMode, BusAddress, BusType, DmaHandle, FailureReport) are
# reused; only the missing pieces are added below.
# ═══════════════════════════════════════════════════════════════════════

# ── Error Severity & Recovery (from error.capnp) ────────────────────

enum ErrorSeverity {
    info @0;       # Informational; no action required.
    warning @1;    # Unexpected but operation continues.
    error @2;      # Operation failed; may be retryable.
    critical @3;   # Immediate attention needed.
    fatal @4;      # Cannot continue; shutdown/panic required.
}

enum RecoveryAction {
    retry @0;
    retryWithBackoff @1;
    resetDevice @2;
    resetBus @3;
    switchToFallback @4;
    requireManual @5;
    escalate @6;
    shutdown @7;
}

# Richer error model used where severity + recovery guidance is needed.
# The base T.Error remains the canonical IPC error type.
struct TypedError {
    code @0 :ErrorCode;
    message @1 :Text;
    context @2 :Text;
    severity @3 :ErrorSeverity;
    suggestedAction @4 :RecoveryAction;
    timestamp @5 :Timestamp;
    diagnosticData @6 :Data;
}

# ── Deadline Handle (from setDeadline lifecycle primitive) ────────────

struct DeadlineHandle {
    id @0 :UInt64;
}

# ── Respawn / Restart Policy (from respawn.capnp) ─────────────────────

# The one canonical restart policy used by init, HAL and the kernel.
enum RestartPolicy {
    always @0;
    onFailure @1;
    never @2;
}

struct RestartEntry {
    name @0 :Text;
    path @1 :Text;
    restartPolicy @2 :RestartPolicy;
    maxAttempts @3 :UInt32;
    fallback @4 :Text;
    kernelManaged @5 :Bool;
}

enum EntityState {
    initializing @0;
    running @1;
    degraded @2;
    respawning @3;
    fallbackActive @4;
    awaitingManual @5;
    permanentlyFailed @6;
}

struct RespawnConfig {
    maxAttempts @0 :UInt32;
    backoffMs @1 :UInt32;
    backoffMultiplier @2 :Float32;
    maxBackoffMs @3 :UInt32;
    fallbackFunction @4 :Data;
}

enum FailureReason {
    timeout @0;
    hardwareFault @1;
    driverError @2;
    memoryExhaustion @3;
    ioError @4;
    protocolViolation @5;
    powerStateFailure @6;
    thermalThrottling @7;
    busError @8;
    authenticationFailure @9;
    panic @10;
    custom @11;
}

enum FailureSeverity {
    recoverable @0;
    critical @1;
    fatal @2;
}

# ── Interrupt internals (from interrupt.capnp) ────────────────────────

enum InterruptLevel {
    edge @0;
    level @1;
    message @2;
}

enum InterruptDelivery {
    fixed @0;
    lowestPriority @1;
    smi @2;
    nmi @3;
    initSignal @4;
    extInt @5;
}

struct MsiCapability {
    deviceId @0 :HalDeviceId;
    vectorCount @1 :UInt8;
    messageAddressLow @2 :UInt64;
    messageData @3 :UInt16;
    supportedModes @4 :List(InterruptMode);
    has64bitAddress @5 :Bool;
    hasPerVectorMask @6 :Bool;
}

struct MsiVector {
    handle @0 :UInt64;
    vector @1 :UInt8;
    address @2 :UInt64;
    data @3 :UInt16;
    targetCpu @4 :UInt32;
}

struct IrqLine {
    vector @0 :UInt8;
    line @1 :UInt8;
    level @2 :InterruptLevel;
    active @3 :Bool;
    shared @4 :Bool;
    owner @5 :UInt64;
}

struct InterruptConfig {
    preferredMode @0 :InterruptMode;
    allowedModes @1 :List(InterruptMode);
    delivery @2 :InterruptDelivery;
    vector @3 :UInt8;
    affinity @4 :UInt32;
    autoEoi @5 :Bool;
}

struct InterruptStatus {
    vector @0 :UInt8;
    mode @1 :InterruptMode;
    count @2 :UInt64;
    lastFiredAt @3 :Timestamp;
    enabled @4 :Bool;
    owner @5 :UInt64;
}

# ── Address space internals (from address_space.capnp) ────────────────

struct VirtualMapping {
    virt @0 :UInt64;
    phys @1 :UInt64;
    size @2 :UInt64;
    flags @3 :PageFlags;
}

struct AddressSpaceInfo {
    asid @0 :UInt64;
    mode @1 :AddressSpaceMode;
    levels @2 :UInt8;
    hhdmOffset @3 :UInt64;
    mappingCount @4 :UInt32;
    maxMappings @5 :UInt32;
}

struct AddressSpaceCreateRequest {
    mode @0 :AddressSpaceMode;
    hhdmOffset @1 :UInt64;
    maxMappings @2 :UInt32;
}

# ── Device descriptor internals (from device_descriptor.capnp) ────────

enum CapabilityType {
    mmio @0;
    portIo @1;
    dma @2;
    interrupt @3;
    busMaster @4;
    powerManagement @5;
    msi @6;
    msix @7;
    custom @8;
}

struct DeviceCapability {
    capabilityType @0 :CapabilityType;
    bar @1 :UInt8;
    offset @2 :UInt32;
    size @3 :UInt32;
}

enum ResourceType {
    memory @0;
    port @1;
    irq @2;
    dma @3;
    msi @4;
    msix @5;
}

struct DeviceResource {
    resourceType @0 :ResourceType;
    address @1 :UInt64;
    size @2 :UInt64;
    flags @3 :UInt32;
}

enum DeviceStatus {
    unknown @0;
    present @1;
    active @2;
    inactive @3;
    error @4;
    disabled @5;
}

enum PowerSleepState {
    busMasterActive @0;
    on @1;
    idle @2;
    standby @3;
    sleep @4;
    deepSleep @5;
    off @6;
    custom @7;
}

struct DeviceState {
    status @0 :DeviceStatus;
    powerState @1 :PowerSleepState;
    lastUpdated @2 :Timestamp;
    errorCount @3 :UInt32;
}

struct DeviceRegistry {
    devices @0 :List(DeviceResource);
    total @1 :UInt32;
    activeCount @2 :UInt32;
}
