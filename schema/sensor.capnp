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

# ── Sensor Types ─────────────────────────────────────────────────────────

enum SensorType {
    unknown @0;
    accelerometer @1;
    gyroscope @2;
    magnetometer @3;
    barometer @4;
    proximity @5;
    ambientLight @6;
    heartRate @7;
    stepCounter @8;
    stepDetector @9;
    gravity @10;
    linearAcceleration @11;
    rotationVector @12;
    gameRotationVector @13;
    geomaticRotation @14;
    significantMotion @15;
    pose6Dof @16;
    stationaryDetect @17;
    motionDetect @18;
    heartBeat @19;
    lowLatencyOffbodyDetect @20;
    accelerometerUncalibrated @21;
    gyroscopeUncalibrated @22;
    magnetometerUncalibrated @23;
    humidity @24;
    temperature @25;
    ambientTemperature @26;
    pressure @27;
    uv @28;
    # Audit-7: extended sensor types.
    gnss @29;           # Multi-constellation GNSS positioning
    airQuality @30;     # Air quality index (PM2.5, CO2, VOC)
    fallDetection @31;  # Wearable fall detection
    lidar @32;          # LiDAR 3D depth sensing
    tof @33;            # Time-of-flight depth sensing
    radar @34;          # Radar motion/gesture detection
    gesture @35;        # Touchless gesture recognition
    spectrometer @36;   # UV index, color temperature, spectral analysis
    gas @37;            # Gas detection (methane, CO, propane)
    radiation @38;      # Radiation detection (Geiger counter)
    soil @39;           # Soil moisture, pH, temperature
    waterQuality @40;   # Water turbidity, pH, chlorine
    acoustic @41;       # Sound level, frequency analysis
    strain @42;         # Load cells, strain gauges
    custom @43;
}

# ── Sensor Info ─────────────────────────────────────────────────────────

struct SensorInfo {
    id @0 :T.SensorId;
    name @1 :Text;
    vendor @2 :Text;
    type @3 :SensorType;
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
    # Which capability must be held to access this sensor.
    permissionCapability @16 :Text;
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

    # All sensors of a given type (for multi-sensor devices).
    getSensorsByType @7 (type :SensorType, pagination :T.Pagination)
                     -> (sensors :List(SensorHandle), total :UInt32);

    # Subscribe at a named rate.
    subscribe @2 (sensorId :T.SensorId, rate :SamplingRate)
              -> (subscription :SensorSubscription);

    # Subscribe at a custom rate in Hz.
    subscribeCustom @3 (sensorId :T.SensorId, rateHz :UInt32)
                    -> (subscription :SensorSubscription);

    # Subscribe multiple sensors at once (for time-synchronized reads).
    subscribeBatch @8 (requests :List(SubscribeRequest))
                   -> (subscription :BatchSubscription);

    # Pull latest readings (non-blocking).
    pull @4 (subscription :SensorSubscription) -> (readings :List(SensorReading));

    # Flush pending readings for a subscription (forces delivery).
    flush @9 (subscription :SensorSubscription) -> T.VoidResult;

    unsubscribe @5 (subscription :SensorSubscription) -> T.VoidResult;

    isAvailable @6 (type :SensorType, pagination :T.Pagination)
                -> (available :Bool, sensors :List(SensorHandle), total :UInt32);

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

interface BatchSubscription {
    pull   @0 (pagination :T.Pagination) -> (readings :List(SensorReading), total :UInt32);
    cancel @1 () -> T.VoidResult;
}

interface SensorSubscription {
    pull   @0 (pagination :T.Pagination) -> (readings :List(SensorReading), total :UInt32);
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
struct SpectrometerData {
    uvIndex @0 :Float32;
    colorTemperature @1 :UInt32;
    spectralData @2 :List(Float32);
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

struct SensorEvent {
    sensorId @0 :T.SensorId;
    type @1 :SensorEventType;
    data @2 :T.Meta;
    timestamp @3 :T.Timestamp;
}

enum SensorEventType {
    reading @0;
    threshold @1;
    accuracyChanged @2;
    enabledChanged @3;
    error @4;
    other @5;
    custom @6;
}

struct SensorEventFilter {
    sensorIds @0 :List(T.SensorId);
    types @1 :List(SensorEventType);
}

# ── Sensor Fusion Algorithm (audit-9 What's Still Missing) ──
struct SensorFusionAlgorithm {
    name @0 :Text;
    description @1 :Text;
    requiredSensors @2 :List(SensorType);
    outputType @3 :SensorType;
}
