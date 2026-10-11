@0xa1b2c3d4e5f6000f;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Network - per-interface state, connect/disconnect, WiFi, cellular, VPN.
#
# Improvements beyond the original schema:
#   - NetworkInterfaceId typed ID replaces bare Text interface names.
#   - VpnProfileId / VpnConnectionId typed IDs replace bare Text/UInt64.
#   - T.Duration for latency and time-based parameters.
#   - WiFi-specific fields extracted to WifiStatus sub-struct.
#   - Subscription cancel methods added to all subscriptions.
#   - Custom/other variants on all enums.
#   - TransportProtocol enum replaces bare Text for protocol matching.
#   - Physical quantities documented (signal dBm, speed bps, frequency Hz).
#   - T.IpAddress for typed IP address fields.
#   - T.Pagination on all list-returning methods.
#   - Mesh, satellite, LoRa/Sigfox/NB-IoT, BLE mesh, packet radio,
#     multi-link bonding network types.
#   - Network quality metrics (packet loss, jitter, throughput, MOS).
#   - Network topology discovery for device-to-device connections.
#   - Network power management profiles.
#   - Network handoff for seamless transitions.
#   - Network slicing for virtual isolation.
#   - Network telemetry and diagnostics.
#   - Network security (firewall) rules.
#   - NTP/PTP time synchronization.
#
# Revamp fixes (this wave):
#   - Five structs no method returns are gone, with their private enums:
#     MeshNetwork, LoraNetwork, BleMeshNetwork, PacketRadioNetwork,
#     MultiLinkConfig, MeshRoute, MeshRoutingAlgorithm, BondingStrategy.
#     A consumer reading the schema believed mesh/LoRa/packet-radio state
#     was queryable and built against types no service will ever emit.
#   - Technology enumerations became open tokens: NetworkType,
#     WifiSecurity, VpnKind, TransportProtocol, WifiBand, SaMode,
#     NanRole, OrbitType, BlockedDomain... a 2046 radio, VPN protocol or
#     firewall-matchable transport is a string with unknown-tolerance.
#   - Wi-Fi credentials are a reference to secret material, not a
#     cleartext password in the message.
#   - The NIC frame path can name its buffer: NicFrameDesc carries a
#     T.BufferId, so the highest-volume data path in the protocol is
#     expressible zero-copy instead of relying on an out-of-band
#     slot-to-memory agreement.
#   - The Bluetooth scan/pair surface is gone (bluetooth.capnp is the
#     canonical home; this file carried a duplicate of its device type).
#   - Interface ids are not labels: `renameInterface` is gone.
#   - Network slicing uses a typed slice id, and time-sync status is a
#     struct rather than a three-field tuple.
#
# Audit-9 improvements:
#   - SatelliteNetwork struct for satellite-specific fields.
#   - CellularConfig for signal band, carrier aggregation, SA/NSA.
#   - WifiNanConfig for Wi-Fi Aware (NAN) neighbor-aware networking.
#   - DtnBundle for DTN (delay-tolerant networking) store-and-forward.
#   - Ipv6Config for SLAAC, DHCPv6, address privacy extensions.
#   - Hotspot client filtering and bandwidth scheduling methods.
#   - Host-global networking and radio control: the master switch
#     (setNetworking @72, isNetworkingEnabled @73) and radio state as an
#     open token set (setRadioEnabled @74, listRadioStates @75,
#     RadioState), plus InterfaceConnectionStatus.hostState — so a host
#     whose networking is switched off reports WHY it is silent instead
#     of being indistinguishable from a dead interface. Incident-born:
#     a persistent disabled-networking state once survived reboot with
#     every device reported unmanaged and no contract surface that could
#     have said so.
# ═══════════════════════════════════════════════════════════════════════

interface Network {
    # ── Interfaces ──
    getInterfaces @0 (pagination :T.Pagination) -> (interfaces :List(NetworkInterface));

    # ── Status ──
    getStatus @1 (interfaceId :T.NetworkInterfaceId) -> (status :InterfaceConnectionStatus);
    subscribeStatus @2 (interfaceId :T.NetworkInterfaceId) -> (subscription :StatusSubscription);
    pullStatus @3 (subscription :StatusSubscription) -> (status :InterfaceConnectionStatus);

    # ── Connect / disconnect ──
    connect @4 (interfaceId :T.NetworkInterfaceId, network :NetworkConfig) -> T.VoidResult;
    disconnect @5 (interfaceId :T.NetworkInterfaceId) -> T.VoidResult;

    # ── WiFi scan + connect ──
    wifiScan @6 (pagination :T.Pagination) -> (networks :List(WifiNetwork));
    # ssid is a user-facing WiFi network name, not a typed entity ID.
    #
    # `credential` references secret material (types.capnp T.SecretKeyId);
    # a network secret must not cross the wire as a cleartext field.
    wifiConnect @7 (ssid :Text, credential :T.SecretKeyId) -> T.VoidResult;
    wifiDisconnect @8 () -> T.VoidResult;
    wifiSetAutoConnect @9 (ssid :Text, enabled :Bool) -> T.VoidResult;
    wifiSetMacRandomization @10 (interfaceId :T.NetworkInterfaceId, enabled :Bool) -> T.VoidResult;

    # ── Cellular data ──
    setMobileData @11 (enabled :Bool) -> T.VoidResult;
    isMobileDataEnabled @12 () -> (enabled :Bool);
    setDataRoaming @13 (enabled :Bool) -> T.VoidResult;
    isDataRoamingEnabled @14 () -> (enabled :Bool);

    # ── VPN ──
    setVpnProfile @15 (profile :VpnProfile) -> T.VoidResult;
    removeVpnProfile @16 (profileId :T.VpnProfileId) -> T.VoidResult;
    listVpnProfiles @17 (pagination :T.Pagination) -> (profiles :List(VpnProfile));
    attachVpn @18 (profileId :T.VpnProfileId) -> (connection :VpnConnection);
    detachVpn @19 (connectionId :T.VpnConnectionId) -> T.VoidResult;
    listVpnConnections @20 (pagination :T.Pagination) -> (connections :List(VpnConnection));

    # ── Hotspot (tethering) ──
    startHotspot @21 (config :HotspotConfig) -> T.VoidResult;
    stopHotspot @22 () -> T.VoidResult;
    getHotspotStatus @23 () -> (status :HotspotStatus);
    subscribeHotspot @24 () -> (subscription :HotspotSubscription);
    pullHotspot @25 (subscription :HotspotSubscription) -> (status :HotspotStatus);

    # ── DHCP ──
    # DHCP is one implementation; the contract is "assign me an address
    # for this interface, tell me when it changes, let me give it back".
    # Naming the protocol makes a SLAAC-only or statically configured
    # backend a special case.
    requestAddressAssignment @26 (interfaceId :T.NetworkInterfaceId, options :AddressAssignmentOptions) -> T.VoidResult;
    getAddressAssignment @27 (interfaceId :T.NetworkInterfaceId) -> (result :AddressAssignmentResult);
    releaseAddressAssignment @28 (interfaceId :T.NetworkInterfaceId) -> T.VoidResult;
    subscribeAddressAssignment @29 (interfaceId :T.NetworkInterfaceId) -> (subscription :AddressAssignmentSubscription);
    pullAddressAssignment @30 (subscription :AddressAssignmentSubscription) -> (assignment :AddressAssignment);

    # ── DNS (preferred servers) ──
    getDnsServers @31 (interfaceId :T.NetworkInterfaceId, pagination :T.Pagination) -> (servers :List(DnsServer));
    setDnsServers @32 (interfaceId :T.NetworkInterfaceId, servers :List(DnsServer)) -> T.VoidResult;

    # ── QoS / DSCP ──
    setInterfaceQos @33 (interfaceId :T.NetworkInterfaceId, qos :List(QosRule)) -> T.VoidResult;
    getInterfaceQos @34 (interfaceId :T.NetworkInterfaceId, pagination :T.Pagination) -> (rules :List(QosRule));

    # ── Counters ──
    # A window ending now. ("Since what?" is the caller's question;
    # `window` answers it without an implementer guessing.)
    getCounters @35 (interfaceId :T.NetworkInterfaceId, window :T.Duration) -> (counters :InterfaceCounters);
    resetCounters @36 (interfaceId :T.NetworkInterfaceId) -> T.VoidResult;
    subscribeCounters @37 (interfaceId :T.NetworkInterfaceId) -> (subscription :CounterSubscription);
    pullCounters @38 (subscription :CounterSubscription) -> (counters :InterfaceCounters);

    # ── Captive portal ──
    checkCaptivePortal @39 (interfaceId :T.NetworkInterfaceId) -> (state :CaptivePortalState);
    subscribeCaptivePortal @40 (interfaceId :T.NetworkInterfaceId) -> (subscription :CaptivePortalSubscription);
    pullCaptivePortal @41 (subscription :CaptivePortalSubscription) -> (state :CaptivePortalState);

    # ── Lifecycle ──
    upInterface @42 (interfaceId :T.NetworkInterfaceId) -> T.VoidResult;
    downInterface @43 (interfaceId :T.NetworkInterfaceId) -> T.VoidResult;

    # ── Network topology ──
    getTopology @44 (pagination :T.Pagination) -> (nodes :List(TopologyNode), links :List(TopologyLink), total :UInt64);

    # ── Network power management ──
    setPowerProfile @45 (interfaceId :T.NetworkInterfaceId, profile :Text) -> T.VoidResult;
    getPowerProfile @46 (interfaceId :T.NetworkInterfaceId) -> (profile :Text);

    # ── Network handoff ──
    handoff @47 (fromInterface :T.NetworkInterfaceId, toInterface :T.NetworkInterfaceId) -> T.VoidResult;

    # ── Network slicing ──
    createSlice @48 (config :SliceConfig) -> (sliceId :NetworkSliceId);
    removeSlice @49 (sliceId :NetworkSliceId) -> T.VoidResult;
    listSlices @50 (pagination :T.Pagination) -> (slices :List(NetworkSlice), total :UInt64);

    # ── Network telemetry ──
    getTelemetry @51 (interfaceId :T.NetworkInterfaceId, duration :T.Duration) -> (telemetry :NetworkTelemetry);
    subscribeTelemetry @52 (interfaceId :T.NetworkInterfaceId) -> (subscription :TelemetrySubscription);
    pullTelemetry @53 (subscription :TelemetrySubscription) -> (telemetry :NetworkTelemetry);

    # ── Network diagnostics ──
    ping @54 (target :T.IpAddress) -> (latency :T.Duration, packetLoss :Float32);
    traceroute @55 (target :T.IpAddress) -> (hops :List(TracerouteHop));

    # ── Network security (firewall) ──
    setFirewallRules @56 (interfaceId :T.NetworkInterfaceId, rules :List(FirewallRule)) -> T.VoidResult;
    getFirewallRules @57 (interfaceId :T.NetworkInterfaceId, pagination :T.Pagination) -> (rules :List(FirewallRule));

    # ── Network time sync ──
    getTimeSync @58 (interfaceId :T.NetworkInterfaceId) -> (status :TimeSyncStatus);

    # ── Satellite ──
    getSatelliteConfig @59 () -> (config :SatelliteNetwork);

    # ── Hotspot enhancements ──
    setHotspotClientFilter @60 (macAddresses :List(T.MacAddress)) -> T.VoidResult;
    getHotspotBandwidthSchedule @61 () -> (schedule :List(BandwidthSlot));
    setHotspotBandwidthSchedule @62 (schedule :List(BandwidthSlot)) -> T.VoidResult;

    # ── DTN (delay-tolerant networking) ──
    sendDtnBundle @63 (bundle :DtnBundle) -> T.VoidResult;
    receiveDtnBundles @64 (pagination :T.Pagination) -> (bundles :List(DtnBundle), total :UInt64);

    # ── Cellular configuration ──
    getCellularConfig @65 () -> (config :CellularConfig);
    setCellularConfig @66 (config :CellularConfig) -> T.VoidResult;

    # ── IPv6 configuration ──
    getIpv6Config @67 (interfaceId :T.NetworkInterfaceId) -> (config :Ipv6Config);
    setIpv6Config @68 (interfaceId :T.NetworkInterfaceId, config :Ipv6Config) -> T.VoidResult;

    # ── Wi-Fi Aware (NAN) ──
    wifiNanAdvertise @69 (config :WifiNanConfig) -> T.VoidResult;
    wifiNanDiscover @70 (config :WifiNanConfig, pagination :T.Pagination) -> (peers :List(NanPeer), totalCount :UInt32);

    # ── Device drivers ──
    # A NIC driver is a capability: acquire the provider by presenting
    # one. This is how the provider surface is reached — the reference
    # granted here IS the authority to drive the device.
    nicProvider @71 (authority :Capability) -> (provider :NicProvider);

    # ── Host-global networking and radios ──
    # The master switch that sits above per-connection state. Every host
    # has one — a phone's airplane mode, a server's `networking off` —
    # and before these methods existed a switched-off host was
    # indistinguishable from a dead interface, so every backend answered
    # with its own silence. A 2046 machine still has this switch.
    setNetworking @72 (enabled :Bool) -> T.VoidResult;
    isNetworkingEnabled @73 () -> (enabled :Bool);

    # Radios are an open token set: wifi, cellular, and radios nobody
    # has named yet are all Text. A closed enum of radio kinds would
    # freeze 2020s hardware into the contract.
    setRadioEnabled @74 (radio :Text, enabled :Bool) -> T.VoidResult;
    listRadioStates @75 (pagination :T.Pagination) -> (radios :List(RadioState), total :UInt64);
}

using import "capability.capnp".Capability;

struct BandwidthSlot {
    startHour @0 :UInt8;
    endHour @1 :UInt8;
    maxKbps @2 :UInt32;
}

struct NanPeer {
    peerId @0 :Text;
    name @1 :Text;
    rssi @2 :Int32;
    metadata @3 :T.StringMap;
}

# ── Subscriptions ───────────────────────────────────────────

interface StatusSubscription {
    pull @0 () -> (status :InterfaceConnectionStatus);
    cancel @1 () -> T.VoidResult;
}

interface HotspotSubscription {
    pull @0 () -> (status :HotspotStatus);
    cancel @1 () -> T.VoidResult;
}

interface AddressAssignmentSubscription {
    pull @0 () -> (assignment :AddressAssignment);
    cancel @1 () -> T.VoidResult;
}

interface CounterSubscription {
    pull @0 () -> (counters :InterfaceCounters);
    cancel @1 () -> T.VoidResult;
}

interface CaptivePortalSubscription {
    pull @0 () -> (state :CaptivePortalState);
    cancel @1 () -> T.VoidResult;
}

interface TelemetrySubscription {
    pull @0 () -> (telemetry :NetworkTelemetry);
    cancel @1 () -> T.VoidResult;
}

# ── Interface ───────────────────────────────────────────────

# A slice is an isolated network view; its id is opaque.
struct NetworkSliceId { id @0 :UInt64; }

struct NetworkInterface {
    id @0 :T.NetworkInterfaceId;
    name @1 :Text;
    # Link technology as an open token ("ethernet", "wifi", "cellular", ...).
    type @2 :Text;
    # Hardware / MAC address (T.MacAddress is the foundation's 6-octet
    # address type; it carries any MAC, not only a Bluetooth one — the
    # former `T.BluetoothAddress` spelling was a foundation misnomer that
    # had this file typing Wi-Fi and Ethernet addresses with a radio's name).
    hwAddress @3 :T.MacAddress;
    ipAddresses @4 :List(T.IpAddress);
    ipv6Addresses @5 :List(T.IpAddress);
    # Gateway (current).
    gateway @6 :T.IpAddress;
    # DNS servers already configured.
    dnsServers @7 :List(T.IpAddress);
    # Up / connected flags.
    up @8 :Bool;
    connected @9 :Bool;
    # MTU currently effective.
    mtU @10 :UInt32;
    # Speed in bits per second (0 = unknown).
    speedUp @11 :UInt64;
    speedDown @12 :UInt64;
    # Driver label as REPORTED by the backend. Absent on a backend with
    # no driver concept (a fabric, a browser runtime) — never fabricated.
    driver @13 :Text;
    # Whether the MAC is randomized on the fly.
    macRandom @14 :Bool;
    # Authority references that may use this interface.
    requiredCaps @15 :List(T.CapabilityHandle);
    # Network slice this interface belongs to (absent = default).
    sliceId @16 :NetworkSliceId;
    # Current power profile applied to this interface, as an open token.
    powerProfile @17 :Text;
    # Backend-specific metadata.
    metadata @18 :T.StringMap;
}

# Link technology as an open token ("ethernet", "wifi", "cellular",
# "vpn", "loopback", ...): a 2046 physical layer is a string with
# unknown-tolerance, not a new ordinal. The previous 19-value enum froze
# LoRa/Sigfox/NB-IoT/BLE-mesh/packet-radio — three of which no method in
# the tree could even report.
#
# NOTE on the MAC fields below: they are typed `T.MacAddress`, the
# foundation's 6-octet address type. It carries any MAC — Wi-Fi, Ethernet,
# Bluetooth, a future link — and was renamed from `T.BluetoothAddress` in
# the 2026-10-10 integration pass to close the X1 contradiction, in which
# this file typed Wi-Fi BSSIDs and Ethernet hardware addresses with a type
# named after a radio. The name now states the shape, not one of its users.

# ── Connection Status ───────────────────────────────────────
# WiFi-specific fields are isolated in WifiStatus to avoid
# leaking WiFi concepts into generic connection status.

struct InterfaceConnectionStatus {
    connected @0 :Bool;
    interface @1 :T.NetworkInterfaceId;
    type @2 :Text;
    # dBm signal strength (signed; -100..0 typical for WiFi/cellular).
    strength @3 :Int32;
    # Speed in bits per second.
    speed @4 :UInt64;
    # Estimated latency.
    latency @5 :T.Duration;
    # Quality in 0..100.
    quality @6 :UInt8;
    # Whether interface is metered (data-usage cost).
    metered @7 :Bool;
    # Whether captive-portal is detected.
    behindCaptive @8 :Bool;
    # WiFi-specific fields. Zeroed/empty if type != wifi.
    wifi @9 :WifiStatus;
    # Network quality metrics (packet loss, jitter, throughput).
    qualityMetrics @10 :LinkQuality;
    metadata @11 :T.StringMap;
    # Open token for WHY the interface is or is not usable:
    # managed / unmanaged / networking-disabled / radio-off / carrier-down /
    # no-firmware / unknown. A user must be able to tell a host whose
    # networking is switched off from a radio that is off from a cable
    # nobody plugged in — three failures that look identical through the
    # connected boolean alone.
    hostState @12 :Text;
}

# The observable state of one radio. `name` is an open token ("wifi",
# "cellular", "bluetooth", or a radio that does not exist yet); `enabled`
# is policy; `hardBlocked` is a physical switch; `softBlocked` is a
# software block. A backend that conflates policy with a hardware switch
# is lying, so the two never share a field.
struct RadioState {
    name @0 :Text;
    enabled @1 :Bool;
    hardBlocked @2 :Bool;
    softBlocked @3 :Bool;
}

struct WifiStatus {
    ssid @0 :Text;
    # AP MAC address (see the note under NetworkType).
    bssid @1 :T.MacAddress;
    # Frequency in Hz (e.g., 2412000000 for 2.4GHz channel 1).
    frequency @2 :UInt32;
    # Roaming hint (AP is weak, roaming in progress).
    roaming @3 :Bool;
    metadata @4 :T.StringMap;
}

# ── Network Quality Metrics ─────────────────────────────────

struct LinkQuality {
    # Packet loss ratio (0.0 = none, 1.0 = 100% loss).
    packetLoss @0 :Float32;
    # Jitter (variation in latency).
    jitter @1 :T.Duration;
    # Throughput in bits per second.
    throughputBps @2 :UInt64;
    # Mean Opinion Score for voice/video quality (1.0..5.0).
    mosScore @3 :Float32;
    # Round-trip time (measured, not estimated).
    rtt @4 :T.Duration;
}

# ── Satellite Network ───────────────────────────────────────────────────

struct SatelliteNetwork {
    # Satellite constellation (e.g., "starlink", "oneweb", "iridium").
    constellation @0 :Text;
    # Orbit type (LEO, MEO, GEO).
    orbitType @1 :Text;
    # Expected latency in milliseconds.
    expectedLatencyMs @2 :UInt32;
    # Whether the satellite link is currently active.
    active @3 :Bool;
    metadata @4 :T.StringMap;
}

# Orbit type as an open token ("leo", "meo", "geo").

# ── Cellular Configuration ───────────────────────────────────────────────

struct CellularConfig {
    # Signal band (e.g., "n78" for 5G, "B2" for LTE).
    band @0 :Text;
    # Carrier name.
    carrier @1 :Text;
    # Whether SA (standalone) or NSA (non-standalone) mode.
    saMode @2 :Text;
    # Supported carrier aggregation bands.
    carrierAggregationBands @3 :List(Text);
    metadata @4 :T.StringMap;
}

# Standalone vs non-standalone as an open token ("nsa", "sa").

# ── Wi-Fi Aware (NAN) ───────────────────────────────────────────────────

struct WifiNanConfig {
    # Service name for NAN discovery.
    serviceName @0 :Text;
    # Whether to publish or subscribe, as an open token.
    mode @1 :Text;
    # TTL in milliseconds.
    ttlMs @2 :UInt32;
    metadata @3 :T.StringMap;
}

# NAN role as an open token ("publish", "subscribe").

# ── DTN (Delay-Tolerant Networking) ─────────────────────────────────────

struct DtnBundle {
    # Bundle identifier.
    bundleId @0 :Text;
    # Source node.
    source @1 :Text;
    # Destination node.
    destination @2 :Text;
    # Payload data, as a handle: a store-and-forward bundle is by
    # definition large, and the inline spelling copied all of it through
    # the message.
    payload @3 :T.DataHandle;
    # Bundle lifetime.
    lifetime @4 :T.Duration;
    # Custody transfer enabled.
    custodyTransfer @5 :Bool;
    metadata @6 :T.StringMap;
}

# ── IPv6 Configuration ───────────────────────────────────────────────────

struct Ipv6Config {
    # Whether SLAAC is enabled.
    slaacEnabled @0 :Bool;
    # Whether automatic address assignment is enabled.
    autoAssignmentEnabled @1 :Bool;
    # Address privacy extensions (RFC 4941) enabled.
    privacyExtensions @2 :Bool;
    # Prefix for SLAAC-derived addresses.
    prefix @3 :Text;
    # Prefix length.
    prefixLen @4 :UInt8;
    metadata @5 :T.StringMap;
}

# ── Network Topology ────────────────────────────────────────

struct TopologyNode {
    interfaceId @0 :T.NetworkInterfaceId;
    # Node label (hostname, device name, or alias).
    label @1 :Text;
    # Node type (router, switch, endpoint, gateway).
    nodeType @2 :Text;
    # Whether this node is reachable.
    reachable @3 :Bool;
    # Node metadata.
    metadata @4 :T.StringMap;
}

struct TopologyLink {
    source @0 :T.NetworkInterfaceId;
    target @1 :T.NetworkInterfaceId;
    # Link type (ethernet, wifi, bluetooth, cellular, mesh).
    linkType @2 :Text;
    # Link latency.
    latency @3 :T.Duration;
    # Link bandwidth in bits per second.
    bandwidthBps @4 :UInt64;
    # Link cost metric (lower = preferred).
    metric @5 :UInt32;
    metadata @6 :T.StringMap;
}

# ── Network Power Management ────────────────────────────────

# Power profile as an open token ("performance", "balanced",
# "batterySaver", ...).

# ── Network Slicing ─────────────────────────────────────────

struct SliceConfig {
    # Human-readable slice name.
    name @0 :Text;
    # Isolation level.
    isolation @1 :SliceIsolation;
    # Minimum bandwidth reservation in bits per second.
    minBandwidthBps @2 :UInt64;
    # Maximum latency target.
    maxLatency @3 :T.Duration;
    # Priority (higher = more important).
    priority @4 :UInt8;
    # Traffic selectors (application IDs that use this slice).
    applicationIds @5 :List(T.AppId);
    metadata @6 :T.StringMap;
}

enum SliceIsolation {
    # Best-effort sharing.
    shared @0;
    # Guaranteed minimum bandwidth.
    guaranteed @1;
    # Fully isolated (dedicated radio resources).
    dedicated @2;
    custom @3;
}

struct NetworkSlice {
    sliceId @0 :NetworkSliceId;
    name @1 :Text;
    isolation @2 :SliceIsolation;
    minBandwidthBps @3 :UInt64;
    maxLatency @4 :T.Duration;
    priority @5 :UInt8;
    # Whether the slice is currently active.
    active @6 :Bool;
    metadata @7 :T.StringMap;
}

# ── Network Telemetry ───────────────────────────────────────

struct NetworkTelemetry {
    interfaceId @0 :T.NetworkInterfaceId;
    # Sampling window.
    sampledAt @1 :T.Timestamp;
    duration @2 :T.Duration;
    # Byte counters for the sampling window.
    bytesIn @3 :UInt64;
    bytesOut @4 :UInt64;
    # Packet counters.
    packetsIn @5 :UInt64;
    packetsOut @6 :UInt64;
    # Error counters.
    errorsIn @7 :UInt64;
    errorsOut @8 :UInt64;
    # Drop counters.
    dropsIn @9 :UInt64;
    dropsOut @10 :UInt64;
    # Average latency during the window.
    avgLatency @11 :T.Duration;
    # Average packet loss during the window.
    avgPacketLoss @12 :Float32;
}

# ── Network Diagnostics ─────────────────────────────────────

struct TimeSyncStatus {
    # Measured offset from reference time (absent when not measured).
    offset @0 :T.Duration;
    offsetMeasured @1 :Bool;
    # Stratum as reported (NTP semantics; a PTP-synced clock has none).
    stratum @2 :UInt32;
    # Source name as an open token.
    source @3 :Text;
    metadata @4 :T.StringMap;
}

struct TracerouteHop {
    # Hop number (1-based).
    hop @0 :UInt8;
    # Address of this hop.
    address @1 :T.IpAddress;
    # Latency to this hop.
    latency @2 :T.Duration;
    # Hostname (if resolvable).
    hostname @3 :Text;
    metadata @4 :T.StringMap;
}

# ── Network Security (Firewall) ─────────────────────────────

struct FirewallRule {
    # Rule name for identification.
    name @0 :Text;
    # Whether the rule is enabled.
    enabled @1 :Bool;
    # Direction.
    direction @2 :FirewallDirection;
    # Protocol.
    # Transport as an open token.
    protocol @3 :Text;
    # Source address (empty = any).
    sourceAddress @4 :T.IpAddress;
    # Source port range (0..0 = any).
    sourcePortStart @5 :UInt16;
    sourcePortEnd @6 :UInt16;
    # Destination address (empty = any).
    destAddress @7 :T.IpAddress;
    # Destination port range (0..0 = any).
    destPortStart @8 :UInt16;
    destPortEnd @9 :UInt16;
    # Action.
    action @10 :FirewallAction;
    # Rule priority (lower = higher priority).
    priority @11 :UInt32;
    metadata @12 :T.StringMap;
}

enum FirewallDirection {
    inbound @0;
    outbound @1;
    both @2;
    custom @3;
}

enum FirewallAction {
    accept @0;
    drop @1;
    reject @2;
    log @3;
    custom @4;
}

struct NetworkConfig {
    # WiFi SSID or VPN profile id.
    ssid @0 :Text;
    # Reference to stored secret material — never the secret itself.
    credential @1 :T.SecretKeyId;
    # Identity (EAP).
    identity @2 :Text;
    # Security mode as an open token.
    security @3 :Text;
    # Whether hidden/non-broadcast SSID.
    hidden @4 :Bool;
    # Whether to use this as a remembered profile.
    remember @5 :Bool = true;
    # Whether to auto-connect when in range.
    autoConnect @6 :Bool = true;
    metadata @7 :T.StringMap;
}

# Security mode as an open token ("open", "wpa2", "wpa3", "sae", ...).
# The previous 11-value enum froze wep (already insecure) into an eternal
# contract and gave a 2046 enterprise auth method no value.

struct WifiNetwork {
    ssid @0 :Text;
    # AP MAC address (see the note under NetworkType).
    bssid @1 :T.MacAddress;
    # dBm signal strength.
    strength @2 :Int32;
    # Frequency in Hz.
    frequency @3 :UInt32;
    security @4 :Text;
    # Vendor OUI.
    vendor @5 :Text;
    # Whether hidden.
    hidden @6 :Bool;
    # 802.11 standard (e.g. "ax", "ac", "n").
    standard @7 :Text;
    metadata @8 :T.StringMap;
}

# ── VPN ─────────────────────────────────────────────────────

struct VpnProfile {
    id @0 :T.VpnProfileId;
    name @1 :Text;
    # Protocol as an open token.
    kind @2 :Text;
    server @3 :T.IpAddress;
    port @4 :T.Port;
    # Username + credential-handled-by-auth, not in spec for security.
    # Authentication method as an open token.
    authMethod @5 :Text;
    # Split-tunnel: which subnets go through the VPN.
    includedSubnets @6 :List(Subnet);
    excludedSubnets @7 :List(Subnet);
    # DNS servers used while connected.
    dnsServers @8 :List(DnsServer);
    # Whether auto-connect on boot.
    autoconnect @9 :Bool;
    # Friendly type name (e.g., "WireGuard").
    driverName @10 :Text;
    metadata @11 :T.StringMap;
}

# VPN protocol as an open token ("wireguard", "openvpn", ...): six
# product names, two of them already deprecated, were frozen here.

# Authentication method as an open token ("psk", "certificate", "oauth2", ...).

struct Subnet {
    address @0 :T.IpAddress;
    prefixLen @1 :UInt8;
    metadata @2 :T.StringMap;
}

struct VpnConnection {
    id @0 :T.VpnConnectionId;
    profileId @1 :T.VpnProfileId;
    state @2 :VpnState;
    startedAt @3 :T.Timestamp;
    bytesIn @4 :UInt64;
    bytesOut @5 :UInt64;
}

enum VpnState {
    connecting @0;
    authenticating @1;
    assigned @2;
    established @3;
    paused @4;
    reconnecting @5;
    disconnected @6;
    failed @7;
    custom @8;
}

# ── Hotspot ─────────────────────────────────────────────────

struct HotspotConfig {
    # Band as an open token.
    band @0 :Text;
    security @1 :Text;
    passphrase @2 :Text;
    # Whether hotspot is visible.
    hidden @3 :Bool;
    maxClients @4 :UInt32;
    # Bandwidth limit per client in kilobits per second (0 = unlimited).
    clientLimitKbps @5 :UInt32;
    # Client isolation (AP mode).
    clientIsolation @6 :Bool;
    metadata @7 :T.StringMap;
}

# Band as an open token ("2.4GHz", "5GHz", "6GHz", ...): spectrum
# allocation is political, not mathematical — 6 GHz is a 2020s regulator
# decision, not a constant of nature.

struct HotspotStatus {
    active @0 :Bool;
    band @1 :Text;
    ssid @2 :Text;
    connectedClients @3 :UInt32;
    bytesIn @4 :UInt64;
    bytesOut @5 :UInt64;
    metadata @6 :T.StringMap;
}

# ── DHCP ────────────────────────────────────────────────────

struct AddressAssignmentOptions {
    # Requested values as open tokens (what the caller wants assigned).
    requested @0 :List(Text);
    # Caller-declared overrides.
    overrides @1 :T.StringMap;
}

struct AddressAssignmentResult {
    union {
        assignment @0 :AddressAssignment;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

# What was assigned, by whom, and until when — the honest shape whichever
# mechanism produced it.
struct AddressAssignment {
    interface @0 :T.NetworkInterfaceId;
    # Address family as an open token ("ipv4", "ipv6").
    family @1 :Text;
    address @2 :T.IpAddress;
    prefixLen @3 :UInt8;
    gateway @4 :T.IpAddress;
    dnsServers @5 :List(T.IpAddress);
    dnsSearch @6 :List(Text);
    # The assigning server, if there was one.
    server @7 :T.IpAddress;
    issuedAt @8 :T.Timestamp;
    expiresAt @9 :T.Timestamp;
    renewedCount @10 :UInt32;
    # Assignment mechanism as an open token ("dhcp", "slaac", "static").
    mechanism @11 :Text;
    metadata @12 :T.StringMap;
}

enum AddressFamily {
    ipv4 @0;
    ipv6 @1;
    dual @2;
    custom @3;
}

struct DnsServer {
    address @0 :T.IpAddress;
    port @1 :T.Port;
    # DOH / DOT path (empty = doh/dot off).
    tlsHostname @2 :Text;
    dohPath @3 :Text;
    # Capability: TLS profile (h2/h3) enabled.
    tls @4 :Bool;
    # Authentication method (e.g., TSIG key name, mTLS client cert label).
    # Empty if unauthenticated.
    auth @5 :Text;
    metadata @6 :T.StringMap;
}

# ── QoS ─────────────────────────────────────────────────────

struct QosRule {
    # DSCP traffic class 0..63.
    dscp @0 :UInt8;
    # When this rule applies.
    match @1 :QosMatch;
    # Priority bucket the OS uses for queuing.
    priority @2 :Int8;
    # Bandwidth ceiling in kbps (0 = unlimited).
    ceilingKbps @3 :UInt32;
    # Latency target.
    latencyTarget @4 :T.Duration;
    metadata @5 :T.StringMap;
}

struct QosMatch {
    # Application or service ID; empty = global.
    applicationId @0 :T.AppId;
    portStart @1 :UInt16;
    portEnd @2 :UInt16;
    protocol @3 :Text;
    metadata @4 :T.StringMap;
}

# Transport as an open token ("tcp", "udp", "icmp", "sctp", "quic",
# "any", ...). A firewall rule that cannot name a future transport
# silently excludes it from security policy — the exact failure a closed
# enum produces here.

# ── Counters ────────────────────────────────────────────────

struct InterfaceCounters {
    bytesIn @0 :UInt64;
    bytesOut @1 :UInt64;
    packetsIn @2 :UInt64;
    packetsOut @3 :UInt64;
    errorsIn @4 :UInt64;
    errorsOut @5 :UInt64;
    dropsIn @6 :UInt64;
    dropsOut @7 :UInt64;
    # Last sample timestamp.
    sampledAt @8 :T.Timestamp;
}

# ── Captive portal ──────────────────────────────────────────

struct CaptivePortalState {
    state @0 :CaptivePortalStage;
    # Captive-portal URL (open in browser).
    loginUrl @1 :Text;
    # Detected network identity.
    network @2 :Text;
    # When the portal check was performed.
    checkedAt @3 :T.Timestamp;
    metadata @4 :T.StringMap;
}

enum CaptivePortalStage {
    unknown @0;
    noPortal @1;
    portalPending @2;
    signedIn @3;
    blocked @4;
    custom @5;
}

# ═══════════════════════════════════════════════════════════════════════
# v0.0.2 additions — Network Interface Provider (NIC driver)
#
# A NIC driver is a capability. The network stack consumes frames
# from it via buffer handles (see buffer.capnp); the driver pushes
# frames to its hardware. Swap driver backends (kernel module,
# virtio-net, userland DPDK, ...) without recompiling consumers.
# ═══════════════════════════════════════════════════════════════════════

interface NicProvider {
    # Identity + capabilities.
    getCapabilities @0 () -> (caps :NicCapabilities);
    # Open the link. The driver comes up (SMP-safe, DMA-ready, ...).
    open @1 () -> (result :T.VoidResult);
    close @2 () -> (result :T.VoidResult);
    # Receive the next batch of frames. The driver queues frames;
    # consumer drains.
    receive @3 () -> (frames :List(NicFrameDesc));
    # Submit frames for transmission.
    transmit @4 (frames :List(NicFrameDesc)) -> (result :T.VoidResult);
    # Statistics counters (driver-defined semantics).
    getCounters @5 () -> (counters :NicCounters);
    # Driver-side health ping.
    ping @6 () -> (health :T.DriverHealth);
}

struct NicCapabilities {
    # Maximum negotiated link speed in bit/s. The full set of speeds a
    # device can negotiate is backend detail, reported in `extras`.
    maxLinkSpeedBps @0 :UInt64;
    # Supported hardware offloads (TSO, checksum, RSS, ...).
    offloads @1 :List(Text);
    # Whether the device is capable of multipath (LACP, MLAG, ...).
    multipath @2 :Bool;
    # Whether the device can change its MAC address.
    macMutable @3 :Bool;
    # Permanent identifier when available (MAC, UUID, ...).
    permanentId @4 :Text;
    # MAC currently configured.
    currentMac @5 :Data;
    # MTU bounds.
    minMtu @6 :UInt32;
    maxMtu @7 :UInt32;
}

struct NicFrameDesc {
    # Backend-specific slot identifier within the provider's ring.
    bufferSlot @0 :UInt32;
    # The shared-memory buffer the frame lives in. THE zero-copy path:
    # the frame path is the highest-volume data path in the protocol, and
    # without this identity every backend invented its own
    # slot-to-memory agreement out of band.
    buffer @1 :T.BufferId;
    # Length in bytes (the driver honors this, not necessarily slot size).
    length @2 :UInt32;
    # Offset within the buffer where frame data starts.
    offset @3 :UInt32;
    # Checksum/length validation reported by hardware, as open tokens.
    flags @4 :List(Text);
    metadata @5 :T.StringMap;
}

struct NicCounters {
    rxPackets @0 :UInt64;
    txPackets @1 :UInt64;
    rxBytes @2 :UInt64;
    txBytes @3 :UInt64;
    rxErrors @4 :UInt64;
    txErrors @5 :UInt64;
    rxDropped @6 :UInt64;
    txDropped @7 :UInt64;
    # Driver-defined extras.
    extras @8 :List(NicCounterEntry);
    metadata @9 :T.StringMap;
}

struct NicCounterEntry {
    name @0 :Text;
    value @1 :UInt64;
    metadata @2 :T.StringMap;
}
