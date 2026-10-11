@0xa1b2c3d4e5f6003d;

# ═══════════════════════════════════════════════════════════════════════
# Device — universal device-tree / hardware topology.
#
# The catalog of devices known to the system and their relationships.
# Apps and drivers query this tree to discover what is available, which
# driver owns it, and how to talk to it. The tree is backend-decided
# (ACPI tables, devicetree blob, kernel enumeration, remote device
# registry - any source). The protocol is timeless.
#
# Improvements (audit):
#   - All device IDs typed as T.DeviceId (was bare Text).
#   - Child references typed as T.DeviceId (was List(Text)).
#   - DeviceSubscription has cancel() for explicit teardown.
#   - DeviceChange union has custom variant for forward compatibility.
#   - DeviceKind has other variant for forward compatibility.
#   - BindState has other variant for forward compatibility.
#   - list() paginated via T.Pagination.
#   - get() accepts T.DeviceId (typed, not raw path string).
#   - BoundDevice.id / UnboundDevice.id typed as T.DeviceId.
#   - No POSIX/Linux concepts (no /dev paths, no udev).
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using import "capability.capnp".Capability;
using P = import "power.capnp";

struct DeviceNode {
    # Stable opaque id.
    id @0 :T.DeviceId;
    # Logical path within the device tree (backend-decided, not filesystem).
    path @1 :Text;
    # Logical kind of device.
    kind @2 :DeviceKind;
    # Vendor and product identification.
    vendor @3 :Text;
    product @4 :Text;
    # Hardware version / revision string.
    version @5 :Text;
    # Driver manifest name owning this device (if bound).
    driverName @6 :Text;
    # Bind-status.
    boundState @7 :BindState;
    # Vendor/product/serial identifiers (numeric).
    idNumbers @8 :NumericIds;
    # Capabilities / affordances available.
    capabilities @9 :List(DeviceCap);
    # Children devices (graph topology).
    children @10 :List(T.DeviceId);
    # Associated caps for the device's bound driver.
    capabilitiesRef @11 :List(CapRef);
    # Audit-8: Device role classification.
    role @12 :DeviceRole;
    # Audit-8: Graduated trust level.
    trustLevel @13 :DeviceTrustLevel;
    # Audit-8: Device group memberships.
    groupIds @14 :List(UInt32);
}

enum DeviceKind {
    unknown @0;
    bus @1;
    cpu @2;
    memory @3;
    storage @4;
    network @5;
    display @6;
    input @7;
    audio @8;
    sensor @9;
    power @10;
    thermal @11;
    clock @12;
    timer @13;
    interruptController @14;
    dma @15;
    serial @16;
    gpio @17;
    i2c @18;
    spi @19;
    usb @20;
    pci @21;
    platform @22;
    virtual @23;
    other @24;
    # Backend-specific device kind.
    custom @25;
}

# Audit-8: Device role classification.
enum DeviceRole {
    primary    @0;   # Primary device (user's main device)
    companion  @1;   # Companion device (phone + watch)
    pairable   @2;   # Can be paired with other devices
    accessory  @3;   # Accessory (keyboard, mouse, headset)
    embedded   @4;   # Embedded device (sensor, controller)
    virtual    @5;   # Virtual device (VM, container)
    other      @6;   # Other role
    custom     @7;   # Backend-specific role
}

# Audit-8: Device trust level (graduated beyond bound/unbound).
enum DeviceTrustLevel {
    full       @0;   # Full trust (paired, authenticated)
    restricted @1;   # Restricted trust (limited capabilities)
    sandboxed  @2;   # Sandboxed (untrusted, limited access)
    unknown    @3;   # Trust level unknown
    revoked    @4;   # Trust has been revoked
    custom     @5;   # Backend-specific trust level
}

enum BindState {
    unbound @0;
    binding @1;
    bound @2;
    broken @3;
    orphaned @4;
    other @5;
    # Backend-specific bind state.
    custom @6;
}

struct NumericIds {
    vendor @0 :UInt32;
    product @1 :UInt32;
    device @2 :UInt32;
    class @3 :UInt32;
    subClass @4 :UInt32;
    serial @5 :Text;
}

struct DeviceCap {
    name @0 :Text;
    payload @1 :List(Property);
}

struct Property {
    key @0 :Text;
    value @1 :Text;
}

struct CapRef {
    # Reference to the CapId workspace data of a CapabilityService.
    capId @0 :Data;
}

struct DeviceFilter {
    kind @0 :DeviceKind;
    pathPrefix @1 :Text;
    vendor @2 :Text;
    product @3 :Text;
    boundState @4 :BindState;
    # Pagination for unbounded result sets.
    page @5 :T.Pagination;
    # Audit-8: Filter by device role.
    role @6 :DeviceRole;
    # Audit-8: Filter by trust level.
    trustLevel @7 :DeviceTrustLevel;
    # Audit-8: Filter by group membership.
    groupId @8 :UInt32;
    # Audit-8: Filter by mesh capability.
    meshCapable @9 :Bool;
}

struct DeviceChange {
    union {
        added @0 :DeviceNode;
        removed @1 :T.DeviceId;
        bound @2 :BoundDevice;
        unbound @3 :UnboundDevice;
        updated @4 :DeviceNode;
        # Backend-specific device change type.
        custom @5 :Data;
        # Audit-8: Device attested.
        attested @6 :DeviceAttestation;
        # Audit-8: Handoff initiated.
        handoffInitiated @7 :DeviceContinuity;
        # Audit-8: Handoff completed.
        handoffCompleted @8 :DeviceContinuity;
        # Audit-8: Firmware updated.
        firmwareUpdated @9 :DeviceFirmwareInfo;
        # Audit-8: Trust level changed.
        trustLevelChanged @10 :DeviceTrustLevelChange;
        # Audit-8: Power state changed.
        powerStateChanged @11 :DevicePowerState;
    }
}

struct BoundDevice {
    id @0 :T.DeviceId;
    driver @1 :Text;
    boundAt @2 :T.Timestamp;
}

struct UnboundDevice {
    id @0 :T.DeviceId;
    previousDriver @1 :Text;
    reason @2 :Text;
}

interface DeviceService {
    # Resolve a device by typed id.
    get @0 (id :T.DeviceId) -> (device :DeviceNode);
    # List children of a parent (root if empty), paginated.
    list @1 (parent :T.DeviceId, filter :DeviceFilter) -> (devices :List(DeviceNode), total :UInt64);
    # Subscribe to device-tree changes.
    subscribe @2 (filter :DeviceFilter) -> (subscription :DeviceSubscription);
    # Pull events from a subscription (convenience — canonical pull is on subscription interface).
    pull @3 (subscription :DeviceSubscription) -> (events :List(DeviceChange));
    # Bind a driver to a device.
    bind @4 (device :T.DeviceId, driver :Text) -> (result :T.BoolResult);
    # Unbind.
    unbind @5 (device :T.DeviceId) -> (result :T.BoolResult);
    # Get the device's affordance list.
    capabilities @6 (device :T.DeviceId) -> (caps :List(DeviceCap));

    # Audit-8: Active device discovery (not just listing known devices).
    discoverDevices @7 (filter :DeviceFilter) -> (devices :List(DeviceNode), total :UInt64);

    # Audit-8: Initiate device pairing.
    pairDevice @8 (deviceId :T.DeviceId) -> (result :T.BoolResult);

    # Audit-8: Unpair a device.
    unpairDevice @9 (deviceId :T.DeviceId) -> (result :T.BoolResult);

    # Audit-8: Get device change history.
    getDeviceHistory @10 (deviceId :T.DeviceId, pagination :T.Pagination)
        -> (events :List(DeviceChange), total :UInt64);

    # Audit-8: Get full device topology (graph, not just tree).
    getDeviceTopology @11 () -> (nodes :List(DeviceNode), edges :List(DeviceEdge));

    # Audit-8: Send cross-device notification.
    notifyDevice @12 (deviceId :T.DeviceId, title :Text, body :Text) -> T.VoidResult;

    # Audit-8: Get detailed capability list.
    getDeviceCapabilities @13 (deviceId :T.DeviceId) -> (caps :List(DeviceCap));

    # Audit-8: Device group management.
    listGroups @14 (pagination :T.Pagination) -> (groups :List(DeviceGroup), total :UInt64);
    createGroup @15 (group :DeviceGroup) -> (groupId :UInt32);
    deleteGroup @16 (groupId :UInt32) -> T.VoidResult;
    addToGroup @17 (groupId :UInt32, deviceId :T.DeviceId) -> T.VoidResult;
    removeFromGroup @18 (groupId :UInt32, deviceId :T.DeviceId) -> T.VoidResult;

    # Audit-8: Device attestation.
    attestDevice @19 (deviceId :T.DeviceId) -> (attestation :DeviceAttestation);
    getAttestation @20 (deviceId :T.DeviceId) -> (attestation :DeviceAttestation);

    # Audit-8: Device mesh capabilities.
    getMeshCapabilities @21 (deviceId :T.DeviceId) -> (mesh :DeviceMeshCapability);

    # Audit-8: Cross-device handoff (continuity).
    initiateHandoff @22 (sourceDevice :T.DeviceId, targetDevice :T.DeviceId, taskType :Text)
        -> (continuity :DeviceContinuity);
    acceptHandoff @23 (continuityId :UInt32) -> T.VoidResult;
    cancelHandoff @24 (continuityId :UInt32) -> T.VoidResult;

    # Audit-8: Device power/thermal state.
    getPowerState @25 (deviceId :T.DeviceId) -> (power :DevicePowerState);
    subscribePowerState @26 (deviceId :T.DeviceId) -> (subscription :PowerStateSubscription);

    # Audit-8: Device resource usage.
    getResourceUsage @27 (deviceId :T.DeviceId) -> (usage :DeviceResourceUsage);

    # Audit-8: Device firmware.
    getFirmwareInfo @28 (deviceId :T.DeviceId) -> (firmware :DeviceFirmwareInfo);
    updateFirmware @29 (deviceId :T.DeviceId) -> T.VoidResult;
    rollbackFirmware @30 (deviceId :T.DeviceId) -> T.VoidResult;

    # Audit-8: Device access control (false positive: device_policy.capnp).
    getDevicePolicy @31 (deviceId :T.DeviceId) -> (policy :DevicePolicy);
    setDevicePolicy @32 (deviceId :T.DeviceId, policy :DevicePolicy) -> T.VoidResult;

    # ─────────────────────────────────────────────────────────────────────
    # THE DRIVER FRAMEWORK ENTRY POINT
    #
    # `DriverRegistry` and `DriverLifecycle` were returned by NOTHING —
    # no method anywhere in the protocol produced either reference, so
    # the entire driver framework in this file was unreachable contract:
    # a driver author following the schema implemented registration,
    # probing, binding, health and restart, and no client could ever
    # call any of it (R8). This method is the hole being closed.
    #
    # It is capability-gated because registering a driver or restarting
    # one is an authority-granting act, not a discovery question: the
    # ungated half above answers "what exists", and this answers "who
    # gets to attach code to it" (ai.capnp:578-584). Discovery stays
    # open; the framework is acquired once, and holding the returned
    # registry IS the authority to call its methods — none of them takes
    # a capability parameter, because a per-method token would duplicate
    # the authority the reference already carries.
    getDriverRegistry @33 (authority :Capability) -> (registry :DriverRegistry);
}

interface DeviceSubscription {
    pull @0 () -> (events :List(DeviceChange));
    # Explicit cancellation — stops the event stream and releases resources.
    cancel @1 () -> T.VoidResult;
}

# ── Audit-8: Device Group ─────────────────────────────────────────────

struct DeviceGroup {
    # Group identifier (0 = new group).
    groupId @0 :UInt32;
    # Human-readable group name.
    name @1 :Text;
    # Devices in this group.
    deviceIds @2 :List(T.DeviceId);
    # Group description.
    description @3 :Text;
}

# ── Audit-8: Device Attestation ───────────────────────────────────────

struct DeviceAttestation {
    # Device being attested.
    deviceId @0 :T.DeviceId;
    # When attestation was performed.
    attestedAt @1 :T.Timestamp;
    # Hash of platform configuration.
    platformConfig @2 :T.HashOutput;
    # Firmware version at attestation.
    firmwareVersion @3 :T.Version;
    # Whether attestation was successful.
    verified @4 :Bool;
}

# ── Audit-8: Device Mesh Capability ───────────────────────────────────

struct DeviceMeshCapability {
    # Device supporting mesh.
    deviceId @0 :T.DeviceId;
    # Whether mesh is supported.
    supportsMesh @1 :Bool;
    # Mesh protocol name (e.g., "Thread", "Zigbee", "BLE Mesh").
    meshProtocol @2 :Text;
    # neighboring devices in the mesh.
    meshNeighbors @3 :List(T.DeviceId);
}

# ── Audit-8: Device Continuity (Handoff) ──────────────────────────────

struct DeviceContinuity {
    # Continuity session identifier.
    continuityId @0 :UInt32;
    # Source device.
    sourceDevice @1 :T.DeviceId;
    # Target device.
    targetDevice @2 :T.DeviceId;
    # Task type being handed off.
    taskType @3 :Text;
    # Continuity state.
    state @4 :ContinuityState;
}

enum ContinuityState {
    pending   @0;   # Handoff initiated, waiting for acceptance
    active    @1;   # Handoff accepted, task running
    completed @2;   # Handoff completed successfully
    failed    @3;   # Handoff failed
    custom    @4;   # Backend-specific state
}

# ── Audit-8: Device Power State ───────────────────────────────────────

struct DevicePowerState {
    # Device being queried.
    deviceId @0 :T.DeviceId;
    # Current power mode.
    powerMode @1 :PowerMode;
    # Battery level (0.0-1.0, -1.0 = unknown).
    batteryLevel @2 :Float32;
    # Whether the device is charging.
    charging @3 :Bool;
    # Thermal state. (R6: power.capnp owns the canonical `ThermalState`;
    # this was a verbatim duplicate before.)
    thermalState @4 :P.ThermalState;
}

enum PowerMode {
    active    @0;   # Full power
    lowPower  @1;   # Low power mode
    sleep     @2;   # Sleep mode
    hibernate @3;   # Hibernate mode
    custom    @4;   # Backend-specific power mode
}

# ── Audit-8: Power State Subscription ─────────────────────────────────

interface PowerStateSubscription {
    pull @0 () -> (states :List(DevicePowerState));
    cancel @1 () -> T.VoidResult;
}

# ── Audit-8: Device Resource Usage ────────────────────────────────────

struct DeviceResourceUsage {
    # Device being queried.
    deviceId @0 :T.DeviceId;
    # CPU usage (0.0-1.0).
    cpuPercent @1 :Float32;
    # Memory usage in bytes.
    memoryBytes @2 :UInt64;
    # GPU usage (0.0-1.0, -1.0 = unknown).
    gpuPercent @3 :Float32;
    # Network received bytes.
    networkRxBytes @4 :UInt64;
    # Network transmitted bytes.
    networkTxBytes @5 :UInt64;
    # When this sample was captured.
    timestamp @6 :T.Timestamp;
}

# ── Audit-8: Device Firmware Info ─────────────────────────────────────

struct DeviceFirmwareInfo {
    # Device being queried.
    deviceId @0 :T.DeviceId;
    # Current firmware version.
    currentVersion @1 :T.Version;
    # Available firmware version (0 = no update).
    availableVersion @2 :T.Version;
    # Whether an update is available.
    updateAvailable @3 :Bool;
    # When the last firmware check was performed.
    lastChecked @4 :T.Timestamp;
}

# ── Audit-8: Device Trust Level Change ────────────────────────────────

struct DeviceTrustLevelChange {
    # Device whose trust level changed.
    deviceId @0 :T.DeviceId;
    # Previous trust level.
    oldLevel @1 :DeviceTrustLevel;
    # New trust level.
    newLevel @2 :DeviceTrustLevel;
    # When the change occurred.
    timestamp @3 :T.Timestamp;
}

# ── Audit-8: Device Edge (for topology graph) ─────────────────────────

struct DeviceEdge {
    # Source device.
    from @0 :T.DeviceId;
    # Target device.
    to @1 :T.DeviceId;
    # Edge type (e.g., "parent", "peer", "mesh").
    edgeType @2 :Text;
}

# ── Audit-8: Device Policy (false positive: device_policy.capnp) ──────

struct DevicePolicy {
    # Allowed actions for this device.
    allowedActions @0 :List(Text);
    # Denied actions for this device.
    deniedActions @1 :List(Text);
    # Maximum power budget (watts, 0 = unlimited).
    maxPowerWatts @2 :Float32;
    # Maximum network bandwidth (bytes/sec, 0 = unlimited).
    maxNetworkBps @3 :UInt64;
    # Whether the device is geofenced.
    geofenced @4 :Bool;
    # Geofence region (empty = no geofence).
    geofenceRegion @5 :Text;
}

# ═══════════════════════════════════════════════════════════════════════
# v0.0.2 additions — Universal Driver Framework
#
# Drivers are first-class capabilities. The framework knows three
# affordances:
#   1. Register  — a driver announces itself with a class & capabilities.
#   2. Bind     — bind a registered driver to a device.
#   3. Lifecycle — started/stopped/restarted without OS intervention.
#
# How drivers are implemented (in-kernel module, sandboxed userspace
# program, remote service) is a backend decision. The framework
# only commits to outcomes.
# ═══════════════════════════════════════════════════════════════════════

# ── Driver Descriptor ────────────────────────────────────────
# What a driver claims to be and do. Compatible-version is the
# monotonic version the driver speaks; bound kernels/registries
# reject bindings where the consumer is too old.

struct DriverDescriptor {
    driverId @0 :T.DriverId;
    class @1 :T.DriverClass;
    name @2 :Text;
    vendor @3 :Text;
    version @4 :Text;
    # Compatible kernel version range (e.g., ">=0.0.2 <0.1.0").
    compatibleKernel @5 :Text;
    # Free-form affordance tags. Bindings match if intersection is non-empty.
    capabilities @6 :List(Text);
    # Vendor-provided opaque metadata (build hash, signing cert, ...).
    metadata @7 :Data;
}

# ── Driver Registration ──────────────────────────────────────
interface DriverRegistry {
    # Register a driver capability. The registry returns a stable
    # DriverId that consumers can request, AND the lifecycle interface
    # the driver itself answers on.
    #
    # Returning DriverLifecycle here is what makes it reachable: it was
    # previously produced by no method, so the probe/bind/start/ping
    # half of the contract was uncallable. The driver that registers is
    # exactly the party that should answer those calls, so this is the
    # natural acquisition point rather than an invented accessor.
    register @0 (driver :DriverDescriptor)
              -> (driverId :T.DriverId, lifecycle :DriverLifecycle, handle :UInt64);
    # Unregister. Outstanding subscriptions are auto-cancelled.
    unregister @1 (driver :T.DriverId) -> (result :T.VoidResult);
    # Look up by name (e.g., "xhci-pci").
    findByName @2 (name :Text) -> (driver :DriverDescriptor);
    # Queryable class.
    list @3 (class :T.DriverClass, page :T.Pagination)
        -> (drivers :List(DriverDescriptor), total :UInt64);
    # Watch for drivers arriving/leaving.
    subscribe @4 (classFilter :T.DriverClass) -> (subscription :DriverSubscription);
}

interface DriverSubscription {
    # Bounded pull, so a slow consumer cannot grow the driver-event
    # queue without limit and a burst of registrations is not shipped
    # as one unbounded message.
    pull @0 (maxEvents :UInt32) -> (events :List(DriverEvent));
    cancel @1 () -> T.VoidResult;
}

# register's named results are the whole driver-framework entry point:
# a stable DriverId consumers can request, the DriverLifecycle interface
# the driver itself answers on (previously produced by no method, so the
# probe/bind/start/ping half of the contract was uncallable), and a
# stable handle for the registered capability.

struct DriverEvent {
    at @0 :UInt64;
    union {
        registered @1 :DriverDescriptor;
        unregistered @2 :T.DriverId;
        healthChanged @3 :DriverHealthChange;
        custom @4 :Void;
    }
}

struct DriverHealthChange {
    driver @0 :T.DriverId;
    before @1 :T.DriverState;
    after @2 :T.DriverState;
    reason @3 :Text;
}

# ── Driver Lifecycle ────────────────────────────────────────
# Lifecycle is what a driver host invokes. The driver registers,
# probes devices, binds, starts, runs (emits health), pauses,
# restarts, and stops. The host decides when to restart; the
# driver gets a clean state on every start.

interface DriverLifecycle {
    # Probe — does this driver recognize this device? Backends
    # may run probe in a sandbox; result is yes/maybe/no.
    probe @0 (device :T.DeviceId) -> (result :ProbeResult);
    # Bind the device to this driver. Idempotent.
    bind @1 (device :T.DeviceId) -> (result :T.VoidResult);
    # Unbind.
    unbind @2 (device :T.DeviceId) -> (result :T.VoidResult);
    # Move into running state.
    start @3 () -> (result :T.VoidResult);
    # Pause on demand (e.g., for sleep).
    pause @4 () -> (result :T.VoidResult);
    # Resume from pause.
    resume @5 () -> (result :T.VoidResult);
    # Graceful stop.
    stop @6 () -> (result :T.VoidResult);
    # Crash-recovery: the host kicks the driver. Driver resets
    # internal state and returns. Continuing users of capabilities
    # from this driver receive E_DRIVER_RESTART errors.
    restart @7 () -> (result :T.VoidResult);
    # Health probe — does the driver still answer?
    ping @8 () -> (health :T.DriverHealth);
}

enum ProbeResult {
    matched   @0;
    maybe     @1;
    rejected  @2;
    failed    @3;
    custom    @4;
}

# ── Driver Restart Policy ───────────────────────────────────
# The contract lets a driver host express restart policy without
# restricting driver implementation. Implementations may ignore
# the policy (in-kernel drivers typically do).

struct DriverRestartPolicy {
    driver @0 :T.DriverId;
    # Max restarts in `windowMs` before permanent failure (0 = unlimited).
    maxRestarts @1 :UInt32;
    windowMs @2 :UInt64;
    # Delay before auto-restart (ms). 0 = no auto-restart.
    autoRestartDelayMs @3 :UInt64;
    # What to do if maxRestarts is exhausted.
    exhaustedAction @4 :ExhaustedAction;
}

enum ExhaustedAction {
    disable @0;       # stop trying; surface to user
    panic @1;         # consider this a system failure
    ignore @2;        # operator's problem
    custom @3;
}
