@0xa1b2c3d4e5f60012;

# ═══════════════════════════════════════════════════════════════════════
# Clipboard — system clipboard content, history, and change notification.
#
# WHAT THIS IS
#   The one clipboard service. Reading, writing, offering multiple
#   representations, history, previews, validation, conversion, and change
#   notification.
#
# THE HOT PATH IS ZERO-COPY
#   `getContent`, `setContent` and `convertContent` all carry
#   `ClipboardContent { mimeType, data :T.DataHandle }`. They used to pass
#   `Data` inline while this very file defined the zero-copy struct and then
#   never used it — so pasting a screenshot copied the whole buffer into the
#   message, deserialized into a fresh allocation, on the protocol's single
#   most copy-prone path. The orphaned type is now the live contract.
#
# AUTHORITY IS A CAPABILITY REFERENCE
#   The file used to carry a parallel access-control system: `grantAccess`,
#   `revokeAccess`, `getAccessControlList`, `getAuditLog`, and a
#   `ClipboardAccessControlEntry` of permission strings (`read`, `write`,
#   `readWrite`, `deny`) keyed by free-text entity ids. That is a second
#   authority that must agree with capability.capnp forever, and it is the
#   only one of the two that is NOT revocable. It is deleted: authority is
#   the capability reference held at acquisition, attenuation and revocation
#   are capability.capnp's job, and the audit trail is capability.capnp's
#   `AuditEntry`.
#
# DELIBERATE LIMIT — ONE SELECTION
#   There is exactly one clipboard and one primary selection per seat. A
#   device with two concurrent selections (gaze plus hand, or two users on
#   one seat) is a future requirement; when it arrives the honest fix is an
#   open selection-name parameter, not a second clipboard service. Recorded
#   here so no one has to guess whether the omission is an oversight.
#
# WHAT ELSE WAS DELETED
#   - The security-policy family (`getSecurityPolicy`/`setSecurityPolicy`,
#     `ClipboardSecurityLevel`, `ClipboardSecurityPolicy`, `setSecurityLevel`):
#     at-rest encryption is the backend's business, `encryptionAlgorithm` is
#     implementation tuning, and `requireConsent` named a consent flow no
#     method implemented — a backend had to invent a side channel.
#   - `ClipboardSizeLimits.inlineThreshold`: a protocol field stating WHEN an
#     implementation should switch from inline to buffer. The backend
#     decides; the protocol just uses T.DataHandle.
#   - `StructuredContentType`, a third content-type model in the batch that
#     no live method used. MIME types are the open vocabulary.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

interface Clipboard {
    # Read current clipboard content for a given MIME type.
    getContent @0 (mimeType :T.MimeType) -> (result :ContentResult);

    # Set clipboard content. The clipboard may hold several representations
    # of one copy (an image plus its text alternative); see `setOffer`.
    setContent @1 (content :ClipboardContent) -> T.VoidResult;

    # Clear current clipboard content.
    clearContent @2 () -> T.VoidResult;

    # Retrieve clipboard history with pagination.
    getHistory @3 (pagination :T.Pagination)
               -> (items :List(ClipboardItem), total :UInt64);

    # Clear all clipboard history.
    clearHistory @4 () -> T.VoidResult;

    # Subscribe to clipboard change events.
    subscribeChanges @5 () -> (subscription :ClipboardChangeSubscription);

    # Query supported MIME types.
    getSupportedMimeTypes @6 () -> (mimeTypes :List(T.MimeType));

    # Search clipboard history.
    searchHistory @7 (query :Text, pagination :T.Pagination)
                  -> (items :List(ClipboardItem), total :UInt64);

    # Pin an item to prevent auto-expiry.
    pinItem @8 (itemId :T.ClipboardId) -> T.VoidResult;

    # Unpin a pinned item.
    unpinItem @9 (itemId :T.ClipboardId) -> T.VoidResult;

    # Remove one item from history.
    deleteItem @10 (itemId :T.ClipboardId) -> T.VoidResult;

    # Get a low-resolution preview of clipboard content.
    getPreview @11 (itemId :T.ClipboardId) -> (result :PreviewResult);

    # Validate that content matches its claimed MIME type.
    # "Content does not match its claim" is a security-relevant event, so it
    # carries an error code rather than a bare boolean.
    validateContent @12 (itemId :T.ClipboardId)
                     -> (result :ContentValidation);

    # Convert clipboard content to a target MIME type.
    convertContent @13 (itemId :T.ClipboardId, targetMimeType :T.MimeType)
                    -> (result :ConversionResult);

    # Get configured size limits.
    getSizeLimits @14 () -> (limits :ClipboardSizeLimits);

    # Set size limits for clipboard content.
    setSizeLimits @15 (limits :ClipboardSizeLimits) -> T.VoidResult;

    # Offer several representations of one copy in a single call, so a
    # backend never has to guess that three separate `setContent` calls
    # belong together.
    setOffer @16 (offers :List(ClipboardContent)) -> T.VoidResult;
}


interface ClipboardChangeSubscription {
    pull @0 (maxEvents :UInt32) -> (changes :List(ClipboardChange));
    cancel @1 () -> T.VoidResult;
}

# ── Content ───────────────────────────────────────────────────

# The one clipboard payload type: an open content type plus a buffer
# reference. It was defined in this file and used nowhere; it is now the
# parameter and return type of every payload method.
struct ClipboardContent {
    mimeType @0 :T.MimeType;
    data     @1 :T.DataHandle;
}

struct ContentResult {
    union {
        content @0 :ClipboardContent;
        # The clipboard holds nothing. This is an answer, not a fault, and
        # it is distinguishable from "there is no clipboard service".
        empty   @1 :Void;
        error   @2 :T.Error;
        unknown @3 :Void;
    }
}

struct ClipboardItem {
    id        @0 :T.ClipboardId;
    timestamp @1 :T.Timestamp;
    mimeTypes @2 :List(T.MimeType);
    # Audit-7: categorization tags (e.g., "work", "personal", "code").
    tags      @3 :List(Text);
    # Audit-7: whether this item is pinned (prevents auto-expiry).
    pinned    @4 :Bool;
    # Audit-7: ownership information.
    ownership @5 :ClipboardOwnership;
    # Size of the stored payload in bytes.
    sizeBytes @6 :UInt64;
}

# Audit-7: typed clipboard change events.
enum ClipboardEventType {
    copied  @0;    # Content was copied to clipboard
    pasted  @1;    # Content was pasted from clipboard
    cleared @2;    # Clipboard was cleared
    expired @3;    # Content expired and was removed
    custom  @4;
}

# Audit-7: ownership tracking for clipboard items.
struct ClipboardOwnership {
    # Opaque source identity, not a free-text app name to string-match.
    sourceId   @0 :T.ClipboardSourceId;
    # When ownership was established.
    acquiredAt @1 :T.Timestamp;
    # When ownership expires (zero = never).
    expiresAt  @2 :T.Timestamp;
    # Maximum lifetime of ownership.
    ttl        @3 :T.Duration;
}

struct ClipboardChange {
    id        @0 :T.ClipboardId;
    timestamp @1 :T.Timestamp;
    sourceId  @2 :T.ClipboardSourceId;
    mimeTypes @3 :List(T.MimeType);
    eventType @4 :ClipboardEventType;
}

# ── Audit-9: Clipboard Preview ─────────────────────────────────────────

struct PreviewResult {
    union {
        preview @0 :ClipboardPreview;
        error   @1 :T.Error;
        unknown @2 :Void;
    }
}

struct ClipboardPreview {
    # Preview text (truncated for text content).
    textPreview @0 :Text;
    # Whether the preview is available.
    available @1 :Bool;
    # Original content size in bytes.
    originalSize @2 :UInt64;
    # Preview MIME type.
    previewMimeType @3 :T.MimeType;
}

# ── Audit-9: Clipboard Size Limits ─────────────────────────────────────

struct ClipboardSizeLimits {
    # Maximum size for a single clipboard item in bytes (0 = unlimited).
    maxItemSize @0 :UInt64;
    # Maximum total clipboard history size in bytes (0 = unlimited).
    maxHistorySize @1 :UInt64;
    # Maximum number of items in clipboard history (0 = unlimited).
    maxHistoryCount @2 :UInt32;
}

# ── Validation and conversion ──────────────────────────────────────────

# "Content does not match its claimed type" is a security-relevant finding:
# a consumer checking for spoofed clipboard content must be able to route on
# a code, not parse prose.
struct ContentValidation {
    union {
        valid   @0 :Void;
        invalid @1 :T.Error;
        unknown @2 :Void;
    }
}

struct ConversionResult {
    union {
        content @0 :ClipboardContent;
        # The requested conversion is not available — a real outcome, not a
        # failure, and no longer hidden inside a boolean.
        unsupported @1 :Void;
        error   @2 :T.Error;
        unknown @3 :Void;
    }
}
