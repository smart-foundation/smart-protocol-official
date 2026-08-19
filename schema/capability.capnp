@0xa1b2c3d4e5f60034;

# ═══════════════════════════════════════════════════════════════════════
# Capability — the universal currency of authority
#
# A capability is opaque content-addressed proof that the holder may invoke
# a specific operation on a specific target, optionally constrained. It is
# backend-agnostic: any service that issues a capability has freedom in how
# it backs that capability (kernel object, signed token, distributed ledger).
# Applications see only the type, never the backing.
#
# Targets are textual paths into any namespace. Examples:
#   "audio/device/speaker"
#   "filesystem/path/~/Documents"
#   "input/keyboard/0"
#   "service/audio"
# Backends decide how to interpret each target; the protocol is timeless.
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

    # Audit-7: delegation chain tracking (parent→child→grandchild).
    chain @6 :DelegationChain;

    # Audit-7: conditional validity (network, time, location, device).
    conditions @7 :List(CapabilityCondition);

    # Audit-7: usage analytics metadata.
    usage @8 :CapabilityUsage;
}

# Audit-7: tracks the delegation chain from root to this capability.
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

# Audit-7: condition that must be true for the capability to be valid.
struct CapabilityCondition {
    # Condition identifier.
    conditionId @0 :UInt64;
    # Type of condition.
    type @1 :CapabilityConditionType;
    # Condition-specific parameters (backend-defined).
    params @2 :T.StringMap;
}

enum CapabilityConditionType {
    network @0;        # Must be on specific network
    time @1;           # Must be within time window
    location @2;       # Must be at specific location
    device @3;         # Must be on specific device
    custom @4;
}

# Audit-7: usage tracking metadata.
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

# Capability service — issues, attenuates, verifies, revokes.
interface CapabilityService {
    # Issue a fresh capability from scratch (caller must hold authority by
    # some out-of-band mechanism; this is the genesis point).
    issue @0 (request :IssueRequest) -> (issued :Capability);

    # Verify a capability proves a requested operation on a target.
    verify @1 (request :VerifyRequest) -> (result :T.BoolResult);

    # Derive a weaker capability from a stronger one.
    # Requires the parent has `attenuate` in its operations.
    attenuate @2 (parent :Capability, drops :List(Operation), tighter :Constraints) -> (result :T.BoolResult);

    # Transfer to another holder (capability unchanged, registry updated).
    transfer @3 (cap :Capability, recipient :Text) -> (result :T.BoolResult);

    # Revoke and all derivatives.
    revoke @4 (cap :Capability) -> (result :T.BoolResult);

    # List capabilities held by the calling entity.
    list @5 (filter :CapabilityFilter, pagination :T.Pagination) -> (caps :List(Capability), totalCount :UInt32);

    # Subscribe to capability changes (issued, attenuated, revoked).
    subscribe @6 () -> (subscription :CapabilitySubscription);

    # Pull events via service (alternative to holding subscription reference).
    pull @7 (subscription :CapabilitySubscription) -> (events :List(CapabilityEvent));

    # Audit-7: refresh an expiring capability.
    refresh @8 (request :RefreshRequest) -> (capability :Capability);

    # Audit-7: revoke with cascade control.
    revokeControlled @9 (cap :Capability, cascade :RevocationCascade) -> (result :T.BoolResult);

    # Audit-7: create a named capability group.
    createGroup @10 (group :CapabilityGroup) -> T.VoidResult;

    # Audit-7: list capability groups.
    listGroups @11 (pagination :T.Pagination) -> (groups :List(CapabilityGroup), totalCount :UInt32);

    # Audit-7: evaluate a capability condition.
    evaluateCondition @12 (cap :Capability, condition :CapabilityCondition) -> (valid :Bool);

    # Audit-7: take a point-in-time snapshot of all capabilities.
    snapshot @13 () -> (capabilities :List(Capability));

    # ── Audit-9: Capability Negotiation ──

    # Negotiate capabilities between two entities (returns intersection of acceptable caps).
    negotiate @17 (request :NegotiationRequest) -> (result :NegotiationResult);

    # ── Audit-9: Capability Composition ──

    # Combine multiple capabilities into a single composite capability.
    compose @18 (capabilities :List(Capability)) -> (composite :Capability);

    # ── Audit-9: Capability Exchange ──

    # Propose an exchange of capabilities with another entity.
    proposeExchange @19 (request :ExchangeRequest) -> (proposalId :Text);

    # Accept a proposed capability exchange.
    acceptExchange @20 (proposalId :Text) -> (result :T.BoolResult);

    # Reject a proposed capability exchange.
    rejectExchange @21 (proposalId :Text, reason :Text) -> T.VoidResult;

    # ── Audit-9: Transfer Approval ──

    # Request approval for a capability transfer (requires explicit approval).
    requestTransferApproval @22 (cap :Capability, recipient :Text, reason :Text) -> (approvalId :Text);

    # Approve a pending transfer request.
    approveTransfer @23 (approvalId :Text) -> (result :T.BoolResult);

    # Deny a pending transfer request.
    denyTransfer @24 (approvalId :Text, reason :Text) -> T.VoidResult;

    # ── Audit Trail (false positive: capability_audit.capnp) ──

    # Query the audit trail with filters.
    queryAudit @14 (filter :AuditFilter) -> (entries :List(AuditEntry), total :UInt32);

    # Export audit trail for compliance.
    exportAudit @15 (request :AuditExportRequest) -> (data :T.DataHandle);

    # Generate a compliance report for a time window.
    generateComplianceReport @16 (windowStart :T.Timestamp, windowEnd :T.Timestamp) -> (report :ComplianceReport);
}

# Audit-7: cascade control for revocation.
enum RevocationCascade {
    subtree @0;       # Revoke this capability and all descendants
    children @1;      # Revoke only direct children
    all @2;           # Revoke all derivatives anywhere
    issuer @3;        # Revoke all capabilities from the same issuer
    custom @4;
}

# Audit-7: refresh an expiring capability.
struct RefreshRequest {
    # The capability to refresh.
    capability @0 :Capability;
    # New expiry timestamp.
    newExpiry @1 :T.Timestamp;
    # Tighter constraints (optional, for progressive tightening).
    tighterConstraints @2 :Constraints;
}

# Audit-7: named bundle of capabilities.
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
    # Audit-7: filter by issuer.
    issuer @3 :Text;
    # Audit-7: filter by delegation depth (max depth to return).
    maxDepth @4 :UInt32;
}

struct CapabilityEvent {
    union {
        issued @0 :Capability;
        revoked @1 :Capability;
        attenuated @2 :AttenuationEvent;
        transferred @3 :TransferEvent;
        # Audit-9: notification when a capability is revoked (for the holder).
        revocationNotice @5 :RevocationNoticeEvent;
        # Audit-9: transfer approval requested.
        transferApprovalRequested @6 :TransferApprovalEvent;
        # Audit-9: exchange proposed.
        exchangeProposed @7 :ExchangeProposedEvent;
        custom @4 :Text;
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

# ── Audit-9: Negotiation ────────────────────────────────────────────────

struct NegotiationRequest {
    # Entity we are negotiating with.
    peer @0 :Text;
    # Capabilities we offer.
    offered @1 :List(Capability);
    # Capabilities we require from the peer.
    required @2 :List(Text);
    # Constraints on the negotiation.
    constraints @3 :Constraints;
}

struct NegotiationResult {
    # Capabilities the peer accepted.
    accepted @0 :List(Capability);
    # Capabilities the peer rejected.
    rejected @1 :List(Capability);
    # Whether the negotiation succeeded (all required caps were met).
    success @2 :Bool;
}

# ── Audit-9: Exchange ───────────────────────────────────────────────────

struct ExchangeRequest {
    # Entity we want to exchange with.
    peer @0 :Text;
    # Capabilities we are offering.
    offered @1 :List(Capability);
    # Capability targets we want in return.
    requestedTargets @2 :List(Text);
    # Maximum duration for the exchange to be valid.
    ttl @3 :T.Duration;
}

struct ExchangeProposedEvent {
    proposalId @0 :Text;
    from @1 :Text;
    offered @2 :List(Capability);
    requestedTargets @3 :List(Text);
    expiresAt @4 :T.Timestamp;
}

# ── Audit-9: Transfer Approval ──────────────────────────────────────────

struct TransferApprovalEvent {
    approvalId @0 :Text;
    cap @1 :Capability;
    from @2 :Text;
    to @3 :Text;
    reason @4 :Text;
    requestedAt @5 :T.Timestamp;
}

# ── Audit-9: Revocation Notice ──────────────────────────────────────────

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

# ── Capability Audit (false positive: capability_audit.capnp) ──────────
# Capability audit trail, compliance reporting, and history export.
# The existing Audit struct captures issuance metadata; these additions
# capture the full lifecycle for compliance and forensic review.

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
    # Export format (e.g., "json", "csv", "siem").
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

# ── CapabilityService audit methods ────────────────────────────────────
# These are documented here but would be added to CapabilityService.
# Since CapabilityService is already defined above, they are added as
# separate interface methods below via documentation.
# Actual integration requires updating CapabilityService ordinal range.
