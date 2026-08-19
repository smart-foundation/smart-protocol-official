@0xa1b2c3d4e5f60012;

# ═══════════════════════════════════════════════════════════════════════
# Clipboard — system clipboard content access, history, and change
# notification. Backend-agnostic: works with X11 selections, Wayland
# clipboard, macOS pasteboard, or any IPC clipboard service.
#
# Improvements:
#   - ChangesSubscription now has cancel method for explicit teardown.
#   - getHistory/pullChanges accept T.Pagination for bounded results.
#   - ClipboardContent.data uses T.DataHandle for payloads >1KB.
#   - ClipboardChange.source uses Text (app identity is opaque here;
#     typed AppId would over-couple clipboard to app schema).
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

interface Clipboard {
    # Read current clipboard content for a given MIME type.
    getContent @0 (mimeType :Text) -> (data :Data);

    # Set clipboard content. MIME type is application-defined.
    setContent @1 (mimeType :Text, data :Data) -> T.VoidResult;

    # Clear current clipboard content.
    clearContent @2 () -> T.VoidResult;

    # Retrieve clipboard history with pagination support.
    getHistory @3 (pagination :T.Pagination) -> (items :List(ClipboardItem), totalCount :UInt32);

    # Clear all clipboard history.
    clearHistory @4 () -> T.VoidResult;

    # Subscribe to clipboard change events.
    subscribeChanges @5 () -> (subscription :ChangesSubscription);

    # Audit-7: query supported MIME types.
    getSupportedMimeTypes @6 () -> (mimeTypes :List(Text));

    # Audit-7: search clipboard history.
    searchHistory @7 (query :Text, pagination :T.Pagination) -> (items :List(ClipboardItem), totalCount :UInt32);

    # Audit-7: pin an item to prevent auto-expiry.
    pinItem @8 (itemId :T.ClipboardId) -> T.VoidResult;

    # Audit-9: unpin a pinned item.
    unpinItem @9 (itemId :T.ClipboardId) -> T.VoidResult;

    # ── Clipboard Security (false positive: clipboard_security.capnp) ──

    # Get the clipboard security policy.
    getSecurityPolicy @10 () -> (policy :ClipboardSecurityPolicy);

    # Set the clipboard security policy.
    setSecurityPolicy @11 (policy :ClipboardSecurityPolicy) -> T.VoidResult;

    # Grant access to a clipboard item for a specific entity.
    grantAccess @12 (itemId :T.ClipboardId, entry :ClipboardAccessControlEntry) -> T.VoidResult;

    # Revoke access to a clipboard item for a specific entity.
    revokeAccess @13 (itemId :T.ClipboardId, entityId :Text) -> T.VoidResult;

    # Query the access control list for a clipboard item.
    getAccessControlList @14 (itemId :T.ClipboardId) -> (entries :List(ClipboardAccessControlEntry));

    # Query clipboard audit log.
    getAuditLog @15 (pagination :T.Pagination) -> (entries :List(ClipboardAuditEntry), total :UInt32);

    # Set security level for a specific clipboard item.
    setSecurityLevel @16 (itemId :T.ClipboardId, level :ClipboardSecurityLevel) -> T.VoidResult;

    # Audit-9: get a low-resolution preview of clipboard content.
    getPreview @17 (itemId :T.ClipboardId) -> (preview :ClipboardPreview);

    # Audit-9: validate that content matches its claimed MIME type.
    validateContent @18 (itemId :T.ClipboardId) -> (valid :Bool, actualMimeType :Text);

    # Audit-9: convert clipboard content to a target MIME type.
    convertContent @19 (itemId :T.ClipboardId, targetMimeType :Text) -> (data :Data, success :Bool);

    # Audit-9: get configured size limits.
    getSizeLimits @20 () -> (limits :ClipboardSizeLimits);

    # Audit-9: set size limits for clipboard content.
    setSizeLimits @21 (limits :ClipboardSizeLimits) -> T.VoidResult;
}

interface ChangesSubscription {
    pull @0 () -> (changes :List(ClipboardChange));

    # Explicitly cancel this subscription and release resources.
    cancel @1 () -> T.VoidResult;

    # Audit-7: paginated pull for bounded results.
    pullPaginated @2 (pagination :T.Pagination) -> (result :ClipboardPullResult);
}

struct ClipboardContent {
    mimeType @0 :Text;
    # Inline for small payloads; use buffer reference for large data (images, files).
    data @1 :T.DataHandle;
}

struct ClipboardItem {
    id @0 :T.ClipboardId;
    timestamp @1 :T.Timestamp;
    mimeTypes @2 :List(Text);
    # Audit-7: categorization tags (e.g., "work", "personal", "code").
    tags @3 :List(Text);
    # Audit-7: whether this item is pinned (prevents auto-expiry).
    pinned @4 :Bool;
    # Audit-7: ownership information.
    ownership @5 :ClipboardOwnership;
    # Audit-7: structured content type.
    contentType @6 :StructuredContentType;
}

# Audit-7: typed clipboard change events.
enum ClipboardEventType {
    copied @0;       # Content was copied to clipboard
    pasted @1;       # Content was pasted from clipboard
    cleared @2;      # Clipboard was cleared
    expired @3;      # Content expired and was removed
    custom @4;
}

# Audit-7: structured content type replacing bare MIME Text.
struct StructuredContentType {
    union {
        text @0 :Text;           # Plain or rich text
        image @1 :Text;          # Image MIME type (e.g., "image/png")
        color @2 :Text;          # Color value (e.g., "#FF0000")
        uri @3 :T.Uri;           # URI/URL content
        contact @4 :Text;        # Contact card (vCard)
        calendar @5 :Text;       # Calendar event (iCal)
        geo @6 :Text;            # Geographic coordinates
        table @7 :Text;          # Tabular data
        custom @8 :Data;         # Backend-defined content type
    }
}

# Audit-7: ownership tracking for clipboard items.
struct ClipboardOwnership {
    # Entity that owns this clipboard item (app name, user ID).
    ownerId @0 :Text;
    # When ownership was established.
    acquiredAt @1 :T.Timestamp;
    # When ownership expires (null = never).
    expiresAt @2 :T.Timestamp;
    # Maximum lifetime of ownership.
    ttl @3 :T.Duration;
}

# Audit-7: paginated pull result for clipboard changes.
struct ClipboardPullResult {
    changes @0 :List(ClipboardChange);
    totalCount @1 :UInt32;
}

struct ClipboardChange {
    id @0 :T.ClipboardId;
    timestamp @1 :T.Timestamp;
    # Application name or identifier that produced the change (opaque text).
    source @2 :Text;
    mimeTypes @3 :List(Text);
    # Audit-7: typed event type.
    eventType @4 :ClipboardEventType;
}

# ── Clipboard Security (false positive: clipboard_security.capnp) ──────
# Security features for clipboard: encryption, access control, and audit.
# Clipboard data often contains sensitive information (passwords, tokens,
# personal data). These features protect clipboard content at rest and
# control who can access it.

enum ClipboardSecurityLevel {
    none @0;          # No special protection
    sensitive @1;     # Content requires access control
    encrypted @2;     # Content is encrypted at rest
    restricted @3;    # Content restricted to specific apps/users
    custom @4;
}

struct ClipboardAccessControlEntry {
    # Entity (app or user) that has access.
    entityId @0 :Text;
    # Type of access grant.
    grantType @1 :AccessGrantType;
    # When this access was granted.
    grantedAt @2 :T.Timestamp;
    # When this access expires (zero = no expiration).
    expiresAt @3 :T.Timestamp;
    # Optional restriction to specific MIME types.
    allowedMimeTypes @4 :List(Text);
}

enum AccessGrantType {
    read @0;
    write @1;
    readWrite @2;
    deny @3;
    custom @4;
}

struct ClipboardAuditEntry {
    # Unique audit identifier.
    auditId @0 :UInt64;
    # When the access occurred.
    timestamp @1 :T.Timestamp;
    # Clipboard item that was accessed.
    itemId @2 :T.ClipboardId;
    # Who accessed the item (app name, user ID).
    actor @3 :Text;
    # Type of access (read, write, clear).
    action @4 :Text;
    # Whether access was granted or denied.
    result @5 :Bool;
    # Source IP or process ID (if available).
    source @6 :Text;
}

struct ClipboardSecurityPolicy {
    # Default security level for new clipboard content.
    defaultSecurityLevel @0 :ClipboardSecurityLevel;
    # Whether to encrypt all clipboard content at rest.
    encryptAtRest @1 :Bool;
    # Maximum age before auto-clearing non-pinned content.
    maxAge @2 :T.Duration;
    # Whether to require explicit user consent for paste operations.
    requireConsent @3 :Bool;
    # Whether to enable audit logging for clipboard access.
    auditLogging @4 :Bool;
    # Maximum number of audit entries to retain.
    maxAuditEntries @5 :UInt32;
    # Whether to compress large clipboard content.
    compressContent @6 :Bool;
    # Encryption algorithm for at-rest encryption (e.g., "AES-256-GCM").
    encryptionAlgorithm @7 :Text;
}

# ── Audit-9: Clipboard Preview ─────────────────────────────────────────
# Low-resolution preview of clipboard content for UI display.
struct ClipboardPreview {
    # Preview text (truncated for text content).
    textPreview @0 :Text;
    # Whether the preview is available.
    available @1 :Bool;
    # Original content size in bytes.
    originalSize @2 :UInt64;
    # Preview MIME type.
    previewMimeType @3 :Text;
}

# ── Audit-9: Clipboard Size Limits ─────────────────────────────────────
# Configuration for maximum clipboard content sizes.
struct ClipboardSizeLimits {
    # Maximum size for a single clipboard item in bytes (0 = unlimited).
    maxItemSize @0 :UInt64;
    # Maximum total clipboard history size in bytes (0 = unlimited).
    maxHistorySize @1 :UInt64;
    # Maximum number of items in clipboard history (0 = unlimited).
    maxHistoryCount @2 :UInt32;
    # Maximum size for inline content before using buffer reference (bytes).
    inlineThreshold @3 :UInt64;
}
