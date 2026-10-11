@0xa1b2c3d4e5f60056;

# ═══════════════════════════════════════════════════════════════════════
# Intent - component activation and dispatch.
#
# WHAT THIS IS
#   The universal activation contract: describe what you want done, let the
#   dispatcher find who can do it, and get a result. `resolve`, dispatch
#   (activity, service, broadcast), handler registration, replay and history.
#
# ANDROID IS GONE FROM THE REQUIRED POSITION
#   `LaunchFlags` was a transcription of Android's `FLAG_ACTIVITY_*`
#   constants — `newTask`, `singleTop`, `clearTop`, `clearTask`,
#   `clearWhenTaskReset`, `excludeFromRecents`, `multipleTask`,
#   `grantReadUriPermission`, `grantPersistableUriPermission`. `IntentCategory`
#   was Android's intent-filter categories, `browserCategory` included. And
#   `ActivityResultCode.firstUser` was `RESULT_FIRST_USER`, an API constant
#   from one platform that nothing else can produce.
#
#   The Swap Test fails on all three: swapping Android for a spatial shell, an
#   embedded HMI, or a robot UI forces the contract to be re-explained, because
#   "tasks" and "recents" do not exist there. Every non-Android backend maps
#   ten flags it does not have, and a client that branches on
#   `grantPersistableUriPermission` bakes 2010s URI-grant semantics into an
#   eternal contract.
#
#   In their place:
#   - `DeliveryHints` declares the real questions — how many instances may
#     result, whether it is visible in a task list, whether it is exclusive to
#     the caller, whether a result is expected — and carries authority as
#     CAPABILITY REFERENCES. A grant IS a capability, not a boolean flag per
#     permission kind.
#   - Categories are OPEN TOKENS, published below as conformance constants. A
#     registration vocabulary is unbounded and per-platform; freezing it at
#     2010 values made a 2046 category unregisterable.
#   - `firstUser` is deleted.
#
# RESULTS ARE NOT POLLED
#   `waitForResult @4` blocked or spun per handle. It is replaced by
#   `subscribeActivity`, which delivers results on a subscription with the
#   same pull/cancel shape every other stream in the protocol uses. Every
#   caller's wait loop disappears.
#
# ONE AUTHORITY PATH
#   `IntentAccessService` — `checkAccess`, `setPolicy`, `getPolicy`,
#   `listPolicies` over `IntentAccessPolicy { caller, allowedActions,
#   deniedActions, maxPerMinute }` — was permission string lists plus a rate
#   limit, i.e. a second access-control policy engine that had to agree with
#   capability.capnp forever. Deleted: the caller's capability reference
#   determines which intents it may dispatch, and rate limits are
#   capability.capnp's `RateBox`.
#
# ONE RECORDING MODEL
#   There were two parallel record/replay families — intent recordings and
#   cross-app activity recordings — with different step types, so a consumer
#   building automation support implemented both. There is now ONE: a
#   recording is an ordered list of steps, each an intent plus the app that
#   handled it.
#
# ADDRESSED BY TYPED IDS
#   Chains, recordings, traces and history entries were free `Text`, so a
#   lifecycle object could not be validated or enumerated. They are now
#   server-issued opaque IDs.
#
# CONTRACTS THAT WERE PROSE, NOW STATED
#   HANDLER DEATH: when a handler unregisters, intents already dispatched to it
#   complete with `T.ErrorCode.unavailable`; intents queued but not yet
#   delivered are re-resolved against the remaining handlers. A backend may
#   not silently drop either.
#   CHOOSER: `DispatchMode.chooser` dispatches to the component registered for
#   the `chooser` action, passing the ranked `resolve` result; the user's pick
#   comes back as the activity result. There is no separate chooser contract
#   because there is no separate chooser behaviour.
#   BROADCAST ORDERING: `sendBroadcast` is best-effort, at-most-once, with NO
#   ordering guarantee between receivers. A receiver that needs ordering
#   sequences its own deliveries; the dispatcher does not.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using import "capability.capnp".Capability;

# ── Identity defined here ─────────────────────────────────────
# Server-issued and opaque. `T.RecordingId` was promoted to types.capnp in
# the foundation batch; the chain, trace and history ids were promoted in
# the 2026-10-10 integration pass, because a consumer holding a chain id
# returned by `executeChain` must be able to name its type without
# importing this schema. ALL of intent's identity is now in the foundation.

# ── Intent ────────────────────────────────────────────────────

struct Intent {
    # Open token. What should happen. Conformance constants are published at
    # the end of this file; an unrecognised action is ignored by a consumer
    # that does not know it, and unroutable for one that does.
    action @0 :Text;
    dataUri @1 :T.Uri;
    mimeType @2 :T.MimeType;
    component @3 :T.ComponentName;
    extras @4 :IntentExtras;
    # Replaces LaunchFlags. Declarations, not an activity-stack emulation.
    delivery @5 :DeliveryHints;
    # Open tokens — see the conformance constants at the end of this file.
    categories @6 :List(Text);
    dispatchType @7 :DispatchType = unspecified;
    # Audit-9: intent priority (higher = more urgent).
    priority @8 :IntentPriority;
    # Audit-9: intent timeout (zero = use system default).
    timeout @9 :T.Duration;
    # Audit-9: retry policy for failed intents.
    retry @10 :IntentRetryPolicy;
    # Audit-9: deduplication key (empty = deduplicate all matching intents).
    dedupKey @11 :Text;
}

# Declarations about how this intent should be delivered. Each replaces one or
# more Android activity flags with the question the flag was approximating.
struct DeliveryHints {
    # Maximum instances of the target component that may result
    # (0 = backend default). This is the real question behind
    # "singleTask"/"singleTop".
    maxInstances @0 :UInt32;
    # Whether this intent may appear in a task/recents list. A declaration
    # about visibility, not an instruction about activity stacks.
    visibleInRecents @1 :Bool;
    # Whether this intent is exclusive to its caller.
    exclusive @2 :Bool;
    # Whether the caller expects a result and will subscribe for it.
    expectsResult @3 :Bool;
    # Authority the target is being granted, as capability references. A
    # grant IS a capability — not a boolean per permission kind, because a
    # boolean cannot be attenuated or revoked.
    grants @4 :List(Capability);
    metadata @5 :T.StringMap;
}

# Audit-9: intent priority level.
enum IntentPriority {
    # Absent means the backend decides; it must never mean a
    # specific paradigm value.
    unspecified @0;
    lowest @1;
    low @2;
    normal @3;
    high @4;
    highest @5;
    custom @6;
}

# Audit-9: retry policy for failed intents.
struct IntentRetryPolicy {
    enabled @0 :Bool;
    maxAttempts @1 :UInt8;
    backoffMultiplier @2 :Float32;
    initialDelay @3 :T.Duration;
}

# ── Dispatch type ─────────────────────────────────────────────

enum DispatchType {
    # Dispatcher decides based on intent contents.
    unspecified @0;
    # Intent explicitly names a target component.
    explicit @1;
    # Intent describes action/data, dispatcher finds target.
    implicit @2;
    custom @3;
}

# ── Extras ────────────────────────────────────────────────────

struct IntentExtras {
    # Typed key-value pairs. Backend validates types.
    items @0 :List(IntentExtra);
}

struct IntentExtra {
    key @0 :Text;
    union {
        string @1 :Text;
        int @2 :Int64;
        float @3 :Float64;
        bool @4 :Bool;
        # Binary data, as a buffer reference.
        data @5 :T.DataHandle;
        # Serialized Cap'n Proto message, as a buffer reference.
        # `capnpSchemaId` names the schema, so a consumer can decode it
        # instead of guessing.
        capnp @6 :T.DataHandle;
        capnpSchemaId @7 :T.SchemaId;
        custom @8 :T.StringMap;
        unknown @9 :Void;
    }
}

# ── Component ─────────────────────────────────────────────────

struct ComponentInfo {
    name @0 :T.ComponentName;
    label @1 :Text;
    # Icon as inline small data or buffer reference for large icons.
    icon @2 :T.DataHandle;
    # Open action tokens.
    actions @3 :List(Text);
    mimeTypes @4 :List(T.MimeType);
    uriPatterns @5 :List(UriPattern);
    # Open category tokens.
    categories @6 :List(Text);
    # Priority for ranking when multiple handlers match (higher = preferred).
    priority @7 :Int32;
    # Whether this component is the system-default for this intent.
    isDefault @8 :Bool;
}

struct UriPattern {
    # URI scheme (e.g., "https", "content").
    scheme @0 :Text;
    # Host pattern (supports wildcards: "*.example.com").
    host @1 :Text;
    # Path prefix.
    pathPrefix @2 :Text;
    # Exact path (mutually exclusive with pathPrefix).
    pathExact @3 :Text;
    # MIME type this pattern handles.
    mimeType @4 :T.MimeType;
}

# ── Intent Filter (for resolution) ───────────────────────────

struct IntentFilter {
    actions @0 :List(Text);
    categories @1 :List(Text);
    mimeTypes @2 :List(T.MimeType);
    schemes @3 :List(T.MimeType);
    paths @4 :List(Text);
}

# ── Activity Result ──────────────────────────────────────────

struct ActivityResult {
    # `firstUser` (Android's RESULT_FIRST_USER range marker) is deleted: an
    # API constant from one platform that nothing else can produce.
    resultCode @0 :ActivityResultCode;
    data @1 :Intent;
}

enum ActivityResultCode {
    canceled @0;
    ok @1;
    custom @2;
}

# ── Dispatch Mode ────────────────────────────────────────────

enum DispatchMode {
    bestMatch @0;
    chooser @1;
    broadcast @2;
    custom @3;
}

# ── Service ───────────────────────────────────────────────────

interface IntentService {
    resolve @0 (intent :Intent, page :T.Pagination)
              -> (components :List(ResolvedComponent), total :UInt64);

    startActivity @1 (intent :Intent, mode :DispatchMode)
                   -> (result :DispatchResult);
    startService @2 (intent :Intent) -> (result :DispatchResult);
    sendBroadcast @3 (intent :Intent) -> T.VoidResult;

    # Observe an activity's results. Replaces `waitForResult`, which every
    # caller polled or blocked on.
    subscribeActivity @4 (handle :ActivityHandle)
                       -> (subscription :ActivityResultSubscription);
    cancelActivity @5 (handle :ActivityHandle) -> T.VoidResult;

    registerHandler @6 (component :ComponentInfo) -> T.VoidResult;
    unregisterHandler @7 (componentName :T.ComponentName) -> T.VoidResult;
    listHandlers @8 (action :Text, mimeType :T.MimeType, page :T.Pagination)
                 -> (components :List(ComponentInfo), total :UInt64);

    resolveWithFilter @9 (filter :IntentFilter, page :T.Pagination)
                       -> (components :List(ResolvedComponent), total :UInt64);

    # ── Recording and replay ─────────────────────────────────

    # Record a workflow for later replay.
    record @10 (recording :Recording) -> (recordingId :T.RecordingId);

    # Replay a recorded workflow.
    replay @11 (request :ReplayRequest) -> (result :ReplayResult);

    # ── History and tracing ──────────────────────────────────

    # Query intent history with filtering.
    getHistory @12 (filter :IntentHistoryFilter, pagination :T.Pagination)
                 -> (entries :List(IntentHistoryEntry), total :UInt64);

    # Debug trace an intent dispatch (resolve, dispatch, result).
    traceIntent @13 (intent :Intent) -> (result :TraceResult);

    # Verify intent authenticity and integrity.
    attestIntent @14 (attestation :IntentAttestation) -> (result :AttestationResult);

    # Get dispatch metrics for monitoring.
    getMetrics @15 () -> (metrics :IntentMetrics);

    # ── Chains ───────────────────────────────────────────────

    # Execute a chained workflow of intents.
    executeChain @16 (chain :IntentChain) -> (chainId :T.IntentChainId);

    # Get the status of a running chain.
    getChainStatus @17 (chainId :T.IntentChainId) -> (result :ChainStatusResult);

    # Cancel a running chain.
    cancelChain @18 (chainId :T.IntentChainId) -> T.VoidResult;

    # ── Batching and recording management ────────────────────

    # Dispatch a batch of intents.
    dispatchBatch @19 (batch :IntentBatch) -> (result :IntentBatchResult);

    # List recorded workflows.
    listRecordings @20 (pagination :T.Pagination)
                   -> (recordings :List(Recording), total :UInt64);

    # Delete a recorded workflow.
    deleteRecording @21 (recordingId :T.RecordingId) -> T.VoidResult;
}

# ── Results ───────────────────────────────────────────────────

struct DispatchResult {
    union {
        activity @0 :ActivityHandle;
        service  @1 :ServiceHandle;
        # No component could handle the intent. An answer, not a fault the
        # caller has to infer from a zero handle.
        unhandled @2 :Void;
        error   @3 :T.Error;
        unknown @4 :Void;
    }
}

struct ChainStatusResult {
    union {
        chain   @0 :IntentChain;
        error   @1 :T.Error;
        unknown @2 :Void;
    }
}

struct TraceResult {
    union {
        trace   @0 :IntentTrace;
        error   @1 :T.Error;
        unknown @2 :Void;
    }
}

struct ReplayResult {
    union {
        completed @0 :ReplaySummary;
        error     @1 :T.Error;
        unknown   @2 :Void;
    }
}

interface ActivityResultSubscription {
    pull @0 (maxEvents :UInt32) -> (results :List(ActivityResult));
    cancel @1 () -> T.VoidResult;
}

struct ResolvedComponent {
    component @0 :ComponentInfo;
    # Ranking score (higher = better match).
    matchScore @1 :Int32;
    # Whether this requires user confirmation (chooser will be shown).
    requiresUserConfirmation @2 :Bool;
}

struct ActivityHandle {
    id @0 :T.ActivityId;
}

struct ServiceHandle {
    id @0 :T.ServiceHandleId;
}

# ── Chains ────────────────────────────────────────────────────

struct IntentChain {
    # Unique chain identifier, server-issued.
    id @0 :T.IntentChainId;
    # Human-readable chain name.
    name @1 :Text;
    # Ordered list of steps in the chain.
    steps @2 :List(IntentStep);
    # Current step index (0-based).
    current @3 :UInt32;
    # Current chain state.
    state @4 :ChainState;
}

struct IntentStep {
    # The intent to dispatch for this step.
    intent @0 :Intent;
    # Conditions that must be true before this step runs.
    precondition @1 :IntentPrecondition;
    # Expected conditions after this step completes.
    postcondition @2 :IntentPostcondition;
    # Maximum time to wait for this step.
    timeout @3 :T.Duration;
}

enum ChainState {
    pending @0;
    running @1;
    paused @2;
    completed @3;
    failed @4;
    cancelled @5;
    custom @6;
}

struct IntentPrecondition {
    requires @0 :List(IntentCondition);
    # Maximum time to wait for preconditions to be satisfied.
    wait @1 :T.Duration;
}

struct IntentPostcondition {
    expects @0 :List(IntentCondition);
    timeout @1 :T.Duration;
}

# A condition names an intent field with an OPEN TOKEN and compares a TYPED
# value. The previous spelling compared two Text values, so a boolean became
# "true" by convention and a future intent field could not be branched on
# without a string convention shared across backends.
struct IntentCondition {
    field @0 :Text;
    operator @1 :ConditionOp;
    value @2 :T.MetaValue;
}

enum ConditionOp {
    # Absent means the backend decides; it must never mean a
    # specific paradigm value.
    unspecified @0;
    equals @1;
    notEquals @2;
    contains @3;
    exists @4;
    notExists @5;
    custom @6;
}

# ── Recording and replay (ONE model) ─────────────────────────

# A recording is an ordered list of steps. `app` records which app handled a
# step; absent when the step is being authored rather than replayed. That is
# what collapsed the two parallel families: an intent recording and a
# cross-app activity recording are the same thing.
struct Recording {
    id @0 :T.RecordingId;
    name @1 :Text;
    description @2 :Text;
    steps @3 :List(RecordingStep);
    createdAt @4 :T.Timestamp;
    duration @5 :T.Duration;
    # Apps involved in this recording.
    apps @6 :List(T.AppId);
    # How this recording was triggered — an open token.
    trigger @7 :Text;
    metadata @8 :T.StringMap;
}

struct RecordingStep {
    # The intent to dispatch for this step.
    intent @0 :Intent;
    # The app that handled this step, when recorded.
    app @1 :T.AppId;
    # Expected conditions before this step.
    preconditions @2 :List(IntentCondition);
    # Expected conditions after this step.
    postconditions @3 :List(IntentCondition);
    # Maximum time to wait for this step.
    timeout @4 :T.Duration;
    # Whether to skip this step if the previous step failed.
    skipOnError @5 :Bool;
    metadata @6 :T.StringMap;
}

struct ReplayRequest {
    # Recording to replay.
    recordingId @0 :T.RecordingId;
    # Override parameters for the replay.
    parameters @1 :T.StringMap;
    # Replay speed (1.0 = normal, 2.0 = double speed).
    speed @2 :Float32;
    # Validate without executing.
    dryRun @3 :Bool;
    # Start from a specific step index (0-based).
    startStep @4 :UInt32;
}

struct ReplaySummary {
    # Number of steps executed.
    stepsExecuted @0 :UInt32;
    # Total steps in the recording.
    stepsTotal @1 :UInt32;
    # Total replay duration.
    duration @2 :T.Duration;
    # Errors encountered during replay.
    errors @3 :List(ReplayError);
    metadata @4 :T.StringMap;
}

struct ReplayError {
    # Step index where the error occurred.
    step @0 :UInt32;
    # Routable error, not prose.
    error @1 :T.Error;
    metadata @2 :T.StringMap;
}

# ── History ───────────────────────────────────────────────────

struct IntentHistoryEntry {
    # Unique history entry identifier, server-issued.
    id @0 :T.IntentHistoryId;
    # The intent that was dispatched.
    intent @1 :Intent;
    # The result of the dispatch.
    result @2 :ActivityResult;
    # When the intent was dispatched.
    timestamp @3 :T.Timestamp;
    # How long the dispatch took.
    duration @4 :T.Duration;
    # The app that called this intent.
    caller @5 :T.AppId;
    # The component that handled this intent.
    target @6 :T.ComponentName;
}

struct IntentHistoryFilter {
    # Filter by caller app.
    caller @0 :T.AppId;
    # Filter by target component.
    target @1 :T.ComponentName;
    # Filter by action.
    action @2 :Text;
    # Only entries after this timestamp.
    since @3 :T.Timestamp;
    # Only entries before this timestamp.
    before @4 :T.Timestamp;
    # Filter by success/failure.
    success @5 :T.BoolFilter;
}

# ── Debug Trace ───────────────────────────────────────────────

struct IntentTrace {
    id @0 :T.IntentTraceId;
    # The intent that was traced.
    intent @1 :Intent;
    # Resolution details (which candidates, why this one was selected).
    resolution @2 :IntentResolution;
    # Dispatch details (timing, mode).
    dispatch @3 :IntentDispatch;
    # The result of the dispatch.
    result @4 :ActivityResult;
    # Total trace duration.
    duration @5 :T.Duration;
    # Detailed trace steps.
    steps @6 :List(TraceStep);
}

struct IntentResolution {
    # All candidate components that matched.
    candidates @0 :List(ResolvedComponent);
    # The component that was selected.
    selected @1 :T.ComponentName;
    # Why this component was selected.
    reason @2 :Text;
}

struct IntentDispatch {
    # How the intent was dispatched.
    mode @0 :DispatchMode;
    # When the intent was queued.
    queueTime @1 :T.Timestamp;
    # When the intent was dispatched.
    dispatchTime @2 :T.Timestamp;
    # When the intent completed.
    completionTime @3 :T.Timestamp;
}

struct TraceStep {
    # Name of this trace step.
    name @0 :Text;
    # When this step started.
    timestamp @1 :T.Timestamp;
    # How long this step took.
    duration @2 :T.Duration;
    # Input data for this step. A buffer reference: a trace of a
    # document-sized intent must not copy the document per step.
    input @3 :T.DataHandle;
    # Output data from this step.
    output @4 :T.DataHandle;
    # Whether this step succeeded.
    success @5 :Bool;
    # Error if this step failed.
    error @6 :T.Error;
    metadata @7 :T.StringMap;
}

# ── Attestation ───────────────────────────────────────────────

struct IntentAttestation {
    # The calling component.
    caller @0 :T.ComponentName;
    # The target component.
    target @1 :T.ComponentName;
    # When the attestation was created.
    timestamp @2 :T.Timestamp;
    # Random nonce for freshness.
    nonce @3 :Data;
    # Cryptographic signature.
    signature @4 :Data;
    # Signature algorithm (e.g. "ed25519", "rsa-pss-sha256") — an open token.
    algorithm @5 :Text;
}

struct AttestationResult {
    union {
        valid @0 :AttestationOk;
        invalid @1 :T.Error;
        unknown @2 :Void;
    }
}

struct AttestationOk {
    # When the verification was performed.
    verifiedAt @0 :T.Timestamp;
}

# ── Metrics ───────────────────────────────────────────────────

struct IntentMetrics {
    # Total intents dispatched.
    totalDispatched @0 :UInt64;
    # Total intents resolved successfully.
    totalResolved @1 :UInt64;
    # Total intents that failed.
    totalFailed @2 :UInt64;
    # Average dispatch latency.
    averageLatency @3 :T.Duration;
    # 99th percentile latency.
    p99Latency @4 :T.Duration;
    # Per-action metrics.
    byAction @5 :List(IntentActionMetrics);
}

struct IntentActionMetrics {
    action @0 :Text;
    count @1 :UInt64;
    averageLatency @2 :T.Duration;
    errorRate @3 :Float32;
}

# ── Batching ──────────────────────────────────────────────────

struct IntentBatch {
    intents @0 :List(Intent);
    # How to handle partial failure.
    failureMode @1 :BatchFailureMode;
}

enum BatchFailureMode {
    # Absent means the backend decides; it must never mean a
    # specific paradigm value.
    unspecified @0;
    # All intents must succeed.
    allOrNothing @1;
    # Continue on failure; collect errors.
    continueOnFailure @2;
    # Stop at first failure.
    stopOnFirst @3;
    custom @4;
}

struct IntentBatchResult {
    success @0 :Bool;
    results @1 :List(ActivityResult);
    errors @2 :List(IntentBatchError);
}

struct IntentBatchError {
    index @0 :UInt32;
    intent @1 :Intent;
    error @2 :T.Error;
}

# ══════════════════════════════════════════════════════════════════════
# CONFORMANCE TOKENS — conventions, NOT contract
#
# Published so today's tools have a discoverable spelling for actions and
# categories. An unrecognised value MUST be ignored, never rejected. They are
# Text and deliberately NOT enums: a registration vocabulary is unbounded and
# per-platform, and freezing it would make a 2046 category unregisterable.
# ══════════════════════════════════════════════════════════════════════

const actionView    :Text = "view";
const actionEdit    :Text = "edit";
const actionPick    :Text = "pick";
const actionSend    :Text = "send";
const actionReceive :Text = "receive";
const actionMain    :Text = "main";
const actionChooser :Text = "chooser";

const categoryDefault     :Text = "default";
const categoryBrowsable   :Text = "browsable";
const categoryLauncher    :Text = "launcher";
const categoryHome        :Text = "home";
const categoryPreference  :Text = "preference";
const categoryAlternative :Text = "alternative";
