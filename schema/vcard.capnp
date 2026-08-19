@0xa1b2c3d4e5f60108;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# vCard — vCard import/export for contacts interoperability (RFC 6350).
#
# contacts.capnp currently has no vCard support. This schema provides
# bidirectional vCard ↔ Contact conversion with full RFC 6350 support.
#
# Zero backend assumptions: no libvcard, no EKD, no platform contact
# APIs. Backend provides vCard parsing/generation.
#
# Used by: contacts.capnp (import/export operations)
#
# Improvements (audit-7):
#   - validateVCard method for standalone validation.
#   - GenderValue enum replacing bare Text in VCardGender.value.
#   - KeyType enum (PGP, X509, SSH) for VCardKey.
#   - VCardVersion.v5_0 forward-compatible slot.
#   - VCardPropertyType enum for structured TYPE parameters.
#   - VCardGeo.altitude field.
#   - PronunciationFormat enum for VCardSound.
#   - vCard sync protocol (false positive from vcard_sync.capnp):
#     incremental sync, conflict resolution, last-modified tracking.
#   - vCard schema validation (false positive from vcard_schema.capnp):
#     custom property definitions, schema compliance checking.
# ═══════════════════════════════════════════════════════════════════════

interface VCardService {
    # Import vCard data to Contact(s).
    importVCard @0 (request :ImportRequest) -> (result :ImportResult);

    # Export Contact(s) to vCard data.
    exportVCard @1 (request :ExportRequest) -> (result :ExportResult);

    # Parse vCard data without importing (validation/inspection).
    parseVCard @2 (data :T.DataHandle) -> (result :ParseResult);

    # Format Contact as vCard data.
    formatVCard @3 (request :FormatRequest) -> (result :FormatResult);

    # Get supported vCard versions.
    getSupportedVersions @4 () -> (versions :List(VCardVersion));

    # Get supported properties.
    getSupportedProperties @5 () -> (properties :List(VCardPropertyInfo));

    # ── Audit-7 additions ────────────────────────────────────

    # Validate vCard data without importing (syntax + schema compliance).
    validateVCard @6 (data :T.DataHandle, version :VCardVersion) -> (result :ValidationResult);

    # ── vCard sync (false positive: vcard_sync.capnp) ────────
    # Get the sync token for incremental vCard sync.
    getSyncToken @7 (contactIds :List(T.ContactId)) -> (token :Text);

    # Fetch vCard changes since a sync token.
    syncChanges @8 (syncToken :Text) -> (result :VCardSyncResult);

    # Resolve a vCard sync conflict.
    resolveConflict @9 (conflictId :Text, resolution :ConflictResolution) -> T.VoidResult;

    # ── Schema validation (false positive: vcard_schema) ─────
    # Get the vCard property schema (definitions, constraints).
    getPropertySchema @10 () -> (schema :VCardPropertySchema);

    # Validate a property against the schema.
    validateProperty @11 (property :VCardProperty, version :VCardVersion) -> (valid :Bool, errors :List(T.Warning));
}

# ─── Import/Export ───────────────────────────────────────────

struct ImportRequest {
    # vCard data (inline or buffer).
    data @0 :T.DataHandle;
    # vCard version to use for parsing (empty = auto-detect).
    version @1 :VCardVersion;
    # Target contact group (optional).
    groupId @2 :T.GroupId;
    # How to handle duplicates.
    duplicateHandling @3 :DuplicateHandling = update;
    # Whether to merge with existing contacts.
    merge @4 :Bool = false;
    # Custom field mapping.
    fieldMapping @5 :T.StringMap;
}

enum VCardVersion {
    v21 @0;    # vCard 2.1 (legacy)
    v30 @1;    # vCard 3.0 (RFC 2425/2426)
    v40 @2;    # vCard 4.0 (RFC 6350)
    auto @3;    # Auto-detect
    # Forward-compatible slot for hypothetical vCard 5.0 (audit-7).
    v50 @4;
}

enum DuplicateHandling {
    skip @0;        # Skip duplicates
    update @1;      # Update existing
    create @2;      # Create new (allow duplicates)
    merge @3;       # Merge data
    custom @4;
}

struct ImportResult {
    union {
        success @0 :ImportSuccess;
        error @1 :T.Error;
        partial @2 :ImportPartial;
    }
}

struct ImportSuccess {
    # Imported contacts.
    contacts @0 :List(ImportedContact);
    # Total vCards processed.
    totalProcessed @1 :UInt32;
    # Successfully imported.
    imported @2 :UInt32;
    # Skipped (duplicates).
    skipped @3 :UInt32;
    # Failed.
    failed @4 :UInt32;
    # Warnings.
    warnings @5 :List(T.Warning);
}

struct ImportPartial {
    contacts @0 :List(ImportedContact);
    totalProcessed @1 :UInt32;
    imported @2 :UInt32;
    skipped @3 :UInt32;
    failed @4 :UInt32;
    errors @5 :List(ImportError);
    warnings @6 :List(T.Warning);
}

struct ImportedContact {
    contactId @0 :T.ContactId;
    # vCard UID that was imported.
    vcardUid @1 :Text;
    # Whether this was a new contact.
    created @2 :Bool;
    # Warnings for this contact.
    warnings @3 :List(T.Warning);
}

struct ImportError {
    # vCard UID (if available).
    vcardUid @0 :Text;
    # Line number in vCard data.
    line @1 :UInt32;
    error @2 :T.Error;
}

struct ExportRequest {
    # Contact IDs to export.
    contactIds @0 :List(T.ContactId);
    # Export all contacts if true.
    allContacts @1 :Bool = false;
    # Target vCard version.
    version @2 :VCardVersion = v40;
    # Include only these property groups.
    includeGroups @3 :List(Text);
    # Exclude these properties.
    excludeProperties @4 :List(Text);
    # Custom field mapping.
    fieldMapping @5 :T.StringMap;
    # Line folding length (75 per RFC, 0 = no folding).
    lineLength @6 :UInt16 = 75;
    # Whether to include PHOTO as inline base64.
    inlinePhotos @7 :Bool = true;
    # Output format.
    outputFormat @8 :OutputFormat = single;
}

enum OutputFormat {
    # Single vCard with multiple contacts.
    single @0;
    # Multiple vCards (one per contact).
    multiple @1;
    # Directory stream (one vCard per line, minimal).
    stream @2;
}

struct ExportResult {
    union {
        success @0 :ExportSuccess;
        error @1 :T.Error;
        partial @2 :ExportPartial;
    }
}

struct ExportSuccess {
    # vCard data.
    data @0 :T.DataHandle;
    # Number of contacts exported.
    exported @1 :UInt32;
    # Warnings.
    warnings @2 :List(T.Warning);
}

struct ExportPartial {
    data @0 :T.DataHandle;
    exported @1 :UInt32;
    failed @2 :UInt32;
    errors @3 :List(ExportError);
    warnings @4 :List(T.Warning);
}

struct ExportError {
    contactId @0 :T.ContactId;
    error @1 :T.Error;
}

# ─── Parse/Format ────────────────────────────────────────────

struct ParseResult {
    union {
        success @0 :ParseSuccess;
        error @1 :T.Error;
    }
}

struct ParseSuccess {
    # Parsed vCards.
    vcards @0 :List(VCard);
    # Warnings.
    warnings @1 :List(T.Warning);
}

struct FormatRequest {
    contact @0 :VCardContact;
    version @1 :VCardVersion = v40;
    lineLength @2 :UInt16 = 75;
    inlinePhotos @3 :Bool = true;
}

struct FormatResult {
    union {
        success @0 :FormatSuccess;
        error @1 :T.Error;
    }
}

struct FormatSuccess {
    data @0 :T.DataHandle;
    warnings @1 :List(T.Warning);
}

# ─── Validation (audit-7) ────────────────────────────────────

struct ValidationResult {
    valid @0 :Bool;
    # Errors found during validation.
    errors @1 :List(ValidationError);
    # Warnings (non-fatal issues).
    warnings @2 :List(T.Warning);
}

struct ValidationError {
    # Line number in vCard data (0 if not line-specific).
    line @0 :UInt32;
    # Property name that caused the error.
    property @1 :Text;
    # Error description.
    message @2 :Text;
    # Severity: error or warning.
    severity @3 :ValidationSeverity;
}

enum ValidationSeverity {
    error @0;
    warning @1;
    info @2;
    custom @3;
}

# ─── vCard Data Model ─────────────────────────────────────────

struct VCard {
    version @0 :VCardVersion;
    # All properties (including custom).
    properties @1 :List(VCardProperty);
    # Raw lines for round-tripping unknown properties.
    rawLines @2 :List(Text);
}

# ── VCard Value ────────────────────────────────────────────────

struct VCardValue {
    union {
        text @0 :Text;
        # Structured values:
        structured @1 :VCardStructuredValue;
        # Binary data (base64 encoded in vCard).
        binary @2 :Data;
        # URI reference.
        uri @3 :T.Uri;
        # Date/time.
        date @4 :T.Timestamp;
        # Boolean.
        boolean @5 :Bool;
        # Integer.
        integer @6 :Int64;
        # Float.
        float @7 :Float64;
        # Custom/backend-specific value.
        custom @8 :Data;
    }
}

struct VCardProperty {
    # Property name (e.g., "FN", "N", "EMAIL", "TEL", "ADR", "PHOTO").
    name @0 :Text;
    # Property group (e.g., "item1", "work").
    group @1 :Text;
    # Parameters (e.g., TYPE=HOME, ENCODING=BASE64).
    parameters @2 :List(VCardParameter);
    # Values (multi-value properties).
    values @3 :List(VCardValue);
}

struct VCardParameter {
    name @0 :Text;
    value @1 :Text;
}

struct VCardStructuredValue {
    # Components separated by ; in vCard.
    components @0 :List(Text);
}

struct VCardDateTime {
    # ISO 8601 format.
    value @0 :Text;
    # Whether it's a date-only (no time).
    dateOnly @1 :Bool;
    # Whether it's UTC.
    utc @2 :Bool;
    # Timezone ID (if not UTC).
    timezone @3 :Text;
}

# ─── Simplified Contact Model for vCard ──────────────────────

struct VCardContact {
    # Basic identification
    uid @0 :Text;
    fn @1 :Text;           # Formatted name
    n @2 :VCardName;       # Structured name
    nickname @3 :Text;
    photo @4 :List(VCardPhoto);
    logo @5 :List(VCardPhoto);
    sound @6 :List(VCardSound);  # Pronunciation

    # Delivery addresses
    adr @7 :List(VCardAddress);

    # Communications
    tel @8 :List(VCardTelephone);
    email @9 :List(VCardEmail);
    impp @10 :List(VCardImpp);   # Instant messaging
    lang @11 :List(VCardLanguage);

    # Geographical
    geo @12 :List(VCardGeo);
    tz @13 :List(VCardTimezone);

    # Organizational
    org @14 :List(VCardOrganization);
    title @15 :Text;
    role @16 :Text;
    member @17 :List(Text);      # Group members (URNs)

    # Explanatory
    categories @18 :List(Text);
    note @19 :Text;
    prodid @20 :Text;
    rev @21 :T.Timestamp;

    # Security
    key @22 :List(VCardKey);

    # Calendar
    bday @23 :VCardDateTime;
    anniversary @24 :VCardDateTime;
    caladruri @25 :List(T.Uri);
    caluri @26 :List(T.Uri);
    fburl @27 :List(T.Uri);

    # Gender (RFC 6350 Section 6.2.5)
    gender @28 :VCardGender;

    # Expertise, Hobby, Interest (RFC 6350 Section 6.7)
    expertise @29 :List(VCardExpertise);
    hobby @30 :List(VCardHobby);
    interest @31 :List(VCardInterest);

    # XML property (RFC 6350 Section 6.8)
    xml @32 :List(VCardXml);

    # Custom properties
    custom @33 :List(VCardProperty);
}

struct VCardName {
    family @0 :Text;
    given @1 :Text;
    additional @2 :Text;
    prefix @3 :Text;
    suffix @4 :Text;
}

struct VCardPhoto {
    data @0 :T.DataHandle;
    mediaType @1 :T.MimeType;
    uri @2 :T.Uri;
}

struct VCardSound {
    data @0 :T.DataHandle;
    mediaType @1 :T.MimeType;
    uri @2 :T.Uri;
    # Pronunciation format (audit-7).
    pronunciationFormat @3 :PronunciationFormat;
}

enum PronunciationFormat {
    ipa @0;        # International Phonetic Alphabet
    xSAMPA @1;     # Extended Speech Assessment Methods Phonetic Alphabet
    custom @2;
}

struct VCardAddress {
    # TYPE parameters
    types @0 :List(Text);
    # Preferred
    preferred @1 :Bool;
    # Components: PO Box, Extended Address, Street, City, Region, Postal Code, Country
    components @2 :List(Text);
    # Geo URI
    geo @3 :T.Uri;
    # Timezone
    tz @4 :Text;
}

struct VCardTelephone {
    types @0 :List(Text);
    preferred @1 :Bool;
    value @2 :Text;  # E.164 format recommended
    # For voice/video/text capabilities
    capabilities @3 :List(TelephoneCapability);
}

enum TelephoneCapability {
    voice @0;
    video @1;
    text @2;
    cell @3;
    pager @4;
    bbs @5;
    modem @6;
    car @7;
    isdn @8;
    custom @9;
}

struct VCardEmail {
    types @0 :List(Text);
    preferred @1 :Bool;
    value @2 :Text;
}

struct VCardImpp {
    types @0 :List(Text);
    preferred @1 :Bool;
    uri @2 :T.Uri;
}

struct VCardLanguage {
    tag @0 :Text;  # BCP 47 language tag
    preferred @1 :Bool;
}

struct VCardGeo {
    uri @0 :T.Uri;  # geo: URI
    lat @1 :Float64;
    lon @2 :Float64;
    # Altitude in meters (audit-7).
    altitude @3 :Float64;
}

struct VCardTimezone {
    # TZID
    id @0 :Text;
    # UTC offset
    offset @1 :Text;
    # VTIMEZONE data
    vtimezone @2 :Text;
}

struct VCardOrganization {
    name @0 :Text;
    units @1 :List(Text);
    title @2 :Text;
    role @3 :Text;
}

struct VCardKey {
    data @0 :T.DataHandle;
    mediaType @1 :T.MimeType;
    uri @2 :T.Uri;
    # Key type (audit-7): PGP, X509, SSH, etc.
    keyType @3 :KeyType;
}

enum KeyType {
    pgp @0;
    x509 @1;
    ssh @2;
    custom @3;
}

# ─── RFC 6350 Section 6.2.5 — Gender ────────────────────────

struct VCardGender {
    # Gender value (audit-7: typed enum replacing bare Text).
    value @0 :GenderValue;
    # Textual representation (e.g., "Pronoun: they/them").
    text @1 :Text;
}

enum GenderValue {
    male @0;
    female @1;
    other @2;
    none @3;
    undefined @4;
    custom @5;
}

# ─── RFC 6350 Section 6.7 — Expertise, Hobby, Interest ──────

struct VCardExpertise {
    domain @0 :Text;        # e.g., "programming", "cooking"
    level @1 :ExpertiseLevel;
    # Human-readable description.
    description @2 :Text;
}

enum ExpertiseLevel {
    beginner @0;
    average @1;
    good @2;
    expert @3;
    master @4;
    custom @5;
}

struct VCardHobby {
    domain @0 :Text;        # e.g., "photography", "hiking"
    level @1 :HobbyLevel;
    # Human-readable description.
    description @2 :Text;
}

enum HobbyLevel {
    low @0;
    medium @1;
    high @2;
    custom @3;
}

struct VCardInterest {
    domain @0 :Text;        # e.g., "science fiction", "history"
    level @1 :InterestLevel;
    # Human-readable description.
    description @2 :Text;
}

enum InterestLevel {
    low @0;
    medium @1;
    high @2;
    custom @3;
}

# ─── RFC 6350 Section 6.8 — XML Property ────────────────────

struct VCardXml {
    # XML namespace.
    namespace @0 :Text;
    # Raw XML content.
    content @1 :Data;
}

# ─── Property Info ──────────────────────────────────────────

struct VCardPropertyInfo {
    name @0 :Text;
    description @1 :Text;
    versions @2 :List(VCardVersion);
    cardinality @3 :Cardinality;
    valueType @4 :ValueType;
    parameters @5 :List(Text);
}

enum Cardinality {
    single @0;
    multi @1;
    optional @2;
}

enum ValueType {
    text @0;
    structured @1;
    binary @2;
    uri @3;
    dateTime @4;
    custom @5;
}

# ─── TYPE Parameter Enum (audit-7) ──────────────────────────

enum VCardPropertyType {
    home @0;
    work @1;
    text @2;
    voice @3;
    fax @4;
    cell @5;
    video @6;
    pager @7;
    bbs @8;
    modem @9;
    car @10;
    isdn @11;
    pref @12;
    custom @13;
}

# ─── vCard Sync (false positive: vcard_sync.capnp) ──────────

struct VCardSyncResult {
    # New sync token.
    newSyncToken @0 :Text;
    # vCards added or modified since last sync.
    changed @1 :List(VCard);
    # Contact IDs deleted since last sync.
    deleted @2 :List(T.ContactId);
    # Whether there are more changes to fetch.
    hasMore @3 :Bool;
    # Sync conflicts that need resolution.
    conflicts @4 :List(VCardSyncConflict);
}

struct VCardSyncConflict {
    conflictId @0 :Text;
    contactId @1 :T.ContactId;
    localVersion @2 :VCard;
    remoteVersion @3 :VCard;
    detectedAt @4 :T.Timestamp;
}

enum ConflictResolution {
    keepLocal @0;
    keepRemote @1;
    merge @2;
    custom @3;
}

# ─── Schema Validation (false positive: vcard_schema) ────────

struct VCardPropertySchema {
    # All known property definitions.
    properties @0 :List(PropertyDefinition);
    # Required properties per version.
    requiredProperties @1 :List(RequiredProperty);
    # Custom property namespace registrations.
    customNamespaces @2 :List(CustomNamespace);
}

struct PropertyDefinition {
    name @0 :Text;
    description @1 :Text;
    versions @2 :List(VCardVersion);
    cardinality @3 :Cardinality;
    allowedValues @4 :List(Text);
    parameters @5 :List(Text);
}

struct RequiredProperty {
    version @0 :VCardVersion;
    properties @1 :List(Text);
}

struct CustomNamespace {
    prefix @0 :Text;
    uri @1 :T.Uri;
    description @2 :Text;
}
