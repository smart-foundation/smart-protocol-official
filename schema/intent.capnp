@0xa1b2c3d4e5f60056;

# ═══════════════════════════════════════════════════════════════════════
# Intent - component activation and dispatch.
#
# Improvements beyond the original schema (audit):
#   - LaunchFlags typed struct (not raw UInt32 bitmap).
#   - IntentCategory enum replaces Text categories.
#   - IntentExtras typed struct (no flat StringMap collision).
#   - DispatchType enum for explicit vs implicit dispatch.
#   - ComponentInfo.priority for ranking multiple handlers.
#   - UriPattern supports wildcards properly.
#   - IntentFilter for multi-criteria resolution.
#   - cancelActivity returns reason.
#
# Improvements (audit-3):
#   - resolve, resolveWithFilter, listHandlers paginated with T.Pagination (Rule 9).
#   - cancelActivity.reason changed from Text to T.Error (Rule 5).
#   - ComponentInfo.icon changed from Text to T.DataHandle (Rule 6).
#
# Improvements (audit-5):
#   - ComponentInfo.name changed from bare Text to T.ComponentName (Rule 2).
#   - Intent.component changed from bare Text to T.ComponentName (Rule 2).
#   - IntentService.unregisterHandler componentName changed to T.ComponentName (Rule 2).
#
# Improvements (audit-6):
#   - cancelActivity return type changed from (ok, reason) to T.VoidResult (Rule 5).
#
# Improvements (audit-7):
#   - Intent chaining / workflow (IntentChain, IntentStep, ChainState).
#   - Intent recording for automation (IntentRecording, RecordingTrigger).
#   - Intent replay for testing/debugging (IntentReplayRequest/Result).
#   - Intent history for analytics (IntentHistoryEntry, IntentHistoryFilter).
#   - Intent debug tracing (IntentTrace, IntentResolution, TraceStep).
#   - Intent attestation for security (IntentAttestation, AttestationResult).
#   - Intent metrics for monitoring (IntentMetrics, IntentActionMetrics).
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

# ── Intent ──────────────────────────────────────────────────────────────

struct Intent {
    action @0 :Text;
    dataUri @1 :Text;
    mimeType @2 :Text;
    component @3 :T.ComponentName;
    extras @4 :IntentExtras;
    flags @5 :LaunchFlags;
    categories @6 :List(IntentCategory);
    dispatchType @7 :DispatchType = unspecified;
    # Audit-9: intent priority (higher = more urgent).
    priority @8 :IntentPriority;
    # Audit-9: intent timeout (null = use system default).
    timeout @9 :T.Duration;
    # Audit-9: retry policy for failed intents.
    retry @10 :IntentRetryPolicy;
    # Audit-9: deduplication key (null = deduplicate all matching intents).
    dedupKey @11 :Text;
}

# Audit-9: intent priority level.
enum IntentPriority {
    lowest @0;
    low @1;
    normal @2;
    high @3;
    highest @4;
    custom @5;
}

# Audit-9: retry policy for failed intents.
struct IntentRetryPolicy {
    enabled @0 :Bool;
    maxAttempts @1 :UInt8;
    backoffMultiplier @2 :Float32;
    initialDelayMs @3 :UInt32;
}

# ── Launch flags (typed, not raw bitmap) ────────────────────────────────

struct LaunchFlags {
    newTask @0 :Bool;
    singleTop @1 :Bool;
    newDocument @2 :Bool;
    clearTop @3 :Bool;
    clearTask @4 :Bool;
    clearWhenTaskReset @5 :Bool;
    excludeFromRecents @6 :Bool;
    fromHistory @7 :Bool;
    foreground @8 :Bool;
    multipleTask @9 :Bool;
    grantReadUriPermission @10 :Bool;
    grantWriteUriPermission @11 :Bool;
    grantPersistableUriPermission @12 :Bool;
    # Force the intent to be treated as exclusive to this caller.
    exclusive @13 :Bool;
}

# ── Categories ───────────────────────────────────────────────────────────

enum IntentCategory {
    default @0;
    browsable @1;
    view @2;
    edit @3;
    pick @4;
    send @5;
    receive @6;
    main @7;
    launcher @8;
    home @9;
    preference @10;
    browserCategory @11;
    alternative @12;
    custom @13;
}

# ── Dispatch type ───────────────────────────────────────────────────────

enum DispatchType {
    # Dispatcher decides based on intent contents.
    unspecified @0;
    # Intent explicitly names a target component.
    explicit @1;
    # Intent describes action/data, dispatcher finds target.
    implicit @2;
    custom @3;
}

# ── Extras ──────────────────────────────────────────────────────────────

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
        # Base64-encoded binary data.
        data @5 :Data;
        # Serialized Cap'n Proto message.
        capnp @6 :Data;
    }
}

# ── Component ────────────────────────────────────────────────────────────

struct ComponentInfo {
    name @0 :T.ComponentName;
    label @1 :Text;
    # Icon as inline small data or buffer reference for large icons.
    icon @2 :T.DataHandle;
    actions @3 :List(Text);
    mimeTypes @4 :List(Text);
    uriPatterns @5 :List(UriPattern);
    categories @6 :List(IntentCategory);
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
    mimeType @4 :Text;
}

# ── Intent Filter (for resolution) ──────────────────────────────────────

struct IntentFilter {
    actions @0 :List(Text);
    categories @1 :List(IntentCategory);
    mimeTypes @2 :List(Text);
    schemes @3 :List(Text);
    paths @4 :List(Text);
}

# ── Activity Result ─────────────────────────────────────────────────────

struct ActivityResult {
    resultCode @0 :ActivityResultCode;
    data @1 :Intent;
}

# Typed result code — replaces raw Int32 for forward compatibility.
enum ActivityResultCode {
    canceled @0;
    ok @1;
    firstUser @2;
    custom @3;
}

# ── Dispatch Mode ──────────────────────────────────────────────────────

enum DispatchMode {
    bestMatch @0;
    chooser @1;
    broadcast @2;
    custom @3;
}

# ── Service ─────────────────────────────────────────────────────────────

interface IntentService {
    resolve @0 (intent :Intent, page :T.Pagination) -> (components :List(ResolvedComponent));
    resolveWithFilter @9 (filter :IntentFilter, page :T.Pagination) -> (components :List(ResolvedComponent));

    startActivity @1 (intent :Intent, mode :DispatchMode) -> (handle :ActivityHandle);
    startService @2 (intent :Intent) -> (handle :ServiceHandle);
    sendBroadcast @3 (intent :Intent) -> T.VoidResult;

    waitForResult @4 (handle :ActivityHandle) -> (result :ActivityResult);
    cancelActivity @5 (handle :ActivityHandle) -> T.VoidResult;

    registerHandler @6 (component :ComponentInfo) -> T.VoidResult;
    unregisterHandler @7 (componentName :T.ComponentName) -> T.VoidResult;
    listHandlers @8 (action :Text, mimeType :Text, page :T.Pagination) -> (components :List(ComponentInfo));

    # ── Audit-7 additions ────────────────────────────────────

    # Record an intent workflow for later replay.
    recordIntent @10 (recording :IntentRecording) -> (recordingId :Text);

    # Replay a recorded intent workflow.
    replayIntent @11 (request :IntentReplayRequest) -> (result :IntentReplayResult);

    # Query intent history with filtering.
    getHistory @12 (filter :IntentHistoryFilter, pagination :T.Pagination) -> (entries :List(IntentHistoryEntry));

    # Debug trace an intent dispatch (resolve, dispatch, result).
    traceIntent @13 (intent :Intent) -> (trace :IntentTrace);

    # Verify intent authenticity and integrity.
    attestIntent @14 (attestation :IntentAttestation) -> (result :AttestationResult);

    # Get dispatch metrics for monitoring.
    getMetrics @15 () -> (metrics :IntentMetrics);

    # Execute a chained workflow of intents.
    executeChain @16 (chain :IntentChain) -> (chainId :Text);

    # Get the status of a running chain.
    getChainStatus @17 (chainId :Text) -> (chain :IntentChain);

    # Cancel a running chain.
    cancelChain @18 (chainId :Text) -> T.VoidResult;

    # Audit-9: dispatch a batch of intents.
    dispatchBatch @19 (batch :IntentBatch) -> (result :IntentBatchResult);

    # Audit-10: record a cross-app activity workflow for replay.
    recordActivity @20 (recording :ActivityRecording) -> (recordingId :Text);

    # Audit-10: replay a recorded cross-app activity workflow.
    replayActivity @21 (request :ActivityReplayRequest) -> (result :ActivityReplayResult);

    # Audit-10: list recorded cross-app activity workflows.
    listActivityRecordings @22 (pagination :T.Pagination)
                           -> (recordings :List(ActivityRecording), totalCount :UInt32);

    # Audit-10: delete a recorded activity workflow.
    deleteActivityRecording @23 (recordingId :Text) -> T.VoidResult;
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

# ── Intent Chaining / Workflow (audit-7) ─────────────────────

struct IntentChain {
    # Unique chain identifier.
    id @0 :Text;
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

struct IntentCondition {
    # Intent field name to check.
    field @0 :Text;
    operator @1 :ConditionOp;
    # Value to compare against.
    value @2 :Text;
}

enum ConditionOp {
    equals @0;
    notEquals @1;
    contains @2;
    exists @3;
    notExists @4;
    custom @5;
}

# ── Intent Recording (audit-7) ───────────────────────────────

struct IntentRecording {
    # Unique recording identifier.
    id @0 :Text;
    # Human-readable recording name.
    name @1 :Text;
    # Description of what this recording does.
    description @2 :Text;
    # Ordered steps in the recording.
    steps @3 :List(IntentStep);
    # When this recording was created.
    createdAt @4 :T.Timestamp;
    # Total duration of the recording.
    duration @5 :T.Duration;
    # How this recording was triggered.
    trigger @6 :RecordingTrigger;
}

enum RecordingTrigger {
    manual @0;
    shortcut @1;
    voice @2;
    gesture @3;
    schedule @4;
    custom @5;
}

# ── Intent Replay (audit-7) ──────────────────────────────────

struct IntentReplayRequest {
    # Recording to replay.
    recordingId @0 :Text;
    # Override parameters for the replay.
    parameters @1 :T.StringMap;
    # Replay speed (1.0 = normal, 2.0 = double speed).
    speed @2 :Float32;
    # Validate without executing.
    dryRun @3 :Bool;
}

struct IntentReplayResult {
    # Whether the replay completed successfully.
    success @0 :Bool;
    # Number of steps executed.
    stepsExecuted @1 :UInt32;
    # Total steps in the recording.
    stepsTotal @2 :UInt32;
    # Total replay duration.
    duration @3 :T.Duration;
    # Errors encountered during replay.
    errors @4 :List(IntentReplayError);
}

struct IntentReplayError {
    # Step index where the error occurred.
    step @0 :UInt32;
    # Error description.
    reason @1 :T.Error;
    # The intent that failed.
    intent @2 :Intent;
}

# ── Intent History (audit-7) ─────────────────────────────────

struct IntentHistoryEntry {
    # Unique history entry identifier.
    id @0 :Text;
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

# ── Intent Debug Trace (audit-7) ─────────────────────────────

struct IntentTrace {
    # Unique trace identifier.
    id @0 :Text;
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
    # Input data for this step.
    input @3 :Data;
    # Output data from this step.
    output @4 :Data;
    # Whether this step succeeded.
    success @5 :Bool;
    # Error if this step failed.
    error @6 :T.Error;
}

# ── Intent Attestation (audit-7) ─────────────────────────────

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
    # Signature algorithm (e.g., "ed25519", "rsa-pss-sha256").
    algorithm @5 :Text;
}

struct AttestationResult {
    # Whether the attestation is valid.
    valid @0 :Bool;
    # Reason if invalid.
    reason @1 :Text;
    # When the verification was performed.
    verifiedAt @2 :T.Timestamp;
}

# ── Intent Metrics (audit-7) ─────────────────────────────────

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

# ── Audit-9: Intent Batching ─────────────────────────────────

# Audit-9: a batch of intents for bulk dispatch.
struct IntentBatch {
    id @0 :Text;
    intents @1 :List(Intent);
    # How to handle partial failure.
    failureMode @2 :BatchFailureMode;
}

enum BatchFailureMode {
    # All intents must succeed.
    allOrNothing @0;
    # Continue on failure; collect errors.
    continueOnFailure @1;
    # Stop at first failure.
    stopOnFirst @2;
    custom @3;
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

# ── Audit-9: Intent Access Control ──────────────────────────

struct IntentAccessPolicy {
    caller @0 :T.ComponentName;
    allowedActions @1 :List(Text);
    deniedActions @2 :List(Text);
    maxPerMinute @3 :UInt32;
}

interface IntentAccessService {
    checkAccess @0 (caller :T.ComponentName, intent :Intent) -> (allowed :Bool, reason :Text);
    setPolicy @1 (policy :IntentAccessPolicy) -> T.VoidResult;
    getPolicy @2 (caller :T.ComponentName) -> (policy :IntentAccessPolicy);
    listPolicies @3 (pagination :T.Pagination) -> (policies :List(IntentAccessPolicy));
}

# ── Audit-10: Cross-App Activity Replay ──────────────────────

# Audit-10: recorded cross-app activity workflow (multi-app sequence).
struct ActivityRecording {
    id @0 :Text;
    name @1 :Text;
    description @2 :Text;
    # Ordered steps across multiple apps.
    steps @3 :List(ActivityStep);
    # When this recording was created.
    createdAt @4 :T.Timestamp;
    # Total duration of the recording.
    duration @5 :T.Duration;
    # Apps involved in this recording.
    apps @6 :List(T.AppId);
}

# Audit-10: a single step in a cross-app activity.
struct ActivityStep {
    # The intent to dispatch.
    intent @0 :Intent;
    # The app that handled this step.
    app @1 :T.AppId;
    # Expected conditions before this step.
    preconditions @2 :List(IntentCondition);
    # Expected conditions after this step.
    postconditions @3 :List(IntentCondition);
    # Maximum time to wait for this step.
    timeout @4 :T.Duration;
    # Whether to skip this step if the previous step failed.
    skipOnError @5 :Bool;
}

# Audit-10: request to replay a recorded activity.
struct ActivityReplayRequest {
    recordingId @0 :Text;
    # Override parameters for the replay (key-value).
    parameters @1 :T.StringMap;
    # Replay speed (1.0 = normal, 2.0 = double speed).
    speed @2 :Float32;
    # Validate without executing.
    dryRun @3 :Bool;
    # Start from a specific step index (0-based).
    startStep @4 :UInt32;
}

# Audit-10: result of replaying a recorded activity.
struct ActivityReplayResult {
    success @0 :Bool;
    stepsExecuted @1 :UInt32;
    stepsTotal @2 :UInt32;
    duration @3 :T.Duration;
    errors @4 :List(ActivityReplayError);
}

# Audit-10: error encountered during activity replay.
struct ActivityReplayError {
    step @0 :UInt32;
    intent @1 :Intent;
    app @2 :T.AppId;
    error @3 :T.Error;
}
