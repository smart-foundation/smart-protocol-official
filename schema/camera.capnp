@0xa1b2c3d4e5f60026;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Camera - photo/video capture, preview, zoom, flash, focus, HDR,
#         depth sensing, face/scene detection, privacy, calibration.
#
# Improvements beyond the original schema:
#   - CameraId, RecordingId, CaptureId, EventId typed IDs.
#   - T.Pagination on listCameras.
#   - CameraEventSubscription with pullPaginated.
#   - Subscription cancel for clean teardown.
#   - T.Duration for recording duration.
#   - T.DataHandle for captured data.
#   - Custom variants on all enums.
#
# Audit-8 enhancements:
#   - CameraFeature: faceTracking, eyeTracking, depth, thermal,
#     sceneDetection, privacyMask, multiCamera.
#   - DepthFormat: depth16, depth32f, disparity16.
#   - PrivacyMask: blur/redact regions before capture.
#   - WatermarkRequest: programmatic watermarking.
#   - HdrOptions: bracket capture with merge strategy.
#   - CaptureFilter: chainable image filters.
#   - CaptureTrigger: motion/sound/schedule/geofence triggers.
#   - CameraCapabilities: structured format/FPS/resolution query.
#   - FaceDetection/SceneDetection: on-device AI features.
#   - CalibrationResult: lens distortion and white balance calibration.
# ═══════════════════════════════════════════════════════════════════════

interface CameraService {
    listCameras @0 (pagination :T.Pagination) -> (cameras :List(CameraInfo), totalCount :UInt32);
    getCamera @1 (cameraId :T.CameraId) -> (info :CameraInfo);

    capturePhoto @2 (cameraId :T.CameraId, options :PhotoOptions) -> (captureId :T.CaptureId, data :T.DataHandle, metadata :PhotoMetadata);
    startRecording @3 (cameraId :T.CameraId, options :VideoOptions) -> (recordingId :T.RecordingId);
    stopRecording @4 (recordingId :T.RecordingId) -> (data :T.DataHandle);
    pauseRecording @5 (recordingId :T.RecordingId) -> T.VoidResult;
    resumeRecording @6 (recordingId :T.RecordingId) -> T.VoidResult;

    startPreview @7 (cameraId :T.CameraId, surfaceId :T.SurfaceId) -> T.VoidResult;
    stopPreview @8 (cameraId :T.CameraId) -> T.VoidResult;

    setZoom @9 (cameraId :T.CameraId, zoom :Float32) -> T.VoidResult;
    setFlash @10 (cameraId :T.CameraId, mode :FlashMode) -> T.VoidResult;
    setFocus @11 (cameraId :T.CameraId, mode :FocusMode, x :Float32, y :Float32) -> T.VoidResult;
    setExposure @12 (cameraId :T.CameraId, exposure :Float32) -> T.VoidResult;
    setExposureCompensation @13 (cameraId :T.CameraId, bias :Float32) -> T.VoidResult;

    subscribeEvents @14 () -> (subscription :CameraEventSubscription);

    # -- Audit-8: Camera capability query --
    getCameraCapabilities @15 (cameraId :T.CameraId) -> (capabilities :CameraCapabilities);

    # -- Audit-8: AI features --
    detectFaces @16 (cameraId :T.CameraId) -> (faces :List(FaceDetection));
    detectScene @17 (cameraId :T.CameraId) -> (scene :SceneDetection);

    # -- Audit-8: Calibration --
    calibrateCamera @18 (cameraId :T.CameraId) -> (result :CalibrationResult);
    getCalibrationStatus @19 (cameraId :T.CameraId) -> (status :CalibrationStatus);

    # -- Audit-9: Video stabilization options --
    setStabilization @20 (cameraId :T.CameraId, options :StabilizationOptions) -> T.VoidResult;
    getStabilization @21 (cameraId :T.CameraId) -> (options :StabilizationOptions);

    # -- Audit-9: Night mode options --
    setNightMode @22 (cameraId :T.CameraId, options :NightModeOptions) -> T.VoidResult;
    getNightMode @23 (cameraId :T.CameraId) -> (options :NightModeOptions);

    # -- Audit-9: Camera stream routing --
    routeStream @24 (cameraId :T.CameraId, route :CameraStreamRoute) -> T.VoidResult;
    listStreamRoutes @25 (cameraId :T.CameraId) -> (routes :List(CameraStreamRoute));

    # -- Audit-9: Camera power management --
    setPowerMode @26 (cameraId :T.CameraId, mode :CameraPowerMode) -> T.VoidResult;
    getPowerMode @27 (cameraId :T.CameraId) -> (mode :CameraPowerMode);

    # -- Audit-9: Rich photo metadata --
    getRichMetadata @28 (captureId :T.CaptureId) -> (metadata :RichPhotoMetadata);

    # -- Audit-9: Camera firmware/hardware info --
    getHardwareInfo @29 (cameraId :T.CameraId) -> (info :CameraHardwareInfo);

    # -- Audit-9: Multi-camera synchronization --
    synchronizeCameras @30 (sync :MultiCameraSync) -> T.VoidResult;

    # -- Audit-9: ProRAW/ProRes options --
    setRawCaptureOptions @31 (cameraId :T.CameraId, options :RawCaptureOptions) -> T.VoidResult;
    getRawCaptureOptions @32 (cameraId :T.CameraId) -> (options :RawCaptureOptions);
}

interface CameraEventSubscription {
    # Deprecated: use pullPaginated for bounded results.
    pull @0 () -> (events :List(CameraEvent));
    cancel @1 () -> T.VoidResult;
    # Paginated pull — returns at most `limit` events starting from `offset`.
    pullPaginated @2 (pagination :T.Pagination) -> (result :CameraEventPullResult);
}

struct CameraEventPullResult {
    events    @0 :List(CameraEvent);
    totalCount @1 :UInt32;
}

struct CameraInfo {
    id @0 :T.CameraId;
    name @1 :Text;              # Human-readable device name
    facing @2 :CameraFacing;
    formats @3 :List(CameraFormat);
    features @4 :List(CameraFeature);
    minZoom @5 :Float32;
    maxZoom @6 :Float32;
    supportsPhoto @7 :Bool;
    supportsVideo @8 :Bool;
    # Audit-8 additions:
    depthSensing @9 :Bool;
    thermalCamera @10 :Bool;
    multiCamera @11 :Bool;
    group @12 :Text;
}

enum CameraFacing {
    front @0;
    back @1;
    external @2;
    custom @3;
}

struct CameraFormat {
    width @0 :UInt32;
    height @1 :UInt32;
    pixelFormat @2 :T.PixelFormat;
    minFps @3 :UInt32;
    maxFps @4 :UInt32;
    # Audit-8 additions:
    hdr @5 :Bool;
    depthFormat @6 :DepthFormat;
}

enum CameraFeature {
    autoFocus @0;
    autoExposure @1;
    autoWhiteBalance @2;
    flash @3;
    torch @4;
    videoStabilization @5;
    hdr @6;
    portrait @7;
    night @8;
    beauty @9;
    raw @10;
    custom @11;
    # Audit-8 additions:
    faceTracking @12;
    eyeTracking @13;
    depth @14;
    thermal @15;
    sceneDetection @16;
    privacyMask @17;
    multiCamera @18;
}

struct PhotoOptions {
    format @0 :PhotoFormat;
    width @1 :UInt32;
    height @2 :UInt32;
    quality @3 :UInt8;          # 0-100, backend maps to internal quality scale
    flash @4 :FlashMode;
    timestamp @5 :T.Timestamp;
    # Audit-8 additions:
    privacyMask @6 :PrivacyMask;
    watermark @7 :WatermarkRequest;
    hdr @8 :HdrOptions;
    filters @9 :List(CaptureFilter);
}

enum PhotoFormat {
    jpeg @0;
    png @1;
    heif @2;
    raw @3;
    webp @4;
    custom @5;
}

enum FlashMode {
    off @0;
    on @1;
    auto @2;
    torch @3;
    custom @4;
}

enum FocusMode {
    locked @0;
    auto @1;
    continuous @2;
    edof @3;
    custom @4;
}

struct PhotoMetadata {
    width @0 :UInt32;
    height @1 :UInt32;
    timestamp @2 :T.Timestamp;
    camera @3 :T.CameraId;
    orientation @4 :T.SurfaceTransform;
}

struct VideoOptions {
    format @0 :VideoFormat;
    width @1 :UInt32;
    height @2 :UInt32;
    frameRate @3 :T.FrameRate;
    bitrate @4 :UInt32;         # Bits per second
    audio @5 :Bool;
    # Audit-8 additions:
    privacyMask @6 :PrivacyMask;
    hdr @7 :HdrOptions;
    maxDuration @8 :T.Duration;
}

enum VideoFormat {
    h264 @0;
    h265 @1;
    vp8 @2;
    vp9 @3;
    av1 @4;
    mjpeg @5;
    custom @6;
}

struct CameraEvent {
    id @0 :T.EventId;
    timestamp @1 :T.Timestamp;
    cameraId @2 :T.CameraId;
    type @3 :CameraEventType;
}

enum CameraEventType {
    connect @0;
    disconnect @1;
    error @2;
    recordingStarted @3;
    recordingStopped @4;
    custom @5;
}

# ════════════════════════════════════════════════════════════════════════
# Audit-8 additions: depth sensing, face/eye tracking, AI scene
# detection, privacy masks, watermarks, HDR options, capture filters,
# camera calibration, camera capabilities query.
# ════════════════════════════════════════════════════════════════════════

# ── Depth Format ───────────────────────────────────────────────────────
enum DepthFormat {
    none @0;
    depth16 @1;
    depth32f @2;
    disparity16 @3;
    custom @4;
}

# ── Privacy Mask ───────────────────────────────────────────────────────
# Regions to blur or redact before capture. Essential for privacy
# compliance in shared/public camera environments.
struct PrivacyMask {
    regions @0 :List(PrivacyRegion);
    mode @1 :PrivacyMaskMode;
}

struct PrivacyRegion {
    x @0 :UInt32;
    y @1 :UInt32;
    width @2 :UInt32;
    height @3 :UInt32;
}

enum PrivacyMaskMode {
    blur @0;
    redact @1;
    pixelate @2;
    custom @3;
}

# ── Watermark Request ──────────────────────────────────────────────────
# Programmatic watermarking during capture. Text or image watermarks
# with position and opacity control.
struct WatermarkRequest {
    text @0 :Text;
    imageUri @1 :Text;
    position @2 :WatermarkPosition;
    opacity @3 :Float32;
}

enum WatermarkPosition {
    topLeft @0;
    topRight @1;
    bottomLeft @2;
    bottomRight @3;
    center @4;
    custom @5;
}

# ── HDR Options ────────────────────────────────────────────────────────
# Structured HDR capture options. Bracket count, EV spacing, and
# merge strategy for high dynamic range photography.
struct HdrOptions {
    bracketCount @0 :UInt8;
    evSpacing @1 :Float32;
    mergeStrategy @2 :HdrMergeStrategy;
}

enum HdrMergeStrategy {
    exposureFusion @0;
    toneMapping @1;
    custom @2;
}

# ── Capture Filter ─────────────────────────────────────────────────────
# Chainable image filters applied during capture. Brightness, contrast,
# saturation, and custom LUT filters for computational photography.
struct CaptureFilter {
    type @0 :CaptureFilterType;
    strength @1 :Float32;
    parameters @2 :T.StringMap;
}

enum CaptureFilterType {
    brightness @0;
    contrast @1;
    saturation @2;
    sharpness @3;
    denoise @4;
    lut @5;
    custom @6;
}

# ── Capture Trigger ────────────────────────────────────────────────────
# Programmatic capture triggers for automated photography. Motion,
# sound, schedule, and geofence triggers for security and monitoring.
enum CaptureTrigger {
    manual @0;
    motion @1;
    sound @2;
    schedule @3;
    geofence @4;
    custom @5;
}

# ── Camera Capabilities ────────────────────────────────────────────────
# Structured query result for supported format/FPS/resolution combos.
# Answers "what can this camera do?" without iterating all formats.
struct CameraCapabilities {
    cameraId @0 :T.CameraId;
    supportedFormats @1 :List(CameraFormat);
    supportedPhotoFormats @2 :List(PhotoFormat);
    supportedVideoFormats @3 :List(VideoFormat);
    maxResolution @4 :UInt32;
    minFps @5 :UInt32;
    maxFps @6 :UInt32;
    supportsHdr @7 :Bool;
    supportsDepth @8 :Bool;
    supportsFaceTracking @9 :Bool;
    supportsSceneDetection @10 :Bool;
}

# ── Face Detection ─────────────────────────────────────────────────────
# On-device face detection result. Bounding box, landmarks, and
# confidence for each detected face.
struct FaceDetection {
    faceId @0 :UInt32;
    x @1 :UInt32;
    y @2 :UInt32;
    width @3 :UInt32;
    height @4 :UInt32;
    confidence @5 :Float32;
    landmarks @6 :List(FaceLandmark);
}

struct FaceLandmark {
    x @0 :UInt32;
    y @1 :UInt32;
    type @2 :Text;
}

# ── Scene Detection ────────────────────────────────────────────────────
# On-device scene classification. Identifies scene type, objects,
# and recommendations for optimal capture settings.
struct SceneDetection {
    scene @0 :Text;
    confidence @1 :Float32;
    objects @2 :List(SceneObject);
    recommendations @3 :List(Text);
}

struct SceneObject {
    label @0 :Text;
    confidence @1 :Float32;
    x @2 :UInt32;
    y @3 :UInt32;
    width @4 :UInt32;
    height @5 :UInt32;
}

# ── Camera Calibration ─────────────────────────────────────────────────
# Lens distortion correction, white balance calibration, and autofocus
# calibration for precision imaging.
struct CalibrationResult {
    lensDistortion @0 :Float32;
    whiteBalanceBias @1 :Float32;
    focusOffset @2 :Float32;
    calibratedAt @3 :T.Timestamp;
}

enum CalibrationStatus {
    uncalibrated @0;
    inProgress @1;
    calibrated @2;
    expired @3;
    custom @4;
}

# ════════════════════════════════════════════════════════════════════════
# Audit-9 additions: video stabilization, night mode, camera stream
# routing, power management, metadata enrichment, firmware/hardware info,
# multi-camera synchronization, and ProRAW/ProRes options.
# ════════════════════════════════════════════════════════════════════════

# ── Video Stabilization Options ─────────────────────────────────────────
# Structured video stabilization configuration. Controls stabilization
# mode, strength, and crop factor for video recording.
struct StabilizationOptions {
    mode @0 :StabilizationMode;
    # Stabilization strength (0.0 = off, 1.0 = maximum).
    strength @1 :Float32;
    # Crop factor applied during stabilization (1.0 = no crop).
    cropFactor @2 :Float32;
}

enum StabilizationMode {
    off @0;
    digital @1;
    optical @2;
    hybrid @3;
    predict @4;
    custom @5;
}

# ── Night Mode Options ─────────────────────────────────────────────────
# Structured night mode configuration. Controls exposure time, frame
# count, and noise reduction for low-light photography.
struct NightModeOptions {
    # Target exposure time in milliseconds.
    exposureTimeMs @0 :UInt32;
    # Number of frames to capture and merge.
    frameCount @1 :UInt8;
    # Noise reduction level (0.0 = off, 1.0 = maximum).
    noiseReduction @2 :Float32;
    # Whether to use motion detection to reduce blur.
    motionCompensation @3 :Bool;
}

# ── Camera Stream Route ────────────────────────────────────────────────
# Describes a route for delivering a camera stream to a consumer.
# Enables routing a single camera stream to multiple consumers.
struct CameraStreamRoute {
    streamId @0 :T.CaptureId;
    consumerId @1 :T.AppId;
    format @2 :CameraFormat;
    # Whether this consumer receives the full-resolution stream.
    fullResolution @3 :Bool;
}

# ── Camera Power Mode ──────────────────────────────────────────────────
# Camera power management modes. Controls the trade-off between
# preview quality and power consumption.
enum CameraPowerMode {
    fullQuality @0;
    lowPowerPreview @1;
    ultraLowPower @2;
    custom @3;
}

# ── Rich Photo Metadata ────────────────────────────────────────────────
# Extended photo metadata including GPS, scene description, AI tags,
# and device info. Supplements the minimal PhotoMetadata struct.
struct RichPhotoMetadata {
    # Basic metadata reference.
    basic @0 :PhotoMetadata;
    # GPS location at capture time.
    latitude @1 :Float64;
    longitude @2 :Float64;
    altitude @3 :Float32;
    # AI-generated scene description.
    sceneDescription @4 :Text;
    # AI-generated tags for the captured content.
    aiTags @5 :List(Text);
    # Camera sensor info at capture time.
    sensorInfo @6 :CameraHardwareInfo;
    # Whether HDR was used for this capture.
    hdrUsed @7 :Bool;
    # Exposure value at capture time.
    exposureValue @8 :Float32;
}

# ── Camera Hardware Info ────────────────────────────────────────────────
# Query camera sensor model, lens info, and firmware version.
# Essential for device-specific debugging and calibration.
struct CameraHardwareInfo {
    cameraId @0 :T.CameraId;
    sensorModel @1 :Text;
    sensorResolution @2 :UInt32;
    lensModel @3 :Text;
    lensAperture @4 :Float32;
    firmwareVersion @5 :Text;
    hardwareRevision @6 :Text;
    manufacturer @7 :Text;
}

# ── Multi-Camera Synchronization ───────────────────────────────────────
# Synchronization protocol for stereo and multi-camera capture.
# Ensures synchronized start/stop and frame alignment across cameras.
struct MultiCameraSync {
    # Camera IDs to synchronize.
    cameraIds @0 :List(T.CameraId);
    # Maximum allowed frame offset between cameras in microseconds.
    maxFrameOffsetUs @1 :UInt32;
    # Whether to use hardware sync signal.
    hardwareSync @2 :Bool;
    # Sync group name for identification.
    syncGroup @3 :Text;
}

# ── Raw Capture Options ────────────────────────────────────────────────
# ProRAW/ProRes capture options. Controls bit depth, color space,
# and compression for RAW photography and video.
struct RawCaptureOptions {
    bitDepth @0 :UInt8;
    colorSpace @1 :RawColorSpace;
    compression @2 :RawCompression;
    # Whether to include embedded preview JPEG.
    includePreview @3 :Bool;
    # Whether to apply lens correction to RAW data.
    lensCorrection @4 :Bool;
}

enum RawColorSpace {
    proPhoto @0;
    adobeRgb @1;
    dng @2;
    appleProRaw @3;
    custom @4;
}

enum RawCompression {
    none @0;
    lossless @1;
    lossy @2;
    custom @3;
}
