@0xa1b2c3d4e5f60029;

# ═══════════════════════════════════════════════════════════════════════
# Contacts — address book management. Backend-agnostic: works with
# system contact stores, vCard databases, LDAP, or IPC services.
#
# The zero-cost posture of this file is exemplary and is kept: photos,
# import and export are all T.DataHandle; sub-entry ids use the promoted
# T.EmailEntryId/T.PhoneEntryId/T.AddressEntryId; birthdays use T.Date;
# every list method is paginated.
#
# ── THE SHARE HOLE ────────────────────────────────────────────────────
#
# `shareContact` copied a person's data to an arbitrary user id with no
# capability, no consent check and no authority — in a file that also
# defines its own consent machinery. Any holder of the reference could
# leak any contact to any user. The privacy-critical surface (share,
# presence, history, relations, identity linking, bulk mutation and
# consent) now sits behind one accessor that takes a Capability, and
# `shareContact` additionally requires a consent record covering the
# `sharing` scope for the target contact: a backend MUST refuse with
# T.Error(permissionDenied) when no such record exists. The file's
# privacy machinery is now binding instead of decorative.
#
# ── VOCABULARIES THAT GROW ARE OPEN ───────────────────────────────────
#
# ContactType, EmailType, PhoneType, AddressType, RelationType,
# SearchMode, ContactRankingType and ConsentScope were closed enums.
# PhoneType already contained `pager` — a dead technology frozen as a
# permanent ordinal with nothing replacing it — and ConsentScope could
# not express a 2046 jurisdiction's "profiling", "automated decision" or
# "cross-border transfer", so `recordConsent` could not record a lawful
# refusal. All eight are open tokens with published spellings.
#
# SearchMode also collided by NAME with content.capnp's SearchMode at
# divergent values (prefix/fuzzy/exact/semantic vs
# fullText/prefix/fuzzy/semantic); both are open tokens sharing one
# published vocabulary now.
#
# ── ONE AVAILABILITY CONTRACT ─────────────────────────────────────────
#
# `getFreeBusy` duplicated calendar.capnp's `queryFreeBusy` with a
# different request shape and a different result type, and its local
# FreeBusyStatus was value-identical to calendar's misnamed
# FreeBusyPrivacy — three names for one concept. The duplicate is
# deleted; calendar.queryFreeBusy is the canonical availability
# contract.
#
# ── ONE PAGINATION MODEL ──────────────────────────────────────────────
#
# ContactsSubscription and PresenceSubscription had unbounded pulls
# with a `cancel` but no terminator. Both gain a `pullPage` (the pattern
# runtime_search.capnp:531 and calendar.capnp:116 already use); the
# unbounded `pull` is documented as deprecated rather than silently
# changed.
#
# Improvements (audit-7/9), unchanged:
#   - All IDs typed (T.ContactId / T.GroupId), sub-entry ids dedicated.
#   - listContacts/searchContacts/getStarred/accept T.Pagination.
#   - Contact.photo uses T.DataHandle; Contact.groups uses List(T.GroupId).
#   - ContactFilter.groups enables multi-group filtering (OR semantics).
#   - ContactFilter.starred uses T.BoolFilter.
#   - Contact.birthday uses T.Date.
#   - ContactConsent for GDPR/privacy compliance.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using import "capability.capnp".Capability;

# ── Root: ungated address-book surface ────────────────────────────────

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

    # ── Merge / Dedup ──────────────────────────────────────
    findDuplicates @12 (pagination :T.Pagination) -> (duplicates :List(DuplicateCandidate));
    mergePreview @13 (request :ContactMergeRequest) -> (merged :Contact);
    mergeContacts @14 (request :ContactMergeRequest) -> T.VoidResult;

    # ── Lookup ─────────────────────────────────────────────
    getContactByField @15 (fieldType :ContactFieldType, fieldValue :Text) -> (contact :Contact);
    getRecentContacts @16 (pagination :T.Pagination) -> (contacts :List(Contact));
    # Smart contact suggestions. `context` is an open token (see
    # conformance consts); previously a bare Text whose vocabulary was
    # undeclared, so two backends produced unrelated results for the
    # same call.
    getSuggestions @17 (context :Text, pagination :T.Pagination) -> (contacts :List(Contact));

    # ── Accessibility / Ranking ────────────────────────────
    getAccessibilityMetadata @18 (contactId :T.ContactId) -> (metadata :ContactAccessibilityMetadata);
    searchContactsRanked @19 (query :Text, pagination :T.Pagination) -> (results :List(RankedContactResult));
    getContactRanking @20 (rankingType :Text, pagination :T.Pagination) -> (results :List(RankedContactResult));

    # ── Gated once, at acquisition ──────────────────────────────────
    # Presence, history, relationships, identity linking, bulk mutation,
    # sharing and consent are personal-data operations. Holding
    # `service` IS the authority; no method inside takes an authority
    # token.
    privacy @21 (authority :Capability) -> (service :ContactPrivacy);
}

# ── Privileged surface: obtained with a Capability ──────────────────────

interface ContactPrivacy {
    # Query real-time availability for one or more contacts.
    getPresence @0 (contactIds :List(T.ContactId)) -> (presences :List(ContactPresence));

    # Subscribe to presence changes.
    subscribePresence @1 () -> (subscription :PresenceSubscription);

    # Query relationships for a contact.
    getRelations @2 (contactId :T.ContactId) -> (relations :List(ContactRelation));

    # Full change history for a contact (edit log, merge history).
    getContactHistory @3 (contactId :T.ContactId, pagination :T.Pagination)
        -> (entries :List(ContactHistoryEntry));

    # Share a contact with another user. Requires a ContactConsent
    # record covering the `sharing` scope for this contact; the backend
    # MUST refuse with T.Error(permissionDenied) when none exists.
    # Previously ungated and unconsented, so any holder of the
    # reference could leak any contact to any user id.
    shareContact @4 (contactId :T.ContactId, targetUserId :T.UserId) -> T.VoidResult;

    # Bulk operations on another party's data.
    batchUpdate @5 (updates :List(BatchContactUpdate)) -> T.VoidResult;
    batchDelete @6 (contactIds :List(T.ContactId)) -> T.VoidResult;

    # Consent lifecycle.
    recordConsent @7 (contactId :T.ContactId, consent :ContactConsent) -> T.VoidResult;
    revokeConsent @8 (contactId :T.ContactId, consentScope :Text) -> T.VoidResult;
    getConsentStatus @9 (contactId :T.ContactId) -> (consents :List(ContactConsent));

    # Cross-provider identity correlation.
    linkContacts @10 (primaryId :T.ContactId, linkedIds :List(T.ContactId)) -> T.VoidResult;
    getLinkedIdentities @11 (contactId :T.ContactId) -> (links :List(ContactIdentityLink));
}

interface ContactsSubscription {
    # DEPRECATED: use pullPage. An unbounded pull on a long-lived
    # subscription exhausts consumer memory.
    pull @0 () -> (contacts :List(Contact));
    # Explicitly cancel this subscription and release resources.
    cancel @1 () -> T.VoidResult;
    # Bounded pull for large histories.
    pullPage @2 (pagination :T.Pagination) -> (contacts :List(Contact), total :UInt64);
}

interface PresenceSubscription {
    # DEPRECATED: use pullPage.
    pull @0 () -> (presences :List(ContactPresence));
    cancel @1 () -> T.VoidResult;
    # Bounded pull for large histories.
    pullPage @2 (pagination :T.Pagination) -> (presences :List(ContactPresence), total :UInt64);
}

# ── Contact ───────────────────────────────────────────────────

struct Contact {
    id @0 :T.ContactId;
    name @1 :PersonName;
    emails @2 :List(EmailEntry);
    phones @3 :List(PhoneEntry);
    addresses @4 :List(AddressEntry);
    photo @5 :T.DataHandle;
    starred @6 :Bool;
    groups @7 :List(T.GroupId);
    note @8 :Text;
    birthday @9 :T.Date;
    created @10 :T.Timestamp;
    modified @11 :T.Timestamp;
    metadata @12 :T.StringMap;

    # ── Audit-7 additions ────────────────────────────────────
    # Entity type, as an open token.
    type @13 :Text;
    organization @14 :OrganizationName;
    socialProfiles @15 :List(SocialProfile);
    tags @16 :List(Text);
    customFields @17 :List(CustomField);
    photoMetadata @18 :ContactPhotoMetadata;
    # IANA timezone name (e.g., "America/New_York").
    timezone @19 :Text;
    lifecycleStatus @20 :ContactLifecycleStatus;
    consent @21 :List(ContactConsent);

    # Optimistic-concurrency guard. Previously absent, so two writers
    # silently overwrote each other and last-write-wins versus merge was
    # decided per backend.
    version @22 :UInt64;
}

# Lifecycle is closed by the lifecycle itself, not by a technology
# snapshot. `stale` has no declared threshold because staleness is a
# backend policy; a consumer reads `modified` to apply its own.
enum ContactLifecycleStatus {
    unspecified @0;   # Sentinel: an unset status is not "active"
    active @1;
    stale @2;
    archived @3;
    custom @4;
}

struct OrganizationName {
    name @0 :Text;
    department @1 :Text;
    role @2 :Text;
    industry @3 :Text;
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
    id @0 :T.EmailEntryId;
    # Open token; see the email-type conformance consts below.
    type @1 :Text;
    value @2 :Text;
    primary @3 :Bool;
}

# ── Phone ─────────────────────────────────────────────────────

struct PhoneEntry {
    id @0 :T.PhoneEntryId;
    # Open token; see the phone-type conformance consts below.
    type @1 :Text;
    value @2 :Text;
    primary @3 :Bool;
}

# ── Address ───────────────────────────────────────────────────

struct AddressEntry {
    id @0 :T.AddressEntryId;
    # Open token; see the address-type conformance consts below.
    type @1 :Text;
    street @2 :Text;
    city @3 :Text;
    region @4 :Text;
    postalCode @5 :Text;
    country @6 :Text;
    primary @7 :Bool;
}

# ── Groups ────────────────────────────────────────────────────

struct ContactGroup {
    id @0 :T.GroupId;
    name @1 :Text;
    contactCount @2 :UInt32;
    rules @3 :List(GroupRule);
    description @4 :Text;
    isDynamic @5 :Bool;
}

struct GroupRule {
    # Contact field name to match against (e.g., "type", "tags", "emails.value").
    field @0 :Text;
    operator @1 :GroupRuleOperator;
    value @2 :Text;
}

# Closed by the matching semantics, not by a technology snapshot.
enum GroupRuleOperator {
    unspecified @0;   # Sentinel: an unset operator is not "equals"
    equals @1;
    contains @2;
    startsWith @3;
    regex @4;
    inList @5;
    custom @6;
}

# ── Presence ──────────────────────────────────────────────────

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
    lastSeen @2 :T.Timestamp;
    # Device or service reporting this presence (e.g., "phone", "desktop").
    device @3 :Text;
}

# ── Social Profile ───────────────────────────────────────────

struct SocialProfile {
    platform @0 :Text;
    handle @1 :Text;
    url @2 :T.Uri;
    verified @3 :Bool;
}

# ── Contact Graph ────────────────────────────────────────────

struct ContactRelation {
    targetId @0 :T.ContactId;
    # Open token; see the relation-type conformance consts below.
    relation @1 :Text;
    label @2 :Text;
    strength @3 :Float32;
}

# ── Custom Fields ────────────────────────────────────────────

struct CustomField {
    key @0 :Text;
    value @1 :T.MetaValue;
}

# ── Photo Metadata ───────────────────────────────────────────

struct ContactPhotoMetadata {
    width @0 :UInt32;
    height @1 :UInt32;
    # MIME type (e.g., "image/jpeg", "image/png").
    format @2 :T.MimeType;
    sizeBytes @3 :UInt64;
}

# ── Merge / Dedup ────────────────────────────────────────────

struct ContactMergeRequest {
    primaryId @0 :T.ContactId;
    duplicateIds @1 :List(T.ContactId);
    strategy @2 :ContactMergeStrategy;
}

# Closed by the merge semantics.
enum ContactMergeStrategy {
    unspecified @0;   # Sentinel: an unset strategy is not "keepPrimary"
    keepPrimary @1;
    keepNewest @2;
    mergeAll @3;
    custom @4;
}

struct DuplicateCandidate {
    contactId @0 :T.ContactId;
    score @1 :Float32;
    duplicateOf @2 :T.ContactId;
    # Which fields matched, as open tokens (see the field-type consts).
    matchedFields @3 :List(Text);
}

# ── Batch Operations ─────────────────────────────────────────

struct BatchContactUpdate {
    contactId @0 :T.ContactId;
    contact @1 :Contact;
}

# ── Field Lookup ─────────────────────────────────────────────

enum ContactFieldType {
    unspecified @0;   # Sentinel: an unset field type is not "email"
    email @1;
    phone @2;
    handle @3;
    custom @4;
}

# ── History ──────────────────────────────────────────────────

struct ContactHistoryEntry {
    timestamp @0 :T.Timestamp;
    action @1 :ContactHistoryAction;
    # Which field was changed, as an open token.
    field @2 :Text;
    oldValue @3 :Text;
    newValue @4 :Text;
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

# ── Filter ───────────────────────────────────────────────────

struct ContactFilter {
    query @0 :Text;
    group @1 :T.GroupId;
    # Filter by multiple groups (OR semantics — contacts in any listed group match).
    groups @2 :List(T.GroupId);
    starred @3 :T.BoolFilter;

    type @4 :Text;
    tags @5 :List(Text);
    hasPresence @6 :Bool;
    lastSeenAfter @7 :T.Timestamp;
    # Search strategy hint, as an open token (see the search-mode consts).
    searchMode @8 :Text;
    parameters @9 :T.StringMap;
}

# ── Accessibility Metadata ──────────────────────────────────
struct ContactAccessibilityMetadata {
    pronunciationHint @0 :Text;
    readingOrder @1 :Text;
    spellOut @2 :Bool;
    voiceHint @3 :Text;
    photoAltText @4 :Text;
}

# ── Contact Ranking ──────────────────────────────────────────

struct RankedContactResult {
    contact @0 :Contact;
    score @1 :Float32;
    rank @2 :UInt32;
    metricValue @3 :Float32;
    label @4 :Text;
}

# ── Cross-Provider Identity Linking ─────────────────────────
struct ContactIdentityLink {
    linkedContactId @0 :T.ContactId;
    # Provider type, as an open token (e.g., "email", "phone", "social").
    provider @1 :Text;
    providerId @2 :Text;
    confidence @3 :Float32;
    confirmed @4 :Bool;
    linkedAt @5 :T.Timestamp;
}

struct ContactConsent {
    consentedAt @0 :T.Timestamp;
    # What the consent covers, as an open token (see the consent-scope
    # consts). Open because a 2046 jurisdiction needs "profiling",
    # "automatedDecision" or "crossBorderTransfer" and a closed list
    # cannot record a lawful refusal.
    scope @1 :Text;
    expiresAt @2 :T.Timestamp;
    revokedAt @3 :T.Timestamp;
    recordedBy @4 :T.UserId;
}

# ══════════════════════════════════════════════════════════════════════
# CONFORMANCE TOKENS — conventions, NOT contract
#
# Today's spellings for the open tokens above. Nothing requires them; an
# unrecognized token MUST be ignored rather than rejected, so a 2046
# entity kind, relation, ranking basis or consent scope becomes nameable
# the day a backend ships it.
# ══════════════════════════════════════════════════════════════════════

const contactTypePerson       :Text = "person";
const contactTypeOrganization :Text = "organization";
const contactTypeTeam         :Text = "team";
const contactTypeService      :Text = "service";
const contactTypeBot          :Text = "bot";

const emailTypeHome  :Text = "home";
const emailTypeWork  :Text = "work";
const emailTypeOther :Text = "other";

const phoneTypeMobile :Text = "mobile";
const phoneTypeHome   :Text = "home";
const phoneTypeWork   :Text = "work";
const phoneTypeFax    :Text = "fax";
const phoneTypeOther  :Text = "other";

const addressTypeHome  :Text = "home";
const addressTypeWork  :Text = "work";
const addressTypeOther :Text = "other";

const relationWorksWith :Text = "works-with";
const relationManages   :Text = "manages";
const relationRelatedTo :Text = "related-to";
const relationReportsTo :Text = "reports-to";
const relationOther     :Text = "other";

const searchModePrefix    :Text = "prefix";
const searchModeFuzzy     :Text = "fuzzy";
const searchModeExact     :Text = "exact";
const searchModeSemantic  :Text = "semantic";
const searchModeFullText  :Text = "full-text";

const rankingMostContacted      :Text = "most-contacted";
const rankingRecentlyContacted  :Text = "recently-contacted";
const rankingVip                :Text = "vip";
const rankingFrequent           :Text = "frequent";
const rankingRecent             :Text = "recent";

const consentStorage   :Text = "storage";
const consentSharing   :Text = "sharing";
const consentAnalytics :Text = "analytics";
const consentMarketing :Text = "marketing";
const consentAll       :Text = "all";

const suggestionContextCompose :Text = "compose";
const suggestionContextShare   :Text = "share";
const suggestionContextSearch  :Text = "search";
