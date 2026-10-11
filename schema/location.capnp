@0xa1b2c3d4e5f60016;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Location - position, heading, and speed
#
# Backend-agnostic location service. Works over GPS, Wi-Fi positioning,
# Bluetooth beacons, cell tower triangulation, or any future method.
# The protocol describes what data looks like, not how it is derived.
#
# Physical quantity units:
#   - latitude / longitude: WGS84 degrees (positive = north/east)
#   - altitude: meters above WGS84 ellipsoid
#   - accuracy / altitudeAccuracy: meters (1-sigma)
#   - heading: degrees clockwise from true north (0-360)
#   - speed: meters per second
#
# Audit-9 improvements:
#   - LocationRef for embedding location in event structs across protocol.
#   - PrivacyLevel enum for user-controlled location granularity.
#   - AccuracyZone for per-zone accuracy requirements.
#   - getLocationsBatch for efficient batch queries.
# ═══════════════════════════════════════════════════════════════════════

# ── Location Reference (embeddable in events) ───────────────────────────

struct LocationRef {
    # Timestamp of this location.
    timestamp @0 :T.Timestamp;
    # Location snapshot.
    location @1 :LocationData;
}

# ── Privacy Level ────────────────────────────────────────────────────────

enum PrivacyLevel {
    # Coarse: city-level only.
    coarse @0;
    # Fine: street-level.
    fine @1;
    # Exact: full precision.
    exact @2;
    # None: location sharing disabled.
    none @3;
    custom @4;
}

# ── Accuracy Zone ────────────────────────────────────────────────────────

struct AccuracyZone {
    # Zone identifier.
    zoneId @0 :Text;
    # Accuracy level required in this zone.
    accuracy @1 :LocationAccuracy;
    # Whether this zone requires indoor positioning.
    requiresIndoor @2 :Bool;
}

# ── Locations ─────────────────────────────────────────────────────────────

interface Locations {
    getLocation @0 () -> (location :LocationData);
    subscribeLocation @1 () -> (subscription :LocationSubscription);
    pullLocation @2 (subscription :LocationSubscription) -> (location :LocationData);

    setEnabled @3 (enabled :Bool) -> T.VoidResult;
    getEnabled @4 () -> (enabled :Bool);

    getStatus @5 () -> (status :LocationStatus);

    setAccuracy @6 (accuracy :LocationAccuracy) -> T.VoidResult;
    setUpdateInterval @7 (interval :T.Duration) -> T.VoidResult;

    # Audit-7: location history with bounded pagination.
    getHistory @8 (filter :LocationHistoryFilter, page :T.Pagination) -> (locations :List(LocationData), total :UInt32);

    # Audit-7: geo-fence registration and monitoring.
    registerGeoFence @9 (fence :GeoFence) -> (id :Text);
    unregisterGeoFence @10 (id :Text) -> T.VoidResult;
    getGeoFenceEvents @11 (page :T.Pagination) -> (events :List(GeoFenceEvent), total :UInt32);

    # Audit-7: E2E-encrypted location sharing.
    shareLocation @12 (targetDeviceId :T.DeviceId) -> T.VoidResult;

    # Audit-9: Batch location query.
    getLocationsBatch @13 (ids :List(Text), page :T.Pagination)
        -> (locations :List(LocationData), total :UInt32);

    # Audit-9: Privacy level control.
    setPrivacyLevel @14 (level :PrivacyLevel) -> T.VoidResult;
    getPrivacyLevel @15 () -> (level :PrivacyLevel);

    # Audit-10: Accuracy zone management.
    setAccuracyZone @16 (zone :AccuracyZone) -> T.VoidResult;
    getAccuracyZone @17 (zoneId :Text) -> (zone :AccuracyZone);
    listAccuracyZones @18 (pagination :T.Pagination) -> (zones :List(AccuracyZone), total :UInt32);
    deleteAccuracyZone @19 (zoneId :Text) -> T.VoidResult;

    # Audit-10: Geo-fence attestation.
    #
    # The previous signature took `privateKey :Data` in the request body.
    # A private key must never cross into a service: the service can
    # only misuse it, and on hardware where the key cannot be exported
    # at all (a secure element, a TPM, a future equivalent) the method
    # was simply unimplementable — on exactly the hardware that most
    # needs attestation. It also had no statement of custody and no key
    # identifier, so nothing said which key signed or who held it.
    #
    # The key now stays where it lives and is named by an opaque handle:
    # the location service asks the key owner to sign through
    # key_management.capnp, and returns a reference to the signature
    # rather than producing one itself.
    attestGeoFence @20 (fenceId :Text, location :LocationData, key :T.KeyId)
        -> (result :GeoFenceAttestationResult);
    verifyGeoFenceAttestation @21 (attestation :GeoFenceAttestation)
        -> (result :GeoFenceVerificationResult);
}

interface LocationSubscription {
    pull @0 () -> (location :LocationData);
    cancel @1 () -> T.VoidResult;
}

struct LocationData {
    # WGS84 latitude in degrees (positive = north, negative = south).
    latitude @0 :Float64;
    # WGS84 longitude in degrees (positive = east, negative = west).
    longitude @1 :Float64;
    # Altitude in meters above the WGS84 ellipsoid.
    # Note: This is geometric height above the reference ellipsoid,
    # NOT height above mean sea level (MSL). The distinction matters
    # for aviation and surveying applications.
    altitude @2 :Float64;
    # Horizontal accuracy in meters (1-sigma radius).
    accuracy @3 :Float32;
    # Vertical accuracy in meters (1-sigma).
    altitudeAccuracy @4 :Float32;
    # Heading in degrees clockwise from true north (0-360).
    # NaN if heading is unknown or device is stationary.
    heading @5 :Float32;
    # Speed in meters per second.
    speed @6 :Float32;
    timestamp @7 :T.Timestamp;
    # Which positioning method produced this location
    # (GPS, Wi-Fi, cell tower, fused, etc.).
    source @8 :T.LocationSourceId;

    # Audit-7: extended location data fields.
    # Building floor number (0 = ground floor, negative = basement).
    floor @9 :Int32;
    # Indoor positioning data (BLE beacon, ultrasound, Wi-Fi RTT).
    indoor @10 :IndoorPosition;
    # AR/VR spatial pose (6DoF position + orientation).
    spatialPose @11 :T.SpatialPose;
    # Signal-strength fingerprint for indoor matching.
    fingerprint @12 :Data;
    # Positioning mode indicator.
    positioningMode @13 :PositioningMode;
}

struct LocationStatus {
    enabled @0 :Bool;
    accuracy @1 :LocationAccuracy;
    updateInterval @2 :T.Duration;
    lastUpdate @3 :T.Timestamp;
    # Which positioning method is currently active.
    activeSource @4 :T.LocationSourceId;
}

enum LocationAccuracy {
    best @0;
    high @1;
    medium @2;
    low @3;
    minimal @4;
    custom @5;
}

# ═══════════════════════════════════════════════════════════════════════
# Audit-7: Extended location capabilities
#
# Indoor positioning, AR/VR spatial pose, geo-fence attestation,
# location history, and location sharing. These extend the
# outdoor-only GPS model to support modern positioning needs.
# ═══════════════════════════════════════════════════════════════════════

# ── Positioning Mode ──────────────────────────────────────────

enum PositioningMode {
    outdoor @0;         # GPS/satellite positioning
    indoor @1;          # BLE beacon, ultrasound, Wi-Fi RTT
    blended @2;         # Outdoor/indoor seamless transition
    spatial @3;         # AR/VR 6DoF spatial positioning
    custom @4;
}

# ── Indoor Positioning ────────────────────────────────────────

struct IndoorPosition {
    method @0 :IndoorMethod;
    # BLE beacon identifiers used for trilateration.
    beacons @1 :List(Text);
    # Wi-Fi access point identifiers used for RTT.
    wifiAps @2 :List(Text);
    # Magnetic field fingerprint (for magnetic positioning).
    magneticSignature @3 :Data;
    # Horizontal accuracy in meters (indoor).
    horizontalAccuracy @4 :Float32;
    # Vertical accuracy in meters (floor-level).
    verticalAccuracy @5 :Float32;
}

enum IndoorMethod {
    bleBeacon @0;       # BLE beacon trilateration
    ultrasound @1;      # Ultrasound time-of-flight
    wifiRtt @2;         # Wi-Fi RTT (802.11mc)
    magnetic @3;        # Magnetic field fingerprinting
    uwb @4;             # Ultra-wideband
    hybrid @5;          # Multiple methods combined
    custom @6;
}

# ── AR/VR Spatial Pose ────────────────────────────────────────


# ── Geo-Fence ─────────────────────────────────────────────────

struct GeoFence {
    # Human-readable fence name.
    name @0 :Text;
    # Fence geometry (center + radius for circular, polygon for complex).
    geometry @1 :GeoFenceGeometry;
    # Actions to trigger on enter/exit.
    onEnter @2 :Text;
    onExit @3 :Text;
    # Whether this fence is currently active.
    active @4 :Bool;
}

struct GeoFenceGeometry {
    union {
        circle @0 :GeoFenceCircle;
        polygon @1 :GeoFencePolygon;
        custom @2 :Data;
    }
}

struct GeoFenceCircle {
    centerLat @0 :Float64;
    centerLon @1 :Float64;
    radiusMeters @2 :Float32;
}

struct GeoFencePolygon {
    points @0 :List(T.Vec2);
}

struct GeoFenceEvent {
    fenceId @0 :Text;
    fenceName @1 :Text;
    event @2 :GeoFenceEventType;
    timestamp @3 :T.Timestamp;
    # Location at the time of the event.
    location @4 :LocationData;
}

enum GeoFenceEventType {
    entered @0;
    exited @1;
    dwell @2;           # Stayed inside for threshold duration
    custom @3;
}

# ── Location History ──────────────────────────────────────────

struct LocationHistoryFilter {
    # Start of time range (inclusive).
    since @0 :T.Timestamp;
    # End of time range (exclusive).
    until @1 :T.Timestamp;
    # Only locations from these sources.
    sources @2 :List(T.LocationSourceId);
    # Minimum accuracy (discard less accurate points).
    maxAccuracy @3 :Float32;
}

# ── Geo-Fence Attestation ─────────────────────────────────────

struct GeoFenceAttestation {
    # Fence identifier.
    fenceId @0 :Text;
    # Location at time of attestation.
    location @1 :LocationData;
    # Timestamp of attestation.
    timestamp @2 :T.Timestamp;
    # Reference to the produced signature. Opaque and backend-decided:
    # how the signature is encoded is crypto.capnp's business, not a
    # location contract's, and a 2046 post-quantum scheme needs no new
    # string here.
    signature @3 :Data;
    # The key that signed, as an opaque T.KeyId reference.
    key @4 :T.KeyId;
}

struct GeoFenceAttestationResult {
    union {
        ok @0 :GeoFenceAttestation;
        error @1 :T.Error;
    }
}

struct GeoFenceVerificationResult {
    union {
        ok @0 :Void;
        error @1 :T.Error;
    }
}
