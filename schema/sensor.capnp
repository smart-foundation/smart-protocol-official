@0xa1b2c3d4e5f60050;

# ═══════════════════════════════════════════════════════════════════════
# Sensor — physical sensor discovery, data streaming, batching, fusion.
#
# Improvements beyond the original schema:
#   - SensorId uses T.SensorId (was raw UInt64).
#   - SensorInfo.version uses T.Version (was raw UInt32).
#   - SensorSubscription and BatchSubscription have cancel methods.
#   - listSensors uses T.Pagination for bounded results.
#   - Removed orphan Subscription interface.
#   - Fixed flush method to use SensorSubscription (was undefined Subscription).
#   - SensorAccuracy, SamplingRate have custom variants.
#   - latencyHint uses T.Duration (audit-3, replaces raw UInt32 microseconds).
#   - getSensorsByType and isAvailable now return total counts (audit-4).
#   - SensorSubscription.pull and BatchSubscription.pull accept T.Pagination
#     for bounded result sets (audit-5, Rule 9).
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using import "capability.capnp".Capability;

# ── Sensor Types ─────────────────────────────────────────────────────────

# ── Sensor class: an OPEN TOKEN, was a 44-value enum ───────────────────
#
# The enum's own history is the proof it was closed by release
# schedules rather than by mathematics: Audit-7 appended fourteen values
# in one revision (gnss, airQuality, fallDetection, lidar, tof, radar,
# gesture, spectrometer, gas, radiation, soil, waterQuality, acoustic,
# strain). A 2046 sensor class — bioimpedance, electrochemical, a
# quantum magnetometer — must either add an ordinal to an eternal
# schema or answer `custom @43`, a bare ordinal carrying no semantics.
# The concrete costs were: `getSensorsByType` could not ask for a class
# the enum lacked, and every consumer with a `switch (type)` had to be
# recompiled to support new hardware.
#
# The machine-readable half of a sensor class never needed the enum:
# `units` and `axisLabels` are already open per-sensor descriptors, so
# "what does this number mean" is answered from the device. What the
# enum added was only a filterable NAME — which is exactly what an open
# token gives, with no ordinal.
#
# Documented vocabulary (not exhaustive, not checked):
#   "accelerometer", "gyroscope", "magnetometer", "barometer",
#   "proximity", "ambientLight", "heartRate", "stepCounter",
#   "stepDetector", "gravity", "linearAcceleration", "rotationVector",
#   "pose6Dof", "motionDetect", "humidity", "temperature", "pressure",
#   "uv", "gnss", "airQuality", "fallDetection", "lidar", "tof",
#   "radar", "gesture", "spectrometer", "gas", "radiation", "soil",
#   "waterQuality", "acoustic", "strain"
# An unrecognised token is ignored, never rejected (ai.capnp:43-47).

# ── Sensor Info ─────────────────────────────────────────────────────────

struct SensorInfo {
    id @0 :T.SensorId;
    name @1 :Text;
    vendor @2 :Text;
    # Open class token — see the SensorType note above.
    type @3 :Text;
    version @4 :T.Version;
    # Maximum sampling rate in Hz.
    maxRate @5 :UInt32;
    # Minimum sampling rate in Hz.
    minRate @6 :UInt32;
    # Sensor resolution in native units (see units field).
    resolution @7 :Float32;
    # Maximum range in native units (see units field).
    maxRange @8 :Float32;
    # Power consumption in milliamperes.
    powerMa @9 :Float32;
    wakeUp @10 :Bool;

    # Human-readable axis names for multi-axis sensors.
    # Example: ["x", "y", "z"] for accelerometer.
    axisLabels @11 :List(Text);
    # Units string (e.g., "m/s^2", "µT", "lux").
    units @12 :Text;
    # Whether this sensor stops when screen turns off.
    offWhenScreenOff @13 :Bool;
    # Maximum readings that can be batched before delivery.
    maxBatchSize @14 :UInt16;
    # For wake-up sensors: what triggered the wake.
    triggerData @15 :Text;
    # The capability that must be held to read this sensor, as a
    # capability REFERENCE. The previous `permissionCapability :Text`
    # named a capability by string, which DESIGN_PRINCIPLES.md:399
    # forbids ("The capability system IS the access control
    # mechanism"), and no method in the file accepted a Capability —
    # so the string was a dead end: a client learned it must hold
    # "sensor.heartrate" and then had nothing to present.
    # `SensorService.openStreams` is where the reference is presented.
    authority @16 :Capability;
    # Whether sensor is currently enabled.
    enabled @17 :Bool;
    # DEPRECATED: Use latencyHint instead. Latency hint in microseconds.
    latencyHintUs @18 :UInt32;
    # Latency hint for batched delivery (preferred over latencyHintUs).
    latencyHint @19 :T.Duration;
}

struct SensorHandle {
    id @0 :T.SensorId;
    name @1 :Text;
}

# ── Sensor Data ──────────────────────────────────────────────────────────

struct SensorReading {
    sensorId @0 :T.SensorId;
    timestamp @1 :T.Timestamp;
    values @2 :List(Float32);
    accuracy @3 :SensorAccuracy;
    # Batch marker: number of flushed readings in this payload.
    # When batchCount > 1, values contains concatenated readings.
    batchCount @4 :UInt16;
    # Per-subscription monotonic sequence, starting at 1. A consumer
    # that records the last sequence it processed can measure loss
    # exactly, so a dropped reading is visible instead of silent.
    sequence @5 :UInt64;
}

enum SensorAccuracy {
    unreliable @0;
    low @1;
    medium @2;
    high @3;
    highest @4;
    custom @5;
}

# ── Sampling Rate ────────────────────────────────────────────────────────

enum SamplingRate {
    normal @0;
    ui @1;
    game @2;
    fastest @3;
    custom @4;
}

# ── Service ───────────────────────────────────────────────────────────────

interface SensorService {
    listSensors @0 (pagination :T.Pagination)
                -> (sensors :List(SensorInfo), total :UInt32);

    getInfo @1 (sensorId :T.SensorId) -> (info :SensorInfo);

    # Subscribe at a named rate.
    subscribe @2 (sensorId :T.SensorId, rate :SamplingRate)
              -> (subscription :SensorSubscription);

    # Subscribe at a custom rate in Hz.
    subscribeCustom @3 (sensorId :T.SensorId, rateHz :UInt32)
                    -> (subscription :SensorSubscription);

    # Pull latest readings (non-blocking). Convenience path — it reads
    # the SAME queue as SensorSubscription.pull, and the canonical pull
    # is on the subscription interface (DESIGN_PRINCIPLES.md:254).
    pull @4 (subscription :SensorSubscription, maxCount :UInt32, cursor :SequenceToken)
           -> (result :ReadingPullResult);

    unsubscribe @5 (subscription :SensorSubscription) -> T.VoidResult;

    # Cheapest possible "is there one": no descriptors, just a yes and a count.
    isAvailable @6 (type :Text, pagination :T.Pagination)
                -> (available :Bool, sensors :List(SensorHandle), total :UInt32);

    # All sensors of a given class token (for multi-sensor devices).
    # Filters on the open class token, so a 2046 sensor class is
    # searchable the day it ships, with no ordinal.
    getSensorsByType @7 (type :Text, pagination :T.Pagination)
                     -> (sensors :List(SensorHandle), total :UInt32);

    # Subscribe multiple sensors at once (for time-synchronized reads).
    subscribeBatch @8 (requests :List(SubscribeRequest))
                   -> (subscription :BatchSubscription);

    # Flush pending readings for a subscription (forces delivery).
    flush @9 (subscription :SensorSubscription) -> T.VoidResult;

    # Enable/disable a sensor.
    enable @10 (sensorId :T.SensorId, enabled :Bool) -> T.VoidResult;

    # Audit-7: GNSS multi-constellation fix.
    getGnssFix @11 () -> (fix :GnssFix);

    # Audit-7: air quality measurement.
    getAirQuality @12 () -> (aqi :AirQualityIndex);

    # Audit-7: fall detection status.
    getFallDetection @13 () -> (detection :FallDetection);

    # Audit-7: sensor calibration management.
    getCalibration @14 (sensorId :T.SensorId) -> (calibration :SensorCalibration);
    calibrate @15 (sensorId :T.SensorId) -> T.VoidResult;

    # Audit-7: multi-sensor fusion configuration.
    getFusionConfig @16 () -> (config :SensorFusionConfig);
    setFusionConfig @17 (config :SensorFusionConfig) -> T.VoidResult;

    # ── Biometric sensor management (audit-9 What's Still Missing) ──
    getBiometricSensorInfo @18 (sensorId :T.SensorId) -> (info :BiometricSensorInfo);
    authenticateBiometric @19 (sensorId :T.SensorId) -> (result :BiometricAuthResult);

    # ── Sensor event subscription (audit-9 What's Still Missing) ──
    subscribeEvents @20 (filter :SensorEventFilter) -> (subscription :SensorEventSubscription);

    # ── Sensor fusion algorithm query (audit-9 What's Still Missing) ──
    listFusionAlgorithms @21 () -> (algorithms :List(SensorFusionAlgorithm));
}

struct SubscribeRequest {
    sensorId @0 :T.SensorId;
    # DEPRECATED: Use rate instead. Bare Hz value cannot represent fractional rates
    # (e.g., 0.5 Hz for slow environmental sensors).
    rateHz @1 :UInt32;
    # Typed sampling rate configuration (preferred over rateHz).
    # Supports fractional rates via T.Frequency for slow sensors.
    rate @2 :SamplingRateConfig;
}

# Typed sampling rate configuration. Replaces bare UInt32 rateHz
# to support fractional rates (e.g., 0.5 Hz) and named presets.
struct SamplingRateConfig {
    union {
        # Named rate preset (normal, ui, game, fastest).
        preset @0 :SamplingRate;
        # Custom rate in Hz. Supports fractional values (e.g., 0.5 = one reading per 2 seconds).
        hz @1 :T.Frequency;
        custom @2 :Data;
    }
}

# ═══════════════════════════════════════════════════════════════════════
# READING DELIVERY — why these take a bound and a cursor, not an offset.
#
# `T.Pagination { offset, limit }` is an offset into a STABLE list. A
# live sensor stream has no stable list, so `pull (offset=5, limit=10)`
# has no defined meaning: a backend may skip the first 5 readings
# (losing them) or return 10 from the newest — silently, with no way
# for the caller to tell. The same defect was found at nine sites across
# the protocol (sensor, camera, capture, usb, bluetooth, capability).
#
# The bound is wanted; the offset is meaningless. So:
#
#   * `maxCount` — the caller states how much it will accept, exactly
#     as ai.capnp:277's `pull (maxBytes)` does. This bounds the
#     server-side queue and stops a slow consumer's next pull from
#     materialising an unbounded message.
#
#   * `cursor` — an opaque, per-subscription sequence token returned by
#     each pull. It is NOT a count and NOT an offset: a backend may
#     encode whatever it needs (the ring position, the queue head, a
#     generation counter). The contract is only that passing it back
#     resumes exactly where the previous pull stopped, and that a
#     consumer that never passes a cursor gets a fresh, contiguous run.
#     Because it is opaque, a backend is free to change its internal
#     queue representation without breaking a caller.
#
#   * `readings` carries an explicit `sequence` per reading so that a
#     GAP is measurable. If the last sequence a consumer processed was
#     412 and the next pull starts at 415, three readings were dropped
#     — which the consumer can see, report, and act on, instead of
#     silently misinterpreting its own sample rate.
#
#   * `T.SubscriptionResult`'s `ended`/`error` (types.capnp:907) tell a
#     dead sensor apart from a quiet one. A bare list return made them
#     the same fact.
# ═══════════════════════════════════════════════════════════════════════

struct ReadingPullResult {
    union {
        # At most maxCount readings, in sequence order.
        readings @0 :List(SensorReading);
        # Nothing has arrived yet. Not an error.
        empty @1 :Void;
        # The sensor is gone and no more readings will arrive.
        ended @2 :Void;
        error @3 :T.Error;
    }
    # Opaque resume token. Pass it back to continue from the next
    # unread reading. See the note above: this replaces the offset, and
    # it is deliberately not a count.
    cursor @4 :SequenceToken;
}

struct SequenceToken {
    # Opaque: a backend encodes its own resumption point here.
    # Consumers never inspect it and never construct one — the token a
    # pull returned is the token the next pull takes.
    token @0 :Data;
}

interface BatchSubscription {
    pull   @0 (maxCount :UInt32, cursor :SequenceToken) -> (result :ReadingPullResult);
    cancel @1 () -> T.VoidResult;
}

interface SensorSubscription {
    pull   @0 (maxCount :UInt32, cursor :SequenceToken) -> (result :ReadingPullResult);
    cancel @1 () -> T.VoidResult;
}

# ═══════════════════════════════════════════════════════════════════════
# Audit-7: Extended sensor data types
#
# GNSS positioning, air quality, fall detection, spatial sensing,
# gesture recognition, sensor calibration, and multi-sensor fusion.
# These structs provide structured data for the new sensor types.
# ═══════════════════════════════════════════════════════════════════════

# ── GNSS Multi-Constellation Fix ──────────────────────────────

struct GnssFix {
    latitude @0 :Float64;
    longitude @1 :Float64;
    altitudeMeters @2 :Float32;
    accuracyMeters @3 :Float32;
    # Horizontal dilution of precision.
    hdop @4 :Float32;
    # Vertical dilution of precision.
    vdop @5 :Float32;
    satellitesUsed @6 :UInt32;
    # Constellation identifier (e.g., "GPS", "GLONASS", "Galileo", "BeiDou").
    constellation @7 :Text;
    timestamp @8 :T.Timestamp;
}

# ── Air Quality Index ─────────────────────────────────────────

struct AirQualityIndex {
    # US EPA AQI value (0-500).
    aqi @0 :UInt32;
    # Category label (e.g., "Good", "Moderate", "Unhealthy").
    category @1 :Text;
    # Particulate matter 2.5 micrometers in µg/m³.
    pm25 @2 :Float32;
    # Particulate matter 10 micrometers in µg/m³.
    pm10 @3 :Float32;
    # Carbon dioxide in ppm.
    co2 @4 :Float32;
    # Volatile organic compounds in ppb.
    voc @5 :Float32;
    # Nitrogen dioxide in ppb.
    no2 @6 :Float32;
    timestamp @7 :T.Timestamp;
}

# ── Fall Detection ────────────────────────────────────────────

struct FallDetection {
    detected @0 :Bool;
    confidence @1 :Float32;
    timestamp @2 :T.Timestamp;
    # Estimated impact force in g.
    impactForce @3 :Float32;
    # Description of motion before impact.
    preImpactMotion @4 :Text;
}

# ── Sensor Calibration ────────────────────────────────────────

struct SensorCalibration {
    sensorId @0 :T.SensorId;
    calibrated @1 :Bool;
    lastCalibration @2 :T.Timestamp;
    nextCalibration @3 :T.Timestamp;
    # Per-axis offset values.
    offset @4 :List(Float32);
    # Per-axis scale factors.
    scale @5 :List(Float32);
}

# ── Spatial Sensor (LiDAR/ToF) ────────────────────────────────

struct SpatialSensor {
    type @0 :SpatialSensorType;
    # Resolution in pixels or points.
    resolution @1 :UInt32;
    # Maximum range in meters.
    range @2 :Float32;
    # Field of view in degrees.
    fov @3 :Float32;
    frameRate @4 :UInt32;
}

enum SpatialSensorType {
    lidar @0;
    tof @1;
    structuredLight @2;
    radar @3;
    ultrasonic @4;
    custom @5;
}

# ── Gesture Sensor ────────────────────────────────────────────

struct GestureSensor {
    # Sensor technology (e.g., "radar", "capacitive", "infrared").
    type @0 :Text;
    # Supported gesture types.
    gestures @1 :List(Text);
    # Detection range in meters.
    range @2 :Float32;
    frameRate @3 :UInt32;
}

# ── Multi-Sensor Fusion ───────────────────────────────────────

struct SensorFusionConfig {
    # Sensors participating in fusion (by ID).
    sensors @0 :List(T.SensorId);
    # Fusion algorithm identifier (e.g., "kalman", "complementary", "madgwick").
    algorithm @1 :Text;
    # Output rate in Hz.
    outputRate @2 :UInt32;
    latencyHint @3 :T.Duration;
}

# ── Context Snapshot (audit-8 What's Still Missing) ──
struct ContextSnapshot {
    timestamp @0 :T.Timestamp;
    readings @1 :List(SensorReading);
    location @2 :Text;
    activity @3 :Text;
}

# ── Spectrometer Sensor Data (audit-8 What's Still Missing) ──
# T.DataHandle for the bins, not an inline list. A spectrometer produces
# hundreds to thousands of bins per reading — 2048 channels x 4 bytes =
# 8 KB — at up to 100 Hz, which is 800 KB/s copied inline into the
# message arena and then copied out again. Same reasoning as
# audio.capnp's submit path; a 12-byte accelerometer reading stays
# inline, which is why SensorReading.values is unchanged.
struct SpectrometerData {
    uvIndex @0 :Float32;
    colorTemperature @1 :UInt32;
    spectralData @2 :T.DataHandle;
    timestamp @3 :T.Timestamp;
}

# ── Gas Sensor Data (audit-8 What's Still Missing) ──
struct GasSensorData {
    methanePpm @0 :Float32;
    coPpm @1 :Float32;
    propanePpm @2 :Float32;
    timestamp @3 :T.Timestamp;
}

# ── Radiation Sensor Data (audit-8 What's Still Missing) ──
struct RadiationSensorData {
    dosage @0 :Float32;
    countRate @1 :Float32;
    timestamp @2 :T.Timestamp;
}

# ── Biometric Sensor Management (audit-9 What's Still Missing) ──
struct BiometricSensorInfo {
    sensorId @0 :T.SensorId;
    type @1 :BiometricSensorType;
    templateCount @2 :UInt32;
    maxTemplates @3 :UInt32;
    falseAcceptRate @4 :Float32;
    falseRejectRate @5 :Float32;
}

enum BiometricSensorType {
    fingerprint @0;
    face @1;
    iris @2;
    palm @3;
    voice @4;
    custom @5;
}

struct BiometricAuthResult {
    authenticated @0 :Bool;
    confidence @1 :Float32;
    sensorId @2 :T.SensorId;
    timestamp @3 :T.Timestamp;
}

# ── Sensor Event Subscription (audit-9 What's Still Missing) ──
interface SensorEventSubscription {
    pull @0 () -> (event :SensorEvent);
    cancel @1 () -> T.VoidResult;
}

# An event, as a union. The previous shape was a struct with
# `type :SensorEventType` and `data :T.Meta`, which had three defects:
#
#   1. T.Meta is ONE {key, value} pair, so a threshold event could carry
#      exactly one of "the threshold" or "the value that crossed it".
#      `data` is now a T.StringMap.
#   2. `error @4` carried no payload, so a sensor failure produced an
#      event that said "something failed" and nothing about what.
#   3. The enum was the only forward-compat route, so a backend adding a
#      new event kind had to overload `other` — and a consumer that did
#      not know the new meaning could not tell what it skipped.
#
# The ai.capnp:533-550 shape fixes all three: known events are arms, the
# error arm carries T.Error, and anything not yet invented rides in
# `unknown` and is ignored rather than rejected (ai.capnp:43-47).
struct SensorEvent {
    sensorId @0 :T.SensorId;
    timestamp @1 :T.Timestamp;
    union {
        reading @2 :SensorReadingPayload;
        threshold @3 :SensorThresholdPayload;
        accuracyChanged @4 :SensorAccuracy;
        enabledChanged @5 :Bool;
        error @6 :T.Error;
        unknown @7 :UnknownSensorEvent;
    }
}

struct UnknownSensorEvent {
    typeId @0 :UInt64;
    payload @1 :Data;
}

struct SensorReadingPayload {
    values @0 :List(Float32);
    units @1 :Text;
    axisLabels @2 :List(Text);
    accuracy @3 :SensorAccuracy;
    metadata @4 :T.StringMap;
}

struct SensorThresholdPayload {
    # Which threshold fired, as an open token — a client and backend
    # agree out of band on the spelling, which is what a threshold NAME
    # is; freezing the spelling into an enum would only cover today's.
    thresholdId @0 :Text;
    # The level that was crossed, in the sensor's own units.
    level @1 :Float32;
    # The reading that crossed it.
    value @2 :Float32;
    metadata @3 :T.StringMap;
}

# A filter over the event kinds. The event union above is open-ended, so
# a filter that named only closed kinds could never select an event the
# consumer does not know about — this is an open token list for the same
# reason SensorType is.
struct SensorEventFilter {
    sensorIds @0 :List(T.SensorId);
    types @1 :List(Text);
}

# ── Sensor Fusion Algorithm (audit-9 What's Still Missing) ──
struct SensorFusionAlgorithm {
    name @0 :Text;
    description @1 :Text;
    requiredSensors @2 :List(Text);
    outputType @3 :Text;
}
