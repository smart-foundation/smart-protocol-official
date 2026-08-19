@0xa1b2c3d4e5f60029;

# ═══════════════════════════════════════════════════════════════════════
# Contacts — address book management. Backend-agnostic: works with
# system contact stores, vCard databases, LDAP, or IPC services.
#
# Improvements:
#   - All IDs use typed T.ContactId / T.GroupId (not raw Text).
#   - Sub-entry IDs use dedicated T.EmailEntryId, T.PhoneEntryId,
#     T.AddressEntryId (not T.ContactId — semantically distinct).
#   - listContacts/searchContacts/getStarred accept T.Pagination
#     for bounded results.
#   - listGroups accepts T.Pagination for bounded results (Rule 9).
#   - ContactFilter.groups enables multi-group filtering (OR semantics).
#   - Contact.photo uses T.DataHandle for large contact photos.
#   - Contact.groups uses List(T.GroupId) (typed references).
#   - ContactFilter.group uses T.GroupId.
#   - ContactFilter.starred uses T.BoolFilter (any/yes/no).
#   - Contact.birthday uses T.Date (date-only, not full timestamp).
#   - ContactsSubscription has cancel method for explicit teardown.
#   - All enums have custom variants for forward compatibility.
#
# Improvements (audit-7):
#   - ContactType enum for entity classification (person, org, team, etc.).
#   - OrganizationName struct for non-person contacts.
#   - Contact.type, Contact.organization for multi-entity support.
#   - DynamicGroup + GroupRule for rule-based smart groups.
#   - PresenceStatus + ContactPresence for real-time availability.
#   - ContactsService.getPresence/subscribePresence for presence.
#   - ContactMergeRequest + mergeContacts/findDuplicates for dedup.
#   - SocialProfile for social media links.
#   - ContactRelation + getRelations for contact graph.
#   - Contact.tags, Contact.customFields for extensibility.
#   - FreeBusyInfo + getFreeBusy for calendar availability.
#   - exportContacts/importContacts for format negotiation.
#   - ContactPhotoMetadata + Contact.photoMetadata for preview.
#   - getContactHistory for change log.
#   - batchUpdate/batchDelete/getContactByField/getRecentContacts/getSuggestions.
#   - ContactConsent + ConsentScope for GDPR/privacy compliance
#     (false positive from contact_privacy.capnp).
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

interface Contacts {
    listContacts @0 (filter :ContactFilter, pagination :T.Pagination) -> (contacts :List(Contact));
    getContact @1 (contactId :T.ContactId) -> (contact :Contact);
    searchContacts @2 (query :Text, pagination :T.Pagination) -> (contacts :List(Contact));
    getStarred @3 (pagination :T.Pagination) -> (contacts :List(Contact));

    listGroups @4 (pagination :T.Pagination) -> (groups :List(ContactGroup), total :UInt32);

    createContact @5 (contact :Contact) -> (contactId :T.ContactId);
    updateContact @6 (contactId :T.ContactId, contact :Contact) -> T.VoidResult;
    deleteContact @7 (contactId :T.ContactId) -> T.VoidResult;
    starContact @8 (contactId :T.ContactId, starred :Bool) -> T.VoidResult;

    addToGroup @9 (contactId :T.ContactId, groupId :T.GroupId) -> T.VoidResult;
    removeFromGroup @10 (contactId :T.ContactId, groupId :T.GroupId) -> T.VoidResult;

    subscribeContacts @11 () -> (subscription :ContactsSubscription);

    # ── Presence (audit-7) ───────────────────────────────────
    # Query real-time availability for one or more contacts.
    getPresence @12 (contactIds :List(T.ContactId)) -> (presences :List(ContactPresence));

    # Subscribe to presence changes (real-time updates).
    subscribePresence @13 () -> (subscription :PresenceSubscription);

    # ── Merge / Dedup (audit-7) ──────────────────────────────
    # Execute a merge of duplicate contacts.
    mergeContacts @14 (request :ContactMergeRequest) -> T.VoidResult;

    # Find potential duplicate contacts (paginated).
    findDuplicates @15 (pagination :T.Pagination) -> (duplicates :List(DuplicateCandidate));

    # Preview a merge without executing it.
    mergePreview @16 (request :ContactMergeRequest) -> (merged :Contact);

    # ── Relationships (audit-7) ──────────────────────────────
    # Query relationships for a contact.
    getRelations @17 (contactId :T.ContactId) -> (relations :List(ContactRelation));

    # ── Free/Busy (audit-7) ──────────────────────────────────
    # Query calendar availability for contacts (respects privacy).
    getFreeBusy @18 (contactIds :List(T.ContactId), range :TimeRange) -> (infos :List(FreeBusyInfo));

    # ── Import/Export (audit-7) ───────────────────────────────
    # Export contacts in specified format (vCard, JSON, CSV).
    exportContacts @19 (format :Text, contactIds :List(T.ContactId)) -> (data :T.DataHandle);

    # Import contacts from specified format.
    importContacts @20 (format :Text, data :T.DataHandle) -> (imported :UInt32, warnings :List(T.Warning));

    # ── History (audit-7) ────────────────────────────────────
    # Full change history for a contact (edit log, merge history).
    getContactHistory @21 (contactId :T.ContactId, pagination :T.Pagination) -> (entries :List(ContactHistoryEntry));

    # ── Sharing (audit-7) ────────────────────────────────────
    # Encrypted contact sharing between devices/users.
    shareContact @22 (contactId :T.ContactId, targetUserId :T.UserId) -> T.VoidResult;

    # ── Batch Operations (audit-7) ───────────────────────────
    # Update multiple contacts in a single operation.
    batchUpdate @23 (updates :List(BatchContactUpdate)) -> T.VoidResult;

    # Delete multiple contacts in a single operation.
    batchDelete @24 (contactIds :List(T.ContactId)) -> T.VoidResult;

    # ── Lookup (audit-7) ─────────────────────────────────────
    # Look up a contact by email, phone, or handle (reverse lookup).
    getContactByField @25 (fieldType :ContactFieldType, fieldValue :Text) -> (contact :Contact);

    # Recently contacted / most-contacted list (paginated).
    getRecentContacts @26 (pagination :T.Pagination) -> (contacts :List(Contact));

    # Smart contact suggestions based on context.
    getSuggestions @27 (context :Text, pagination :T.Pagination) -> (contacts :List(Contact));

    # ── Consent / Privacy (false positive: contact_privacy) ───
    # Record consent for storing/processing this contact.
    recordConsent @28 (contactId :T.ContactId, consent :ContactConsent) -> T.VoidResult;

    # Revoke previously granted consent.
    revokeConsent @29 (contactId :T.ContactId, consentScope :ConsentScope) -> T.VoidResult;

    # Query consent status for a contact.
    getConsentStatus @30 (contactId :T.ContactId) -> (consents :List(ContactConsent));

    # ── Audit-9: Accessibility / Ranking / Linking ───────────────

    # Get accessibility metadata for a contact (pronunciation, reading order).
    getAccessibilityMetadata @31 (contactId :T.ContactId) -> (metadata :ContactAccessibilityMetadata);

    # Search contacts with relevance ranking.
    searchContactsRanked @32 (query :Text, pagination :T.Pagination) -> (results :List(RankedContactResult));

    # Get contact scoring/ranking (most contacted, VIP, etc.).
    getContactRanking @33 (rankingType :ContactRankingType, pagination :T.Pagination) -> (results :List(RankedContactResult));

    # Link contacts across providers (same person, different accounts).
    linkContacts @34 (primaryId :T.ContactId, linkedIds :List(T.ContactId)) -> T.VoidResult;

    # Get linked identities for a contact.
    getLinkedIdentities @35 (contactId :T.ContactId) -> (links :List(ContactIdentityLink));
}

interface ContactsSubscription {
    pull @0 () -> (contacts :List(Contact));

    # Explicitly cancel this subscription and release resources.
    cancel @1 () -> T.VoidResult;
}

interface PresenceSubscription {
    pull @0 () -> (presences :List(ContactPresence));
    cancel @1 () -> T.VoidResult;
}

# ── Contact ───────────────────────────────────────────────────

struct Contact {
    id @0 :T.ContactId;
    name @1 :PersonName;
    emails @2 :List(EmailEntry);
    phones @3 :List(PhoneEntry);
    addresses @4 :List(AddressEntry);
    # Inline for small photos; use buffer reference for large/high-res photos.
    photo @5 :T.DataHandle;
    starred @6 :Bool;
    groups @7 :List(T.GroupId);
    note @8 :Text;
    # Date-only birthday (no time-of-day precision).
    birthday @9 :T.Date;
    created @10 :T.Timestamp;
    modified @11 :T.Timestamp;
    metadata @12 :T.StringMap;

    # ── Audit-7 additions ────────────────────────────────────
    # Entity type (person, organization, team, etc.)
    type @13 :ContactType;
    # Organization name (for non-person contacts).
    organization @14 :OrganizationName;
    # Social media profile links.
    socialProfiles @15 :List(SocialProfile);
    # User-defined tags beyond groups.
    tags @16 :List(Text);
    # Structured extensible custom fields.
    customFields @17 :List(CustomField);
    # Photo metadata for preview/display decisions.
    photoMetadata @18 :ContactPhotoMetadata;
    # IANA timezone name (e.g., "America/New_York").
    timezone @19 :Text;
    # Contact lifecycle (active, stale, archived).
    lifecycleStatus @20 :ContactLifecycleStatus;
    # Consent records for GDPR/privacy compliance.
    consent @21 :List(ContactConsent);
}

# ── Entity Type (audit-7) ─────────────────────────────────────

enum ContactType {
    person @0;
    organization @1;
    team @2;
    service @3;
    bot @4;
    other @5;
    custom @6;
}

struct OrganizationName {
    name @0 :Text;
    department @1 :Text;
    role @2 :Text;
    industry @3 :Text;
}

# ── Lifecycle (audit-7) ───────────────────────────────────────

enum ContactLifecycleStatus {
    active @0;
    stale @1;
    archived @2;
    custom @3;
}

# ── Names ─────────────────────────────────────────────────────

struct PersonName {
    given @0 :Text;
    family @1 :Text;
    middle @2 :Text;
    prefix @3 :Text;
    suffix @4 :Text;
    display @5 :Text;
}

# ── Email ─────────────────────────────────────────────────────

struct EmailEntry {
    # Dedicated sub-entry ID (not T.ContactId — this is an email within a contact).
    id @0 :T.EmailEntryId;
    type @1 :EmailType;
    value @2 :Text;
    primary @3 :Bool;
}

enum EmailType {
    home @0;
    work @1;
    other @2;
    custom @3;
}

# ── Phone ─────────────────────────────────────────────────────

struct PhoneEntry {
    # Dedicated sub-entry ID (not T.ContactId — this is a phone within a contact).
    id @0 :T.PhoneEntryId;
    type @1 :PhoneType;
    value @2 :Text;
    primary @3 :Bool;
}

enum PhoneType {
    mobile @0;
    home @1;
    work @2;
    fax @3;
    pager @4;
    other @5;
    custom @6;
}

# ── Address ───────────────────────────────────────────────────

struct AddressEntry {
    # Dedicated sub-entry ID (not T.ContactId — this is an address within a contact).
    id @0 :T.AddressEntryId;
    type @1 :AddressType;
    street @2 :Text;
    city @3 :Text;
    region @4 :Text;
    postalCode @5 :Text;
    country @6 :Text;
    primary @7 :Bool;
}

enum AddressType {
    home @0;
    work @1;
    other @2;
    custom @3;
}

# ── Groups ────────────────────────────────────────────────────

struct ContactGroup {
    id @0 :T.GroupId;
    name @1 :Text;
    contactCount @2 :UInt32;
    # Rule-based filter criteria for dynamic/smart groups (audit-7).
    rules @3 :List(GroupRule);
    # Human-readable description of the group (audit-7).
    description @4 :Text;
    # Whether this is a rule-based dynamic group (audit-7).
    isDynamic @5 :Bool;
}

struct GroupRule {
    # Contact field name to match against (e.g., "type", "tags", "emails.value").
    field @0 :Text;
    operator @1 :GroupRuleOperator;
    # Value to compare against (interpretation depends on operator).
    value @2 :Text;
}

enum GroupRuleOperator {
    equals @0;
    contains @1;
    startsWith @2;
    regex @3;
    inList @4;
    custom @5;
}

# ── Presence (audit-7) ────────────────────────────────────────

enum PresenceStatus {
    unknown @0;
    available @1;
    busy @2;
    doNotDisturb @3;
    away @4;
    offline @5;
    custom @6;
}

struct ContactPresence {
    contactId @0 :T.ContactId;
    status @1 :PresenceStatus;
    # When this presence was last observed.
    lastSeen @2 :T.Timestamp;
    # Device or service reporting this presence (e.g., "phone", "desktop").
    device @3 :Text;
}

# ── Social Profile (audit-7) ──────────────────────────────────

struct SocialProfile {
    # Platform name (e.g., "github", "linkedin", "twitter", "mastodon").
    platform @0 :Text;
    # Handle or username on the platform.
    handle @1 :Text;
    # Profile URL.
    url @2 :T.Uri;
    # Whether this profile is verified.
    verified @3 :Bool;
}

# ── Contact Graph (audit-7) ───────────────────────────────────

struct ContactRelation {
    # The contact this relation points to.
    targetId @0 :T.ContactId;
    relation @1 :RelationType;
    # Human-readable label (e.g., "manager", "spouse").
    label @2 :Text;
    # Relationship strength for analytics (0.0 = weak, 1.0 = strong).
    strength @3 :Float32;
}

enum RelationType {
    worksWith @0;
    manages @1;
    relatedTo @2;
    reportsTo @3;
    other @4;
    custom @5;
}

# ── Custom Fields (audit-7) ───────────────────────────────────

struct CustomField {
    # Field key (e.g., "favorite_color", "assistant_name").
    key @0 :Text;
    # Typed value using existing T.MetaValue union.
    value @1 :T.MetaValue;
}

# ── Free/Busy (audit-7) ───────────────────────────────────────

struct FreeBusyInfo {
    contactId @0 :T.ContactId;
    status @1 :FreeBusyStatus;
    start @2 :T.Timestamp;
    end @3 :T.Timestamp;
    # Privacy level for this availability entry.
    privacy @4 :FreeBusyPrivacy;
}

enum FreeBusyStatus {
    free @0;
    busy @1;
    tentative @2;
    outOfOffice @3;
    custom @4;
}

enum FreeBusyPrivacy {
    public @0;
    contactsOnly @1;
    private @2;
    custom @3;
}

# ── Photo Metadata (audit-7) ──────────────────────────────────

struct ContactPhotoMetadata {
    width @0 :UInt32;
    height @1 :UInt32;
    # MIME type (e.g., "image/jpeg", "image/png").
    format @2 :Text;
    sizeBytes @3 :UInt64;
}

# ── Merge / Dedup (audit-7) ───────────────────────────────────

struct ContactMergeRequest {
    # The contact to keep as primary.
    primaryId @0 :T.ContactId;
    # Contacts to merge into primary.
    duplicateIds @1 :List(T.ContactId);
    # Strategy for resolving conflicts during merge.
    strategy @2 :MergeStrategy;
}

enum MergeStrategy {
    keepPrimary @0;
    keepNewest @1;
    mergeAll @2;
    custom @3;
}

struct DuplicateCandidate {
    # One of the potential duplicate contacts.
    contactId @0 :T.ContactId;
    # Similarity score (0.0 = no match, 1.0 = identical).
    score @1 :Float32;
    # The other contact this one may duplicate.
    duplicateOf @2 :T.ContactId;
    # Which fields matched (e.g., "email", "phone", "name").
    matchedFields @3 :List(Text);
}

# ── Batch Operations (audit-7) ────────────────────────────────

struct BatchContactUpdate {
    contactId @0 :T.ContactId;
    contact @1 :Contact;
}

# ── Field Lookup (audit-7) ────────────────────────────────────

enum ContactFieldType {
    email @0;
    phone @1;
    handle @2;
    custom @3;
}

# ── History (audit-7) ─────────────────────────────────────────

struct ContactHistoryEntry {
    # Timestamp of the change.
    timestamp @0 :T.Timestamp;
    # Type of action performed.
    action @1 :ContactHistoryAction;
    # Which field was changed (e.g., "name", "email", "phone").
    field @2 :Text;
    # Previous value (empty for creation).
    oldValue @3 :Text;
    # New value (empty for deletion).
    newValue @4 :Text;
    # User or system that performed the change.
    actor @5 :T.UserId;
}

enum ContactHistoryAction {
    created @0;
    updated @1;
    deleted @2;
    merged @3;
    restored @4;
    custom @5;
}

# ── Time Range (for free/busy queries) ────────────────────────

struct TimeRange {
    start @0 :T.Timestamp;
    end @1 :T.Timestamp;
}

# ── Filter ────────────────────────────────────────────────────

struct ContactFilter {
    query @0 :Text;
    group @1 :T.GroupId;
    # Filter by multiple groups (OR semantics — contacts in any listed group match).
    groups @2 :List(T.GroupId);
    # T.BoolFilter: any/yes/no — more expressive than bare Bool.
    starred @3 :T.BoolFilter;

    # ── Audit-7 additions ────────────────────────────────────
    # Filter by entity type (person, organization, etc.)
    type @4 :ContactType;
    # Filter by user-defined tags.
    tags @5 :List(Text);
    # Only contacts with presence data.
    hasPresence @6 :Bool;
    # Only contacts seen after this timestamp.
    lastSeenAfter @7 :T.Timestamp;
    # Search strategy hint (prefix, fuzzy, exact, semantic).
    searchMode @8 :SearchMode;
}

enum SearchMode {
    prefix @0;
    fuzzy @1;
    exact @2;
    semantic @3;
    custom @4;
}

# ── Consent / Privacy (false positive: contact_privacy) ───────
# Contact consent tracking for GDPR/privacy compliance.
# Right-to-erasure, data retention, and consent lifecycle
# management are features of contacts.capnp, not a new schema.

# ── Accessibility Metadata (audit-9) ────────────────────────
struct ContactAccessibilityMetadata {
    # Pronunciation hint for the contact name (IPA or phonetic).
    pronunciationHint @0 :Text;
    # Preferred reading order for screen readers (e.g., "given-family", "family-given").
    readingOrder @1 :Text;
    # Whether the name should be spelled out character-by-character.
    spellOut @2 :Bool;
    # Screen reader voice hint (e.g., "formal", "casual").
    voiceHint @3 :Text;
    # Alternative text for the contact photo.
    photoAltText @4 :Text;
}

# ── Contact Ranking (audit-9) ───────────────────────────────

enum ContactRankingType {
    mostContacted @0;
    recentlyContacted @1;
    vip @2;
    frequent @3;
    recent @4;
    custom @5;
}

struct RankedContactResult {
    # The contact.
    contact @0 :Contact;
    # Ranking score (higher = more relevant).
    score @1 :Float32;
    # Rank position (1-based).
    rank @2 :UInt32;
    # Ranking metric value (e.g., message count, last contact time).
    metricValue @3 :Float32;
    # Human-readable ranking label (e.g., "Most contacted", "VIP").
    label @4 :Text;
}

# ── Cross-Provider Identity Linking (audit-9) ───────────────

struct ContactIdentityLink {
    # The linked contact ID.
    linkedContactId @0 :T.ContactId;
    # Provider type (e.g., "email", "phone", "social", "enterprise").
    provider @1 :Text;
    # Provider-specific identifier.
    providerId @2 :Text;
    # Confidence score for the link (0.0 = uncertain, 1.0 = confirmed).
    confidence @3 :Float32;
    # Whether this link was user-confirmed.
    confirmed @4 :Bool;
    # When the link was established.
    linkedAt @5 :T.Timestamp;
}

struct ContactConsent {
    # When consent was granted.
    consentedAt @0 :T.Timestamp;
    # What the consent covers.
    scope @1 :ConsentScope;
    # When consent expires (zero = no expiration).
    expiresAt @2 :T.Timestamp;
    # When consent was revoked (zero = still active).
    revokedAt @3 :T.Timestamp;
    # User or system that recorded this consent.
    recordedBy @4 :T.UserId;
}

enum ConsentScope {
    storage @0;
    sharing @1;
    analytics @2;
    marketing @3;
    all @4;
    custom @5;
}
