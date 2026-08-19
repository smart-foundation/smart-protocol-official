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
# Audit-9 improvements:
#   - SatelliteNetwork struct for satellite-specific fields.
#   - CellularConfig for signal band, carrier aggregation, SA/NSA.
#   - WifiNanConfig for Wi-Fi Aware (NAN) neighbor-aware networking.
#   - DtnBundle for DTN (delay-tolerant networking) store-and-forward.
#   - Ipv6Config for SLAAC, DHCPv6, address privacy extensions.
#   - Hotspot client filtering and bandwidth scheduling methods.
# ═══════════════════════════════════════════════════════════════════════

interface Network {
    # ── Interfaces ──
    getInterfaces @0 (pagination :T.Pagination) -> (interfaces :List(NetworkInterface));

    # ── Status ──
    getStatus @1 (interfaceId :T.NetworkInterfaceId) -> (status :ConnectionStatus);
    subscribeStatus @2 (interfaceId :T.NetworkInterfaceId) -> (subscription :StatusSubscription);
    pullStatus @3 (subscription :StatusSubscription) -> (status :ConnectionStatus);

    # ── Connect / disconnect ──
    connect @4 (interfaceId :T.NetworkInterfaceId, network :NetworkConfig) -> T.VoidResult;
    disconnect @5 (interfaceId :T.NetworkInterfaceId) -> T.VoidResult;

    # ── WiFi scan + connect ──
    wifiScan @6 (pagination :T.Pagination) -> (networks :List(WifiNetwork));
    # ssid is a user-facing WiFi network name, not a typed entity ID.
    wifiConnect @7 (ssid :Text, password :Text) -> T.VoidResult;
    wifiDisconnect @8 () -> T.VoidResult;
    wifiSetAutoConnect @9 (ssid :Text, enabled :Bool) -> T.VoidResult;
    wifiSetMacRandomization @10 (interfaceId :T.NetworkInterfaceId, enabled :Bool) -> T.VoidResult;

    # ── Bluetooth (legacy; see bluetooth.capnp for full controls) ──
    bluetoothScan @11 (pagination :T.Pagination) -> (devices :List(BluetoothDevice));
    bluetoothPair @12 (address :T.BluetoothAddress) -> T.VoidResult;
    bluetoothUnpair @13 (address :T.BluetoothAddress) -> T.VoidResult;

    # ── Cellular data ──
    setMobileData @14 (enabled :Bool) -> T.VoidResult;
    isMobileDataEnabled @15 () -> (enabled :Bool);
    setDataRoaming @16 (enabled :Bool) -> T.VoidResult;
    isDataRoamingEnabled @17 () -> (enabled :Bool);

    # ── VPN ──
    setVpnProfile @18 (profile :VpnProfile) -> T.VoidResult;
    removeVpnProfile @19 (profileId :T.VpnProfileId) -> T.VoidResult;
    listVpnProfiles @20 (pagination :T.Pagination) -> (profiles :List(VpnProfile));
    attachVpn @21 (profileId :T.VpnProfileId) -> (connection :VpnConnection);
    detachVpn @22 (connectionId :T.VpnConnectionId) -> T.VoidResult;
    listVpnConnections @23 (pagination :T.Pagination) -> (connections :List(VpnConnection));

    # ── Hotspot (tethering) ──
    startHotspot @24 (config :HotspotConfig) -> T.VoidResult;
    stopHotspot @25 () -> T.VoidResult;
    getHotspotStatus @26 () -> (status :HotspotStatus);
    subscribeHotspot @27 () -> (subscription :HotspotSubscription);
    pullHotspot @28 (subscription :HotspotSubscription) -> (status :HotspotStatus);

    # ── DHCP ──
    requestDhcpLease @29 (interfaceId :T.NetworkInterfaceId, options :DhcpOptions) -> T.VoidResult;
    getDhcpLease @30 (interfaceId :T.NetworkInterfaceId) -> (lease :DhcpLease);
    releaseDhcpLease @31 (interfaceId :T.NetworkInterfaceId) -> T.VoidResult;
    subscribeDhcp @32 (interfaceId :T.NetworkInterfaceId) -> (subscription :DhcpSubscription);
    pullDhcp @33 (subscription :DhcpSubscription) -> (lease :DhcpLease);

    # ── DNS (preferred servers) ──
    getDnsServers @34 (interfaceId :T.NetworkInterfaceId, pagination :T.Pagination) -> (servers :List(DnsServer));
    setDnsServers @35 (interfaceId :T.NetworkInterfaceId, servers :List(DnsServer)) -> T.VoidResult;

    # ── QoS / DSCP ──
    setInterfaceQos @36 (interfaceId :T.NetworkInterfaceId, qos :List(QosRule)) -> T.VoidResult;
    getInterfaceQos @37 (interfaceId :T.NetworkInterfaceId, pagination :T.Pagination) -> (rules :List(QosRule));

    # ── Counters ──
    getCounters @38 (interfaceId :T.NetworkInterfaceId, since :T.Duration) -> (counters :InterfaceCounters);
    resetCounters @39 (interfaceId :T.NetworkInterfaceId) -> T.VoidResult;
    subscribeCounters @40 (interfaceId :T.NetworkInterfaceId) -> (subscription :CounterSubscription);
    pullCounters @41 (subscription :CounterSubscription) -> (counters :InterfaceCounters);

    # ── Captive portal ──
    checkCaptivePortal @42 (interfaceId :T.NetworkInterfaceId) -> (state :CaptivePortalState);
    subscribeCaptivePortal @43 (interfaceId :T.NetworkInterfaceId) -> (subscription :CaptivePortalSubscription);
    pullCaptivePortal @44 (subscription :CaptivePortalSubscription) -> (state :CaptivePortalState);

    # ── Renaming / lifecycle ──
    renameInterface @45 (oldId :T.NetworkInterfaceId, newId :T.NetworkInterfaceId) -> T.VoidResult;
    upInterface @46 (interfaceId :T.NetworkInterfaceId) -> T.VoidResult;
    downInterface @47 (interfaceId :T.NetworkInterfaceId) -> T.VoidResult;

    # ── Network topology ──
    getTopology @48 (pagination :T.Pagination) -> (nodes :List(TopologyNode), links :List(TopologyLink), total :UInt64);

    # ── Network power management ──
    setPowerProfile @49 (interfaceId :T.NetworkInterfaceId, profile :NetworkPowerProfile) -> T.VoidResult;
    getPowerProfile @50 (interfaceId :T.NetworkInterfaceId) -> (profile :NetworkPowerProfile);

    # ── Network handoff ──
    handoff @51 (fromInterface :T.NetworkInterfaceId, toInterface :T.NetworkInterfaceId) -> T.VoidResult;

    # ── Network slicing ──
    createSlice @52 (config :SliceConfig) -> (sliceId :Text);
    removeSlice @53 (sliceId :Text) -> T.VoidResult;
    listSlices @54 (pagination :T.Pagination) -> (slices :List(NetworkSlice), total :UInt64);

    # ── Network telemetry ──
    getTelemetry @55 (interfaceId :T.NetworkInterfaceId, duration :T.Duration) -> (telemetry :NetworkTelemetry);
    subscribeTelemetry @56 (interfaceId :T.NetworkInterfaceId) -> (subscription :TelemetrySubscription);
    pullTelemetry @57 (subscription :TelemetrySubscription) -> (telemetry :NetworkTelemetry);

    # ── Network diagnostics ──
    ping @58 (target :T.IpAddress) -> (latency :T.Duration, packetLoss :Float32);
    traceroute @59 (target :T.IpAddress) -> (hops :List(TracerouteHop));

    # ── Network security (firewall) ──
    setFirewallRules @60 (interfaceId :T.NetworkInterfaceId, rules :List(FirewallRule)) -> T.VoidResult;
    getFirewallRules @61 (interfaceId :T.NetworkInterfaceId, pagination :T.Pagination) -> (rules :List(FirewallRule));

    # ── Network time sync ──
    getTimeSync @62 (interfaceId :T.NetworkInterfaceId) -> (offset :T.Duration, stratum :UInt8, source :Text);

    # ── Satellite ──
    getSatelliteConfig @63 () -> (config :SatelliteNetwork);

    # ── Hotspot enhancements ──
    setHotspotClientFilter @64 (macAddresses :List(T.BluetoothAddress)) -> T.VoidResult;
    getHotspotBandwidthSchedule @65 () -> (schedule :List(BandwidthSlot));
    setHotspotBandwidthSchedule @66 (schedule :List(BandwidthSlot)) -> T.VoidResult;

    # ── DTN (delay-tolerant networking) ──
    sendDtnBundle @67 (bundle :DtnBundle) -> T.VoidResult;
    receiveDtnBundles @68 (pagination :T.Pagination) -> (bundles :List(DtnBundle), total :UInt64);

    # ── Cellular configuration ──
    getCellularConfig @69 () -> (config :CellularConfig);
    setCellularConfig @70 (config :CellularConfig) -> T.VoidResult;

    # ── IPv6 configuration ──
    getIpv6Config @71 (interfaceId :T.NetworkInterfaceId) -> (config :Ipv6Config);
    setIpv6Config @72 (interfaceId :T.NetworkInterfaceId, config :Ipv6Config) -> T.VoidResult;

    # ── Wi-Fi Aware (NAN) ──
    wifiNanAdvertise @73 (config :WifiNanConfig) -> T.VoidResult;
    wifiNanDiscover @74 (config :WifiNanConfig) -> (peers :List(NanPeer), total :UInt32);
}

struct BandwidthSlot {
    startHour @0 :UInt8;
    endHour @1 :UInt8;
    maxKbps @2 :UInt32;
}

struct NanPeer {
    peerId @0 :Text;
    name @1 :Text;
    rssi @2 :Int32;
}

# ── Subscriptions ───────────────────────────────────────────

interface StatusSubscription {
    pull @0 () -> (status :ConnectionStatus);
    cancel @1 () -> T.VoidResult;
}

interface HotspotSubscription {
    pull @0 () -> (status :HotspotStatus);
    cancel @1 () -> T.VoidResult;
}

interface DhcpSubscription {
    pull @0 () -> (lease :DhcpLease);
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

struct NetworkInterface {
    id @0 :T.NetworkInterfaceId;
    name @1 :Text;
    type @2 :NetworkType;
    # Hardware / MAC address (typed for cross-platform compatibility).
    hwAddress @15 :T.BluetoothAddress;
    # List of `ipv4:NNN.NNN.NNN.NNN/NN` strings.
    ipAddresses @3 :List(T.IpAddress);
    # IPv6 addresses in CIDR.
    ipv6Addresses @4 :List(T.IpAddress);
    # Gateway (current).
    gateway @5 :T.IpAddress;
    # DNS servers already configured.
    dnsServers @6 :List(T.IpAddress);
    # Up / connected flags.
    up @7 :Bool;
    connected @8 :Bool;
    # MTU currently effective.
    mtU @9 :UInt32;
    # Speed in bits per second (0 = unknown).
    speedUp @10 :UInt64;
    speedDown @11 :UInt64;
    # Vendor/Driver of the underlying NIC.
    driver @12 :Text;
    # Whether MAC is randomized on the fly (WiFi/BT).
    macRandom @13 :Bool;
    # Per-app caps that can use this interface.
    requiredCaps @14 :List(CapRef);
    # Network slice this interface belongs to (empty = default/best-effort).
    sliceId @16 :Text;
    # Current power profile applied to this interface.
    powerProfile @17 :NetworkPowerProfile;
}

struct CapRef {
    capId @0 :Data;
}

enum NetworkType {
    unknown @0;
    ethernet @1;
    wifi @2;
    bluetooth @3;
    cellular @4;
    vpn @5;
    usb @6;
    thunderbolt @7;
    loopback @8;
    virtual @9;
    serial @10;
    satellite @11;
    # Device-to-device mesh (Zigbee, Thread, BLE mesh, Wi-Fi mesh).
    mesh @12;
    # Low-power wide-area (LoRa).
    lora @13;
    # Low-power wide-area (Sigfox).
    sigfox @14;
    # Low-power wide-area (NB-IoT / LTE-M).
    nbIoT @15;
    # BLE mesh networking.
    bleMesh @16;
    # Packet radio (AX.25, APRS, ham radio).
    packetRadio @17;
    # Multi-link bonding (Wi-Fi + cellular + Ethernet combined).
    multiLink @18;
    custom @19;
}

# ── Mesh Network ────────────────────────────────────────────

struct MeshNetwork {
    # Mesh network identifier.
    meshId @0 :Text;
    # Neighboring nodes directly reachable.
    neighbors @1 :List(T.NetworkInterfaceId);
    # Routing table entries.
    routingTable @2 :List(MeshRoute);
    # Mesh routing algorithm in use.
    routingAlgorithm @3 :MeshRoutingAlgorithm;
    # Self-healing: whether the mesh auto-recovers from node failures.
    selfHealing @4 :Bool;
}

struct MeshRoute {
    destination @0 :T.NetworkInterfaceId;
    nextHop @1 :T.NetworkInterfaceId;
    metric @2 :UInt32;
    # Route expiry (0 = static route, no expiry).
    expiry @3 :T.Timestamp;
}

enum MeshRoutingAlgorithm {
    flood @0;
    gossip @1;
    linkState @2;
    distanceVector @3;
    custom @4;
}

# ── Low-Power Wide-Area ─────────────────────────────────────

struct LoraNetwork {
    # Spreading factor (SF7..SF12). Higher = longer range, lower throughput.
    spreadingFactor @0 :UInt8;
    # Bandwidth in Hz (125000, 250000, 500000).
    bandwidthHz @1 :UInt32;
    # Estimated range in km.
    rangeKm @2 :Float32;
    # Coding rate (4/5, 4/6, 4/7, 4/8).
    codingRate @3 :UInt8;
    # Adaptive data rate enabled.
    adr @4 :Bool;
}

# ── BLE Mesh ────────────────────────────────────────────────

struct BleMeshNetwork {
    # Mesh network name.
    meshName @0 :Text;
    # Total node count in the mesh.
    nodeCount @1 :UInt32;
    # Relay node count.
    relayCount @2 :UInt32;
    # Proxy node count.
    proxyCount @3 :UInt32;
    # Friend node count.
    friendCount @4 :UInt32;
}

# ── Packet Radio ────────────────────────────────────────────

struct PacketRadioNetwork {
    # Callsign (e.g., "W1AW").
    callsign @0 :Text;
    # Protocol identifier (e.g., "AX.25", "APRS").
    protocol @1 :Text;
    # Frequency in MHz.
    frequencyMHz @2 :Float32;
    # Modulation (e.g., "AFSK", "FSK").
    modulation @3 :Text;
}

# ── Multi-Link Bonding ──────────────────────────────────────

struct MultiLinkConfig {
    # Interfaces participating in the bond.
    interfaces @0 :List(T.NetworkInterfaceId);
    # Bonding strategy.
    strategy @1 :BondingStrategy;
    # Failover threshold: max packet loss % before switching.
    failoverThreshold @2 :Float32;
    # Health check interval for link monitoring.
    healthCheckInterval @3 :T.Duration;
}

enum BondingStrategy {
    roundRobin @0;
    leastLatency @1;
    failover @2;
    weighted @3;
    loadBalanced @4;
    custom @5;
}

# ── Connection Status ───────────────────────────────────────
# WiFi-specific fields are isolated in WifiStatus to avoid
# leaking WiFi concepts into generic connection status.

struct ConnectionStatus {
    connected @0 :Bool;
    interface @1 :T.NetworkInterfaceId;
    type @2 :NetworkType;
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
    qualityMetrics @10 :QualityMetrics;
}

struct WifiStatus {
    ssid @0 :Text;
    # AP MAC address (typed for cross-platform compatibility).
    bssid @1 :T.BluetoothAddress;
    # Frequency in Hz (e.g., 2412000000 for 2.4GHz channel 1).
    frequency @2 :UInt32;
    # Roaming hint (AP is weak, roaming in progress).
    roaming @3 :Bool;
}

# ── Network Quality Metrics ─────────────────────────────────

struct QualityMetrics {
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
    orbitType @1 :OrbitType;
    # Expected latency in milliseconds.
    expectedLatencyMs @2 :UInt32;
    # Whether the satellite link is currently active.
    active @3 :Bool;
}

enum OrbitType {
    leo @0;
    meo @1;
    geo @2;
    custom @3;
}

# ── Cellular Configuration ───────────────────────────────────────────────

struct CellularConfig {
    # Signal band (e.g., "n78" for 5G, "B2" for LTE).
    band @0 :Text;
    # Carrier name.
    carrier @1 :Text;
    # Whether SA (standalone) or NSA (non-standalone) mode.
    saMode @2 :SaMode;
    # Supported carrier aggregation bands.
    carrierAggregationBands @3 :List(Text);
}

enum SaMode {
    nsa @0;
    sa @1;
    custom @2;
}

# ── Wi-Fi Aware (NAN) ───────────────────────────────────────────────────

struct WifiNanConfig {
    # Service name for NAN discovery.
    serviceName @0 :Text;
    # Whether to publish or subscribe.
    role @1 :NanRole;
    # TTL in milliseconds.
    ttlMs @2 :UInt32;
}

enum NanRole {
    publish @0;
    subscribe @1;
    custom @2;
}

# ── DTN (Delay-Tolerant Networking) ─────────────────────────────────────

struct DtnBundle {
    # Bundle identifier.
    bundleId @0 :Text;
    # Source node.
    source @1 :Text;
    # Destination node.
    destination @2 :Text;
    # Payload data.
    payload @3 :Data;
    # Bundle lifetime.
    lifetime @4 :T.Duration;
    # Custody transfer enabled.
    custodyTransfer @5 :Bool;
}

# ── IPv6 Configuration ───────────────────────────────────────────────────

struct Ipv6Config {
    # Whether SLAAC is enabled.
    slaacEnabled @0 :Bool;
    # Whether DHCPv6 is enabled.
    dhcpv6Enabled @1 :Bool;
    # Address privacy extensions (RFC 4941) enabled.
    privacyExtensions @2 :Bool;
    # Prefix for SLAAC-derived addresses.
    prefix @3 :Text;
    # Prefix length.
    prefixLen @4 :UInt8;
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
}

# ── Network Power Management ────────────────────────────────

enum NetworkPowerProfile {
    # Always on, maximum performance.
    performance @0;
    # Balanced between power and performance.
    balanced @1;
    # Battery saver: reduced scan intervals, lower transmit power.
    batterySaver @2;
    # Ultra-low power: minimal radio usage.
    ultraLowPower @3;
    # Custom power profile.
    custom @4;
}

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
    sliceId @0 :Text;
    name @1 :Text;
    isolation @2 :SliceIsolation;
    minBandwidthBps @3 :UInt64;
    maxLatency @4 :T.Duration;
    priority @5 :UInt8;
    # Whether the slice is currently active.
    active @6 :Bool;
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

struct TracerouteHop {
    # Hop number (1-based).
    hop @0 :UInt8;
    # Address of this hop.
    address @1 :T.IpAddress;
    # Latency to this hop.
    latency @2 :T.Duration;
    # Hostname (if resolvable).
    hostname @3 :Text;
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
    protocol @3 :TransportProtocol;
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
    password @1 :Text;
    # Identity (EAP).
    identity @2 :Text;
    security @3 :WifiSecurity;
    # Whether hidden/non-broadcast SSID.
    hidden @4 :Bool;
    # Whether to use this as a remembered profile.
    remember @5 :Bool = true;
    # Whether to auto-connect when in range.
    autoConnect @6 :Bool = true;
}

enum WifiSecurity {
    open @0;
    wep @1;
    wpa @2;
    wpa2 @3;
    wpa3 @4;
    owe @5;
    enhancedOpen @6;
    sae @7;
    wpa3Enterprise @8;
    eapPwd @9;
    eapTtls @10;
    custom @11;
}

struct WifiNetwork {
    ssid @0 :Text;
    # AP MAC address (typed for cross-platform compatibility).
    # Matches WifiStatus.bssid type — scan results normalized to typed address.
    bssid @1 :T.BluetoothAddress;
    # dBm signal strength.
    strength @2 :Int32;
    # Frequency in Hz.
    frequency @3 :UInt32;
    security @4 :WifiSecurity;
    # Vendor OUI.
    vendor @5 :Text;
    # Whether hidden.
    hidden @6 :Bool;
    # 802.11 standard (e.g. "ax", "ac", "n").
    standard @7 :Text;
}

struct BluetoothDevice {
    # Bluetooth address (typed for cross-platform compatibility).
    address @0 :T.BluetoothAddress;
    name @1 :Text;
    paired @2 :Bool;
    connected @3 :Bool;
    # Bluetooth class-of-device 24-bit field.
    deviceClass @4 :UInt32;
    # Trusted=yes means pairing persists and runs at boot.
    trusted @5 :Bool;
    # Battery if known (0..100, 0xFF = unknown).
    batteryPercent @6 :UInt8;
}

# ── VPN ─────────────────────────────────────────────────────

struct VpnProfile {
    id @0 :T.VpnProfileId;
    name @1 :Text;
    kind @2 :VpnKind;
    server @3 :T.IpAddress;
    port @4 :T.Port;
    # Username + credential-handled-by-auth, not in spec for security.
    authMethod @5 :VpnAuthMethod;
    # Split-tunnel: which subnets go through the VPN.
    includedSubnets @6 :List(Subnet);
    excludedSubnets @7 :List(Subnet);
    # DNS servers used while connected.
    dnsServers @8 :List(DnsServer);
    # Whether auto-connect on boot.
    autoconnect @9 :Bool;
    # Friendly type name (e.g., "WireGuard").
    driverName @10 :Text;
}

enum VpnKind {
    wireguard @0;
    openvpn @1;
    ikev2 @2;
    ipsec @3;
    l2tp @4;
    pptp @5;
    ss @6;
    custom @7;
}

enum VpnAuthMethod {
    psk @0;
    certificate @1;
    oauth2 @2;
    usernamePassword @3;
    none @4;
    custom @5;
}

struct Subnet {
    address @0 :T.IpAddress;
    prefixLen @1 :UInt8;
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
    band @0 :WifiBand;
    security @1 :WifiSecurity;
    passphrase @2 :Text;
    # Whether hotspot is visible.
    hidden @3 :Bool;
    maxClients @4 :UInt32;
    # Bandwidth limit per client in kilobits per second (0 = unlimited).
    clientLimitKbps @5 :UInt32;
    # Client isolation (AP mode).
    clientIsolation @6 :Bool;
}

enum WifiBand {
    band24GHz @0;   # was: band2_4GHz
    band5GHz @1;
    band6GHz @2;
    dualBand @3;
    custom @4;
}

struct HotspotStatus {
    active @0 :Bool;
    band @1 :WifiBand;
    ssid @2 :Text;
    connectedClients @3 :UInt32;
    bytesIn @4 :UInt64;
    bytesOut @5 :UInt64;
}

# ── DHCP ────────────────────────────────────────────────────

struct DhcpOptions {
    requested @0 :List(Text);
    overrides @1 :T.StringMap;
}

struct DhcpLease {
    interface @0 :T.NetworkInterfaceId;
    family @1 :AddressFamily;
    address @2 :T.IpAddress;
    prefixLen @3 :UInt8;
    gateway @4 :T.IpAddress;
    dnsServers @5 :List(T.IpAddress);
    dnsSearch @6 :List(Text);
    server @7 :T.IpAddress;
    issuedAt @8 :T.Timestamp;
    expiresAt @9 :T.Timestamp;
    renewedCount @10 :UInt32;
    # DHCP server class-id.
    vendorClass @11 :Text;
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
}

struct QosMatch {
    # Application or service ID; empty = global.
    applicationId @0 :T.AppId;
    portStart @1 :UInt16;
    portEnd @2 :UInt16;
    protocol @3 :TransportProtocol;
}

enum TransportProtocol {
    tcp @0;
    udp @1;
    icmp @2;
    sctp @3;
    quic @4;
    any @5;
    custom @6;
}

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
    # Link speeds in bit/s the device negotiates (max-visible).
    linkSpeedsBps @0 :List(UInt64);
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
    # Backend-specific slot/handle. Buffer is identity-anchored on the
    # provider side; this is a ring slot identifier, not a buffer
    # handle. Use buffer.capnp to share the underlying memory.
    bufferSlot @0 :UInt32;
    # Length in bytes (the driver honors this, not necessarily slot size).
    length @1 :UInt32;
    # Offset within the slot where frame data starts.
    offset @2 :UInt32;
    # Checksum/length validation reported by hardware if known.
    flags @3 :UInt32;
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
}

struct NicCounterEntry {
    name @0 :Text;
    value @1 :UInt64;
}
