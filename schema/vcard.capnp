@0xa1b2c3d4e5f60108;

using T = import "types.capnp";
using Cal = import "calendar.capnp";

# ═══════════════════════════════════════════════════════════════════════
# vCard — vCard import/export for contacts interoperability (RFC 6350).
#
# This file is a CONVERTER, and it is kept as its own schema rather than
# merged into contacts.capnp: vCard is an external standard that will
# exist in 2046 regardless of what this protocol does, so a dedicated
# converter contract is one of the more timeless things in the tree. The
# payload handling is correct — photos, sounds, keys and imported/exported
# data are all T.DataHandle — and is kept.
#
# Zero backend assumptions: no libvcard, no EKD, no platform contact
# APIs. Backend provides vCard parsing/generation.
#
# ── THE CONVERSION CONTRACT IS NOW DECLARED ────────────────────────────
#
# contacts.capnp already owned import/export with a free-form `format`
# string, and this file owned the same operations with structured
# requests, and NEITHER declared the field mapping: does
# `Contact.type = organization` produce FN or N? Which `EmailEntry.type`
# maps to TYPE=INTERNET? Without the mapping, import/export is not
# interoperable — every backend pairs them differently. The mapping is
# declared at the bottom of this header, and `ImportRequest.fieldMapping`
# names the exact keys a caller may override.
#
# ── THE 1998 TYPE VOCABULARY IS GONE ───────────────────────────────────
#
# `VCardPropertyType` froze the RFC 2426 (1998) TYPE parameter
# vocabulary into a required position — including bulletin-board systems
# and dial-up modems — while the same file had
# `VCardProperty.parameters @2 :List(VCardParameter)`, the open key/value
# mechanism that carries exactly that information two structs away. The
# enum was a lossy duplicate of a mechanism next to it: anything it could
# express, `parameters` already could; anything it could not
# (TYPE=x-other, a 2046 parameter), it could not. `TelephoneCapability`
# was the same 1998 list frozen a second time, on the telephone path,
# while the address and email paths already used open `List(Text)`.
#
# All three now use the open mechanism, so one spelling replaces three
# and a 2046 property parameter is expressible.
#
# ── THE SCHEMA REGISTRY IS GONE ────────────────────────────────────────
#
# `getPropertySchema`, `VCardPropertySchema`, `PropertyDefinition`,
# `RequiredProperty`, `CustomNamespace` and `validateProperty` described
# an external standard the consumer can already read, in six types and
# two methods, with no consumer. They are deleted: a converter contract
# is what remains.
#
# ── v50 IS GONE ────────────────────────────────────────────────────────
#
# `VCardVersion.v50` was a declared slot for a hypothetical vCard 5.0 —
# a standard that does not exist (4.0 / RFC 6350 is the latest published
# version). Asserting a future that may never arrive is exactly the
# failure the doctrine names, and the slot made
# `getSupportedVersions` return a value no implementation could support.
#
# Used by: contacts.capnp (import/export operations)
# ═══════════════════════════════════════════════════════════════════════
#
# ══════════════════════════════════════════════════════════════════════
# THE VCardContact ↔ Contact MAPPING — the conversion contract
#
# Every row is normative. A backend that cannot honour a row MUST report
# it as a T.Warning on the imported contact rather than silently dropping
# the field, so a caller can see what was lost.
#
# VCardContact.uid        -> Contact.metadata["vcard.uid"]
# VCardContact.fn         -> Contact.name.display
# VCardContact.n          -> Contact.name.{family,given,middle,prefix,suffix}
#                             (empty components are omitted, not blanked)
# VCardContact.nickname   -> Contact.metadata["vcard.nickname"]
# VCardContact.org        -> Contact.organization.{name,department}
#                             and Contact.type = "organization" when FN
#                             is the org name
# VCardContact.title      -> Contact.organization.title
# VCardContact.role       -> Contact.organization.role
# VCardContact.tel        -> Contact.phones[].value (E.164 normalised when
#                             parseable; the raw value is preserved in
#                             metadata["vcard.tel.raw"])
# VCardContact.email      -> Contact.emails[].value
# VCardContact.adr        -> Contact.addresses[] (street/city/region/
#                             postalCode/country, in that component order)
# VCardContact.photo      -> Contact.photo (T.DataHandle)
# VCardContact.bday       -> Contact.birthday (T.Date; the time part is
#                             dropped, never guessed)
# VCardContact.anniversary-> Contact.metadata["vcard.anniversary"]
# VCardContact.categories-> Contact.tags
# VCardContact.note       -> Contact.note
# VCardContact.geo        -> Contact.customFields["geo"]
#
# TYPE parameters: VCardAddress.types / VCardEmail.types /
# VCardTelephone.types are open Text lists and map to the SAME open
# tokens contacts.capnp publishes (home, work, other, ...). A TYPE value
# that is not a published token is preserved verbatim in the sub-entry's
# `type` and MUST be ignored rather than rejected by a consumer.
#
# `ImportRequest.fieldMapping` may override any row above. Its keys are
# the DESTINATION field paths spelled exactly as in this table
# ("name.display", "phones[].value", "metadata.vcard.uid", ...), and its
# values are backend-declared. An unknown key MUST be reported as a
# warning, never silently honoured.
# ══════════════════════════════════════════════════════════════════════

interface VCardService {
    # Import vCard data to Contact(s).
    importVCard @0 (request :ImportRequest) -> (result :ImportResult);

    # Export Contact(s) to vCard data.
    exportVCard @1 (request :ExportRequest) -> (result :VcardExportResult);

    # Parse vCard data without importing (validation/inspection).
    parseVCard @2 (data :T.DataHandle) -> (result :ParseResult);

    # Format Contact as vCard data.
    formatVCard @3 (request :FormatRequest) -> (result :FormatResult);

    # Get supported vCard versions. Honest now that the hypothetical
    # v50 slot is gone: this returns what the backend can actually
    # read and write.
    getSupportedVersions @4 () -> (versions :List(VCardVersion));

    # ── Audit-7 additions ────────────────────────────────────

    # ── vCard sync ──
    getSyncToken @5 (contactIds :List(T.ContactId)) -> (token :Text);
    syncChanges @6 (syncToken :Text) -> (result :VCardSyncResult);
    # ConflictResolution is calendar.capnp's: the identical enum used to
    # be declared in both files, so a file importing both had two types
    # by one name.
    resolveConflict @7 (conflictId :Text, resolution :Cal.ConflictResolution) -> T.VoidResult;
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
    # Custom field mapping. Keys are the DESTINATION field paths spelled
    # exactly as in the mapping table in this file's header.
    fieldMapping @5 :T.StringMap;
}

# No v50: a declared slot for a standard that does not exist made
# getSupportedVersions return a value no implementation could support.
# The ordinal is preserved anyway (the doctrine's rule) and simply
# carries no meaning.
enum VCardVersion {
    unspecified @0;   # Sentinel: an unset value is not the @0 paradigm
    v21 @1;    # vCard 2.1 (legacy)
    v30 @2;    # vCard 3.0 (RFC 2425/2426)
    v40 @3;    # vCard 4.0 (RFC 6350) — the latest published version
    auto @4;    # Auto-detect
}

enum DuplicateHandling {
    unspecified @0;   # Sentinel: an unset value is not the @0 paradigm
    skip @1;        # Skip duplicates
    update @2;      # Update existing
    create @3;      # Create new (allow duplicates)
    merge @4;       # Merge data
    custom @5;
}

struct ImportResult {
    union {
        success @0 :ImportSuccess;
        error @1 :T.Error;
        partial @2 :ImportPartial;
        unknown @3 :T.UnknownEvent;
    }
}

struct ImportSuccess {
    contacts @0 :List(ImportedContact);
    totalProcessed @1 :UInt32;
    imported @2 :UInt32;
    skipped @3 :UInt32;
    failed @4 :UInt32;
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
    created @2 :Bool;
    warnings @3 :List(T.Warning);
}

struct ImportError {
    vcardUid @0 :Text;
    # Line number in vCard data.
    line @1 :UInt32;
    error @2 :T.Error;
}

struct ExportRequest {
    contactIds @0 :List(T.ContactId);
    # Export all contacts if true.
    allContacts @1 :Bool = false;
    # Target vCard version.
    version @2 :VCardVersion = v40;
    # Include only these property groups.
    includeGroups @3 :List(Text);
    # Exclude these properties.
    excludeProperties @4 :List(Text);
    # Custom field mapping (see the mapping table in this file's header).
    fieldMapping @5 :T.StringMap;
    # Line folding length (0 = no folding).
    lineLength @6 :UInt16 = 0;
    # Whether to include PHOTO as inline base64.
    inlinePhotos @7 :Bool = true;
    # Output format.
    outputFormat @8 :OutputFormat = single;
}

# `single`/`multiple`/`stream` are output shapes of one encoding, not
# three technologies, so they survive as a closed set.
enum OutputFormat {
    unspecified @0;   # Sentinel: an unset value is not the @0 paradigm
    single @1;
    multiple @2;
    stream @3;
}

struct VcardExportResult {
    union {
        success @0 :ExportSuccess;
        error @1 :T.Error;
        partial @2 :ExportPartial;
        unknown @3 :T.UnknownEvent;
    }
}

struct ExportSuccess {
    data @0 :T.DataHandle;
    exported @1 :UInt32;
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
        unknown @2 :T.UnknownEvent;
    }
}

struct ParseSuccess {
    vcards @0 :List(VCard);
    warnings @1 :List(T.Warning);
}

struct FormatRequest {
    contact @0 :VCardContact;
    version @1 :VCardVersion = v40;
    lineLength @2 :UInt16 = 0;
    inlinePhotos @3 :Bool = true;
    fieldMapping @4 :T.StringMap;
}

struct FormatResult {
    union {
        success @0 :FormatSuccess;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct FormatSuccess {
    data @0 :T.DataHandle;
    warnings @1 :List(T.Warning);
}

# ─── vCard Data Model ─────────────────────────────────────────

struct VCard {
    version @0 :VCardVersion;
    # All properties (including custom).
    properties @1 :List(VCardProperty);
    # Raw lines for round-tripping unknown properties — the right
    # instinct, kept: an unknown property survives a round trip instead
    # of being dropped.
    rawLines @2 :List(Text);
}

# ── VCard Value ────────────────────────────────────────────────

struct VCardValue {
    union {
        text @0 :Text;
        structured @1 :VCardStructuredValue;
        binary @2 :Data;
        uri @3 :T.Uri;
        date @4 :T.Timestamp;
        boolean @5 :Bool;
        integer @6 :Int64;
        float @7 :Float64;
        custom @8 :Data;
    }
}

struct VCardProperty {
    # Property name (e.g., "FN", "N", "EMAIL", "TEL", "ADR", "PHOTO").
    name @0 :Text;
    # Property group (e.g., "item1", "work").
    group @1 :Text;
    # Parameters (e.g., TYPE=HOME, ENCODING=BASE64) — the open key/value
    # mechanism that replaces the frozen TYPE enums.
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
    bday @23 :T.Date;
    anniversary @24 :T.Date;
    caladruri @25 :List(T.Uri);
    caluri @26 :List(T.Uri);
    fburl @27 :List(T.Uri);

    # Gender (RFC 6350 Section 6.2.5): an open token plus the free text
    # the RFC also carries. The `none`/`undefined` pair is deleted — two
    # values that both mean "not stated", an implementer trap with no
    # protocol value.
    gender @28 :Text;

    # Expertise, Hobby, Interest (RFC 6350 Section 6.7): one open level
    # vocabulary, replacing three enums with different scales
    # (5/3/3 levels) that a consumer could not compare and an
    # implementer had to convert between.
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
    # Pronunciation format, as an open token (see the consts below).
    pronunciationFormat @3 :Text;
}

# Address, email, telephone and IM all carry their TYPE parameters as
# open Text lists — one spelling for four paths. Previously only the
# address and email paths were open; the telephone path carried a frozen
# 1998 enum on top of the same list.
struct VCardAddress {
    # TYPE parameters, open tokens.
    types @0 :List(Text);
    preferred @1 :Bool;
    # Components: PO Box, Extended Address, Street, City, Region, Postal Code, Country
    components @2 :List(Text);
    geo @3 :T.Uri;
    tz @4 :Text;
}

struct VCardTelephone {
    types @0 :List(Text);
    preferred @1 :Bool;
    value @2 :Text;  # E.164 format recommended
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
    tag @0 :T.Language;  # BCP 47 tag
    preferred @1 :Bool;
}

struct VCardGeo {
    uri @0 :T.Uri;  # geo: URI
    lat @1 :Float64;
    lon @2 :Float64;
    altitude @3 :Float64;
}

struct VCardTimezone {
    # TZID
    id @0 :Text;
    # UTC offset, as a T.Duration from UTC — a typed offset instead of a
    # string that every backend re-parses.
    offset @1 :T.Duration;
    # VTIMEZONE data, preserved verbatim for round-tripping.
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
    # The media type IS the key type: PGP, X509 and SSH are all
    # distinguishable by it, so the closed KeyType enum (which named
    # `pgp`, a product name, and could not carry a 2046 format) is
    # deleted in favour of the field that already existed.
    mediaType @1 :T.MimeType;
    uri @2 :T.Uri;
}

# ─── RFC 6350 Section 6.7 — Expertise, Hobby, Interest ──────

struct VCardExpertise {
    domain @0 :Text;        # e.g., "programming", "cooking"
    level @1 :Text;
    description @2 :Text;
}

struct VCardHobby {
    domain @0 :Text;
    level @1 :Text;
    description @2 :Text;
}

struct VCardInterest {
    domain @0 :Text;
    level @1 :Text;
    description @2 :Text;
}

# ─── RFC 6350 Section 6.8 — XML Property ────────────────────

struct VCardXml {
    namespace @0 :Text;
    # A payload, not an opaque token, so it travels as a handle.
    content @1 :T.DataHandle;
    metadata @2 :T.StringMap;
}

# ─── Property Info ──────────────────────────────────────────
# What remains of the registry half: a caller can still ask what the
# backend claims to support, as data. The six-type schema-description
# apparatus is deleted — RFC 6350 is readable by any consumer.

struct VCardPropertyInfo {
    name @0 :Text;
    description @1 :Text;
    versions @2 :List(VCardVersion);
    cardinality @3 :Cardinality;
    valueType @4 :ValueType;
    parameters @5 :List(Text);
}

enum Cardinality {
    unspecified @0;   # Sentinel: an unset value is not the @0 paradigm
    single @1;
    multi @2;
    optional @3;
}

enum ValueType {
    unspecified @0;   # Sentinel: an unset value is not the @0 paradigm
    text @1;
    structured @2;
    binary @3;
    uri @4;
    dateTime @5;
    custom @6;
}

# ─── vCard Sync ──────────────────────────────────────────────

struct VCardSyncResult {
    newSyncToken @0 :Text;
    changed @1 :List(VCard);
    deleted @2 :List(T.ContactId);
    hasMore @3 :Bool;
    conflicts @4 :List(VCardSyncConflict);
}

struct VCardSyncConflict {
    conflictId @0 :Text;
    contactId @1 :T.ContactId;
    localVersion @2 :VCard;
    remoteVersion @3 :VCard;
    detectedAt @4 :T.Timestamp;
}

# ══════════════════════════════════════════════════════════════════════
# CONFORMANCE TOKENS — conventions, NOT contract
#
# Today's spellings for the open tokens above (the TYPE parameters, the
# level vocabulary, the pronunciation formats). Nothing requires them;
# an unrecognized token MUST be preserved verbatim on round-trip and
# ignored by a consumer that does not understand it — which is what
# makes a 2046 property parameter lossless.
# ══════════════════════════════════════════════════════════════════════

const typeHome :Text = "home";
const typeWork :Text = "work";
const typeCell :Text = "cell";
const typeFax  :Text = "fax";
const typePref :Text = "pref";

const levelBeginner :Text = "beginner";
const levelAverage  :Text = "average";
const levelGood     :Text = "good";
const levelExpert   :Text = "expert";
const levelMaster   :Text = "master";
const levelLow      :Text = "low";
const levelMedium   :Text = "medium";
const levelHigh     :Text = "high";

const pronunciationIpa   :Text = "ipa";
const pronunciationXsampa :Text = "x-sampa";
