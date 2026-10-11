@0xa1b2c3d4e5f60034;

# ═══════════════════════════════════════════════════════════════════════
# Capability — the universal currency of authority
#
# A capability is opaque, content-addressed proof that the holder may
# invoke a specific operation on a specific target, optionally
# constrained. It is backend-agnostic: a service that issues a capability
# has freedom in how it backs that capability (kernel object, signed
# token, distributed ledger). Applications see only the type, never the
# backing.
#
# Targets are textual paths into any namespace. Examples:
#   "audio/device/speaker"
#   "filesystem/path/~/Documents"
#   "input/keyboard/0"
#   "service/audio"
# Backends decide how to interpret each target; the protocol is timeless.
#
# ── AUTHORITY IS THE REFERENCE ─────────────────────────────────────────
#
# In Cap'n Proto RPC a capability IS a reference: holding it conveys the
# authority to call it. So authority is expressed by WHICH REFERENCE A
# CALLER HOLDS, granted once at acquisition, and every method below takes
# no authority token. `schema/ai.capnp` is the reference implementation
# (validator rule E3); this file is the second half — it owns attenuation
# and revocation so that no service ever re-specifies them.
#
# The exception, stated so it is not mistaken for a violation: the five
# methods that take a `Capability` parameter (attenuate, transfer, revoke,
# revokeControlled, evaluateCondition) act ON the capability named by that
# parameter. The parameter is the object under manipulation, not an
# authority token. There is exactly one file in the protocol where that is
# true, and this is it.
#
# Delegation lives here too. Delegating a capability to another holder is
# `attenuate` (weaken: fewer operations, tighter constraints) followed by
# `transfer` (hand the reference over). `DelegationChain` records the
# parentage so a revoked root takes its derivatives with it. There is no
# delegation method in boot.capnp, kernel.capnp or anywhere else — that
# was the pre-revamp state and it was a second, unenforced authority
# grammar.
#
# ── WHAT WAS DELETED, AND WHY ──────────────────────────────────────────
#
# negotiate / compose / proposeExchange / acceptExchange / rejectExchange /
# requestTransferApproval / approveTransfer / denyTransfer: a capability
# market with human approval flows. None of it is needed to prove an
# operation on a target, all of it had to be implemented and kept
# consistent, and a 2046 system gains nothing from it. Attenuation and
# transfer, both typed and both error-honest, cover the real cases.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

struct Capability {
    # Opaque content-addressed identifier. Backend-specific binary token
    # (e.g., ed25519 signature, UUID, capability pointer). Kept as Data
    # because it is an opaque crypto token, not payload data — typically
    # 32-64 bytes, never exceeds 256 bytes.
    id @0 :Data;

    # Target this capability covers. Free-form textual address.
    # Resolution rules are backend-defined.
    target @1 :Text;

    # Operations granted.
    operations @2 :List(Operation);

    # Optional constraints.
    constraints @3 :Constraints;

    # Audit metadata.
    audit @4 :Audit;

    # When this capability expires (zero means never). Optional.
    expiry @5 :T.Timestamp;

    # Delegation chain tracking (parent→child→grandchild).
    chain @6 :DelegationChain;

    # Conditional validity. `type` is an OPEN token — network, time,
    # location and device are today's examples, not a closed list: a
    # condition invented in 2046 ("inside a trusted enclave") needs no
    # schema edit. Unrecognised condition types are ignored by consumers
    # and enforced by the backend that issued them.
    conditions @7 :List(CapabilityCondition);

    # Usage tracking metadata.
    usage @8 :CapabilityUsage;
}

# The delegation chain from root to this capability.
struct DelegationChain {
    # Root capability ID (the original issued capability).
    rootId @0 :Data;
    # Direct parent capability ID (the one this was attenuated from).
    parentId @1 :Data;
    # Depth from root (0 = root, 1 = direct child, etc.).
    depth @2 :UInt32;
    # Full chain of parent IDs from root to immediate parent.
    ancestors @3 :List(Data);
}

# A condition that must be true for the capability to be valid.
struct CapabilityCondition {
    # Condition identifier.
    conditionId @0 :UInt64;
    # Open condition token (e.g. "network", "time", "location", "device").
    type @1 :Text;
    # Condition-specific parameters (backend-defined).
    params @2 :T.StringMap;
}

# Usage tracking metadata.
struct CapabilityUsage {
    # Total number of times this capability has been used.
    useCount @0 :UInt64;
    # When this capability was last used.
    lastUsedAt @1 :T.Timestamp;
    # Which entities used this capability.
    usedBy @2 :List(Text);
    # Maximum allowed uses (0 = unlimited).
    maxUses @3 :UInt64;
    # Maximum number of delegation levels (0 = unlimited).
    maxDelegationDepth @4 :UInt32;
}

# The authority algebra. Closed because it is a grammar, not a fashion:
# a holder reads, writes, executes, subscribes, publishes, creates,
# destroys, attenuates, transfers and revokes — and `custom` carries a
# verb a backend needs that is not in this list. New values do not need
# to be added here to be usable: the field is an open list of tokens on
# the wire.
enum Operation {
    read @0;
    write @1;
    execute @2;
    subscribe @3;
    publish @4;
    create @5;
    destroy @6;
    attenuate @7;
    transfer @8;
    revoke @9;
    custom @10;
}

struct Constraints {
    # Bounded time window (zero pair = unbounded).
    timeBox @0 :TimeBox;
    # Bounded rate budget (zero pair = unbounded).
    rateBox @1 :RateBox;
    # Path prefix the capability is scoped to (filesystem-style targets).
    pathPrefix @2 :Text;
    # Whether the capability is fungible across peer entities.
    shareable @3 :Bool = true;
    # Whether the holder can attenuate further.
    attenuatable @4 :Bool = true;
}

struct TimeBox {
    start @0 :T.Timestamp;   # Zero = since issue
    end @1 :T.Timestamp;     # Zero = until revoked
}

struct RateBox {
    # Maximum operations per window.
    maxOps @0 :UInt32;
    # Duration of the rate window.
    window @1 :T.Duration;
}

struct Audit {
    # Who issued this capability (service name, entity identifier).
    # Empty for self-minted capabilities.
    issuer @0 :Text;
    # Sequence number from issuer (monotonic per issuer).
    sequence @1 :UInt64;
    # Wall-clock issuance time.
    issuedAt @2 :T.Timestamp;
    # Optional cryptographic proof of issuance.
    # Backend-specific: ed25519, rsa, raw hmac, etc.
    # Kept as Data because it is an opaque crypto proof, not payload data.
    proof @3 :Data;
}

# ── The authority service ───────────────────────────────────────────────
# This is the root of the authority domain: like `AI` in ai.capnp it is
# handed to the caller by the host, so it is deliberately not returned by
# any method. Every interface below it is.
#
# `verify` returns T.BoolResult, which distinguishes "denied" from
# "un-enforceable" only through the Error code — a backend that cannot
# honour a constraint MUST say so with a non-permissionDenied code rather
# than answering `false` for two different reasons.

interface CapabilityService {
    # Issue a fresh capability from scratch (caller must hold authority by
    # some out-of-band mechanism; this is the genesis point).
    issue @0 (request :IssueRequest) -> (issued :Capability);

    # Verify a capability proves a requested operation on a target.
    verify @1 (request :VerifyRequest) -> (result :T.BoolResult);

    # Derive a weaker capability from a stronger one.
    # Requires the parent has `attenuate` in its operations — the
    # precondition is stated here and enforced by the backend, exactly
    # like every other precondition in this file.
    attenuate @2 (parent :Capability, drops :List(Operation), tighter :Constraints) -> (result :T.BoolResult);

    # Transfer to another holder (capability unchanged, registry updated).
    transfer @3 (cap :Capability, recipient :Text) -> (result :T.BoolResult);

    # Revoke and all derivatives.
    revoke @4 (cap :Capability) -> (result :T.BoolResult);

    # List capabilities held by the calling entity.
    list @5 (filter :CapabilityFilter, pagination :T.Pagination) -> (caps :List(Capability), totalCount :UInt32);

    # Subscribe to capability changes (issued, attenuated, revoked).
    # Holding the returned subscription IS the authority to pull.
    subscribe @6 () -> (subscription :CapabilitySubscription);

    # Refresh an expiring capability.
    refresh @7 (request :RefreshRequest) -> (capability :Capability);

    # Revoke with cascade control.
    revokeControlled @8 (cap :Capability, cascade :RevocationCascade) -> (result :T.BoolResult);

    # Create a named capability group.
    createGroup @9 (group :CapabilityGroup) -> T.VoidResult;

    # List capability groups.
    listGroups @10 (pagination :T.Pagination) -> (groups :List(CapabilityGroup), totalCount :UInt32);

    # Evaluate a capability condition.
    evaluateCondition @11 (cap :Capability, condition :CapabilityCondition) -> (valid :Bool);

    # Take a point-in-time snapshot of all capabilities.
    snapshot @12 () -> (capabilities :List(Capability));

    # Query the audit trail with filters.
    queryAudit @13 (filter :AuditFilter) -> (entries :List(AuditEntry), total :UInt32);

    # Export audit trail for compliance.
    exportAudit @14 (request :AuditExportRequest) -> (data :T.DataHandle);

    # Generate a compliance report for a time window.
    generateComplianceReport @15 (windowStart :T.Timestamp, windowEnd :T.Timestamp) -> (report :ComplianceReport);
}

# Cascade control for revocation.
enum RevocationCascade {
    subtree @0;       # Revoke this capability and all descendants
    children @1;      # Revoke only direct children
    all @2;           # Revoke all derivatives anywhere
    issuer @3;        # Revoke all capabilities from the same issuer
    custom @4;
}

# Refresh an expiring capability.
struct RefreshRequest {
    # The capability to refresh.
    capability @0 :Capability;
    # New expiry timestamp.
    newExpiry @1 :T.Timestamp;
    # Tighter constraints (optional, for progressive tightening).
    tighterConstraints @2 :Constraints;
}

# Named bundle of capabilities.
struct CapabilityGroup {
    # Human-readable group name (e.g. "standard-app", "admin").
    name @0 :Text;
    # Capabilities in this group.
    capabilities @1 :List(Capability);
    # Description of what this group grants.
    description @2 :Text;
    # Whether the group can be shared with other entities.
    shareable @3 :Bool;
}

struct IssueRequest {
    target @0 :Text;
    operations @1 :List(Operation);
    constraints @2 :Constraints;
    # Recipient entity identifier (service name, user ID, node ID).
    # Backend interprets based on its identity model.
    recipient @3 :Text;
    proof @4 :Data;
}

struct VerifyRequest {
    cap @0 :Capability;
    operation @1 :Operation;
    target @2 :Text;
}

struct CapabilityFilter {
    targetPrefix @0 :Text;
    operations @1 :List(Operation);
    onlyActive @2 :Bool = true;
    # Filter by issuer.
    issuer @3 :Text;
    # Filter by delegation depth (max depth to return).
    maxDepth @4 :UInt32;
}

# `unknown @0 :T.UnknownEvent` is the R7 terminator (TIMELESSNESS.md:98):
# a backend forwards an event kind this schema does not name, with its
# discriminant and payload intact, instead of squeezing it into a string.
struct CapabilityEvent {
    union {
        issued @0 :Capability;
        revoked @1 :Capability;
        attenuated @2 :AttenuationEvent;
        transferred @3 :TransferEvent;
        # Notification when a capability is revoked (for the holder).
        revocationNotice @4 :RevocationNoticeEvent;
        unknown @5 :T.UnknownEvent;
    }
}

struct AttenuationEvent {
    parent @0 :Capability;
    derived @1 :Capability;
    droppedOps @2 :List(Operation);
}

struct TransferEvent {
    cap @0 :Capability;
    from @1 :Text;
    to @2 :Text;
}

struct RevocationNoticeEvent {
    # The capability that was revoked.
    cap @0 :Capability;
    # Who revoked it.
    revokedBy @1 :Text;
    # Reason for revocation.
    reason @2 :Text;
    # When the revocation occurred.
    timestamp @3 :T.Timestamp;
    # Whether all derivatives were also revoked.
    cascadeApplied @4 :Bool;
}

# One pull path only: hold the subscription reference and pull from it.
# The pre-revamp `CapabilityService.pull (subscription)` was a second
# identity path for the same subscription — the two-authority-paths
# anti-pattern (DESIGN_PRINCIPLES.md:394-396).
interface CapabilitySubscription {
    # Deprecated: use pullPaginated for bounded results.
    pull @0 () -> (events :List(CapabilityEvent));
    cancel @1 () -> T.VoidResult;
    # Paginated pull — returns at most `limit` events starting from `offset`.
    pullPaginated @2 (pagination :T.Pagination) -> (result :CapabilityPullResult);
}

struct CapabilityPullResult {
    events    @0 :List(CapabilityEvent);
    totalCount @1 :UInt32;
}

# ── Capability Audit ────────────────────────────────────────────────────
# The full lifecycle for compliance and forensic review. `Audit` above
# captures issuance metadata; this captures everything that happened to a
# capability afterwards.

struct AuditEntry {
    # Unique audit identifier.
    auditId @0 :UInt64;
    # When the auditable event occurred.
    timestamp @1 :T.Timestamp;
    # The capability this entry relates to.
    capabilityId @2 :Data;
    # Type of auditable event.
    eventType @3 :AuditEventType;
    # Who initiated the action (entity identifier).
    actor @4 :Text;
    # Optional target entity (e.g., recipient of a transfer).
    target @5 :Text;
    # Free-form human-readable description of the event.
    description @6 :Text;
    # Structured key-value metadata for the event.
    metadata @7 :T.StringMap;
    # Cryptographic proof of the event (optional).
    proof @8 :Data;
}

enum AuditEventType {
    issued @0;
    attenuated @1;
    transferred @2;
    revoked @3;
    refreshed @4;
    verified @5;
    conditionChecked @6;
    groupCreated @7;
    groupModified @8;
    snapshotTaken @9;
    custom @10;
}

struct AuditFilter {
    # Filter identifier.
    filterId @0 :UInt64;
    # Only events after this timestamp.
    since @1 :T.Timestamp;
    # Only events before this timestamp.
    until @2 :T.Timestamp;
    # Filter by event type.
    eventTypes @3 :List(AuditEventType);
    # Filter by actor.
    actor @4 :Text;
    # Filter by capability ID prefix.
    capabilityPrefix @5 :Data;
    # Pagination.
    pagination @6 :T.Pagination;
}

struct AuditExportRequest {
    # Export format (e.g., "json", "csv", "siem") — open token.
    format @0 :Text;
    # Filter for the export window.
    filter @1 :AuditFilter;
    # Whether to include proof fields in the export.
    includeProofs @2 :Bool;
}

struct ComplianceReport {
    # Time window this report covers.
    windowStart @0 :T.Timestamp;
    windowEnd @1 :T.Timestamp;
    # Total capabilities active during this window.
    totalCapabilities @2 :UInt32;
    # Capabilities issued during this window.
    issuedCount @3 :UInt32;
    # Capabilities revoked during this window.
    revokedCount @4 :UInt32;
    # Capabilities transferred during this window.
    transferredCount @5 :UInt32;
    # Average delegation depth.
    avgDelegationDepth @6 :Float32;
    # Number of expired capabilities.
    expiredCount @7 :UInt32;
    # Compliance status.
    status @8 :ComplianceStatus;
    # Non-compliance findings.
    findings @9 :List(ComplianceFinding);
}

enum ComplianceStatus {
    compliant @0;
    nonCompliant @1;
    partial @2;
    unknown @3;
    custom @4;
}

struct ComplianceFinding {
    # Severity of the finding.
    severity @0 :ComplianceSeverity;
    # Description of the finding.
    description @1 :Text;
    # The capability or group that triggered the finding.
    target @2 :Text;
    # Recommended remediation.
    recommendation @3 :Text;
}

enum ComplianceSeverity {
    info @0;
    warning @1;
    critical @2;
    custom @3;
}
