@0xa1b2c3d4e5f60007;

# ═══════════════════════════════════════════════════════════════════════
# Display — video outputs, modes, HDR, DPMS, night-light, color profiles,
#           brightness, mirroring, adaptive sync, HDCP content protection.
#
# Zero-backend-assumption IPC contract. No Wayland, X11, DRM/KMS, or
# platform-specific display server assumed. The backend decides the
# display pipeline; the protocol defines the contract.
#
# Improvements (audit):
#   - All subscription interfaces have cancel() for explicit teardown.
#   - LogicalMonitor.id typed as T.LogicalMonitorId.
#   - ColorProfile.id typed as T.ColorProfileId.
#   - DisplayMode.id typed as T.DisplayModeId.
#   - ContentProtectionResult.error → T.Error.
#   - Night light temperature documented as Kelvin in field name.
#   - AdaptiveSyncCaps.variant has custom variant for forward compatibility.
#   - DisplayConnection has other variant for forward compatibility.
#   - HdrStandard has other variant for forward compatibility.
#   - PqMode has other variant for forward compatibility.
#   - DpmsState has other variant for forward compatibility.
#   - ColorSpace has other variant for forward compatibility.
#   - MonitorEvent union has custom variant for forward compatibility.
#   - Vec2f references corrected to T.Vec2 (canonical type in types.capnp).
#   - List returns use T.Pagination via MonitorFilter.
#
# Audit-7 improvements:
#   - Monitor.dpi :DisplayDpi for explicit DPI with diagonal measurement.
#   - Monitor.devicePixelRatio :Float32 for content scaling.
#   - FoldState enum for foldable device state detection.
#   - Monitor.foldState :FoldState for foldable displays.
#   - FoldPosition struct for detailed fold geometry.
#   - Monitor.foldPosition :FoldPosition for fold position details.
#   - AdaptiveRefreshPolicy enum for refresh rate adaptation.
#   - Display.setAdaptiveRefreshPolicy / getAdaptiveRefreshPolicy.
#   - IccProfile struct for ICC profile management.
#   - Display.loadIccProfile / getIccProfileData.
#   - ColorManagementConfig struct for color management pipeline.
#   - Display.setColorManagement / getColorManagement.
#   - StylusDisplayEvent struct for display-level stylus input.
#   - Display.subscribeStylusInput + StylusInputSubscription.
#   - ArDisplayConfig struct for AR/VR display configuration.
#   - Display.setArConfig / getArConfig.
#   - CircularDisplayConfig struct for circular display geometry.
#   - Monitor.circularConfig for watch/circular displays.
#   - SignageConfig struct for digital signage settings.
#   - Display.setSignageConfig.
#   - KioskConfig struct for kiosk mode settings.
#   - Display.setKioskConfig / getKioskConfig.
#   - DisplayTilingConfig struct for multi-display tiling.
#   - Display.createTiledDisplay.
#   - DisplayPowerBudget struct for per-display power management.
#   - Display.setPowerBudget / getPowerBudget.
#   - DisplayAccessibilityConfig struct for accessibility settings.
#   - Display.setAccessibilityConfig / getAccessibilityConfig.
#   - DisplayCapabilities struct for comprehensive capability report.
#   - Display.getDisplayCapabilities.
#   - NightLightSchedule struct for night light scheduling.
#   - Display.setNightLightSchedule / getColorTemperatureRange.
#   - HdrCapabilities struct for detailed HDR capabilities.
#   - Display.getHdrCapabilities.
#   - Display.getEdidData / setCustomMode.
#   - DisplayFilter struct for optional monitor filtering.
#   - ContentProtectionLevel enum for fine-grained HDCP levels.
#   - Display.negotiateContentProtection for content protection negotiation.
#   - DisplayCalibration: startCalibration, getCalibrationStatus.
#   - DisplayRecommendation: getDisplayRecommendation for content-aware settings.
#   - NightLightGeoConfig: setNightLightGeofencing for GPS-based night light.
#   - DisplayThermal: getThermalStatus for thermal-aware display management.
#   - DisplayFilter: listMonitorsFiltered for optional monitor filtering.
#   - Display.setRefreshRateFloat (compliant alternative to UInt32/Float32 inconsistency).
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

interface Display {
    # ── Core discovery ──
    getMonitors @0 () -> (monitors :List(Monitor));
    subscribeMonitors @1 () -> (subscription :MonitorSubscription);
    pullMonitors @2 (subscription :MonitorSubscription) -> (events :List(MonitorEvent));

    # ── Per-monitor controls ──
    hasBacklight @3 (outputId :T.OutputId) -> (has :Bool);

    getBrightness @4 (outputId :T.OutputId) -> (brightness :Float32);
    setBrightness @5 (outputId :T.OutputId, brightness :Float32) -> T.VoidResult;
    subscribeBrightness @6 (outputId :T.OutputId) -> (subscription :BrightnessSubscription);
    pullBrightness @7 (subscription :BrightnessSubscription) -> (brightness :Float32);

    # ── Night light ──
    setNightLight @8 (outputId :T.OutputId, enabled :Bool) -> T.VoidResult;
    # Temperature in Kelvin (2700 warm – 6500 cool typical).
    setNightLightTemp @9 (outputId :T.OutputId, temperatureKelvin :Float32) -> T.VoidResult;
    getNightLight @10 (outputId :T.OutputId) -> (enabled :Bool, temperatureKelvin :Float32);

    # ── Mode / geometry / mirroring ──
    setMode @11 (outputId :T.OutputId, mode :T.DisplayModeId) -> T.VoidResult;
    setPosition @12 (outputId :T.OutputId, position :T.Vec2i) -> T.VoidResult;
    setScale @13 (outputId :T.OutputId, scale :Float32) -> T.VoidResult;
    setRotation @14 (outputId :T.OutputId, rotation :T.SurfaceTransform) -> T.VoidResult;
    setPrimary @15 (outputId :T.OutputId, primary :Bool) -> T.VoidResult;
    setEnabled @16 (outputId :T.OutputId, enabled :Bool) -> T.VoidResult;
    setDpms @17 (outputId :T.OutputId, state :DpmsState) -> T.VoidResult;

    setMirroring @18 (outputId :T.OutputId, sources :List(T.OutputId)) -> T.VoidResult;
    clearMirroring @19 (outputId :T.OutputId) -> T.VoidResult;

    # ── Apply / test (typed results) ──
    testChanges @20 (outputId :T.OutputId) -> (result :ApplyResult);
    applyChanges @21 (outputId :T.OutputId) -> (result :ApplyResult);

    # ── Refresh rate ──
    getCurrentRefreshRate @22 (outputId :T.OutputId) -> (rate :Float32);
    setRefreshRate @23 (outputId :T.OutputId, rate :UInt32) -> T.VoidResult;
    subscribeRefreshRate @24 (outputId :T.OutputId) -> (subscription :RefreshSubscription);
    pullRefreshRate @25 (subscription :RefreshSubscription) -> (rate :Float32);

    # ── Color profile ──
    setColorProfile @26 (outputId :T.OutputId, profileId :T.ColorProfileId) -> T.VoidResult;
    getColorProfile @27 (outputId :T.OutputId) -> (profile :ColorProfile);
    listColorProfiles @28 (outputId :T.OutputId, page :T.Pagination) -> (profiles :List(ColorProfile), total :UInt32);

    # ── HDR ──
    setHdrMode @29 (outputId :T.OutputId, mode :HdrMode) -> T.VoidResult;
    getHdrMode @30 (outputId :T.OutputId) -> (mode :HdrMode);
    subscribeHdr @31 (outputId :T.OutputId) -> (subscription :HdrSubscription);
    pullHdr @32 (subscription :HdrSubscription) -> (mode :HdrMode);

    # ── HDCP / content protection ──
    setContentProtection @33 (outputId :T.OutputId, enabled :Bool) -> (result :ContentProtectionResult);
    getContentProtection @34 (outputId :T.OutputId) -> (state :ContentProtectionState);

    # ── Logical monitors ──
    listLogicalMonitors @35 (page :T.Pagination) -> (monitors :List(LogicalMonitor), total :UInt32);
    createLogicalMonitor @36 (config :LogicalMonitorConfig) -> (id :T.LogicalMonitorId);
    destroyLogicalMonitor @37 (id :T.LogicalMonitorId) -> T.VoidResult;
    applyLogicalConfig @38 (id :T.LogicalMonitorId) -> (result :ApplyResult);

    # ── Adaptive refresh rate ──
    setAdaptiveRefreshPolicy @39 (outputId :T.OutputId, policy :AdaptiveRefreshPolicy) -> T.VoidResult;
    getAdaptiveRefreshPolicy @40 (outputId :T.OutputId) -> (policy :AdaptiveRefreshPolicy);

    # ── ICC profile management ──
    loadIccProfile @41 (outputId :T.OutputId, profile :IccProfile) -> T.VoidResult;
    getIccProfileData @42 (outputId :T.OutputId, profileId :T.ColorProfileId) -> (data :T.DataHandle);

    # ── Color management pipeline ──
    setColorManagement @43 (outputId :T.OutputId, config :ColorManagementConfig) -> T.VoidResult;
    getColorManagement @44 (outputId :T.OutputId) -> (config :ColorManagementConfig);

    # ── Stylus input on display ──
    subscribeStylusInput @45 (outputId :T.OutputId) -> (subscription :StylusInputSubscription);

    # ── AR/VR display configuration ──
    setArConfig @46 (outputId :T.OutputId, config :ArDisplayConfig) -> T.VoidResult;
    getArConfig @47 (outputId :T.OutputId) -> (config :ArDisplayConfig);

    # ── Digital signage ──
    setSignageConfig @48 (outputId :T.OutputId, config :SignageConfig) -> T.VoidResult;

    # ── Kiosk mode ──
    setKioskConfig @49 (outputId :T.OutputId, config :KioskConfig) -> T.VoidResult;
    getKioskConfig @50 (outputId :T.OutputId) -> (config :KioskConfig);

    # ── Multi-display tiling ──
    createTiledDisplay @51 (config :DisplayTilingConfig) -> T.VoidResult;

    # ── Per-display power budget ──
    setPowerBudget @52 (outputId :T.OutputId, budget :DisplayPowerBudget) -> T.VoidResult;
    getPowerBudget @53 (outputId :T.OutputId) -> (budget :DisplayPowerBudget);
    subscribePowerBudget @54 (outputId :T.OutputId) -> (subscription :PowerBudgetSubscription);

    # ── Display accessibility ──
    setAccessibilityConfig @55 (outputId :T.OutputId, config :DisplayAccessibilityConfig) -> T.VoidResult;
    getAccessibilityConfig @56 (outputId :T.OutputId) -> (config :DisplayAccessibilityConfig);

    # ── Capability query ──
    getDisplayCapabilities @57 (outputId :T.OutputId) -> (caps :DisplayCapabilities);

    # ── Per-output queries ──
    getDpiForOutput @58 (outputId :T.OutputId) -> (dpi :DisplayDpi);
    getContentScale @59 (outputId :T.OutputId) -> (scale :Float32);

    # ── Night light scheduling ──
    setNightLightSchedule @60 (outputId :T.OutputId, schedule :NightLightSchedule) -> T.VoidResult;
    getColorTemperatureRange @61 (outputId :T.OutputId) -> (minKelvin :Float32, maxKelvin :Float32);

    # ── HDR capabilities ──
    getHdrCapabilities @62 (outputId :T.OutputId) -> (caps :HdrCapabilities);

    # ── EDID and custom modes ──
    getEdidData @63 (outputId :T.OutputId) -> (data :T.DataHandle);
    setCustomMode @64 (outputId :T.OutputId, mode :DisplayMode) -> T.VoidResult;

    # ── Content protection negotiation ──
    negotiateContentProtection @65 (outputId :T.OutputId, requiredLevel :ContentProtectionLevel) -> (result :ContentProtectionResult);

    # ── Display calibration (audit-7 false positive: belongs here, not in display_calibration.capnp) ──
    startCalibration @66 (outputId :T.OutputId, profile :IccProfile) -> T.VoidResult;
    getCalibrationStatus @67 (outputId :T.OutputId) -> (status :CalibrationStatus);

    # ── Display recommendations (audit-7) ──
    getDisplayRecommendation @68 (outputId :T.OutputId, contentType :Text) -> (recommendation :DisplayRecommendation);

    # ── Night light geofencing (audit-7) ──
    setNightLightGeofencing @69 (outputId :T.OutputId, config :NightLightGeoConfig) -> T.VoidResult;

    # ── Display thermal (audit-7) ──
    getThermalStatus @70 (outputId :T.OutputId) -> (thermal :DisplayThermal);

    # ── Monitor filtering (audit-6) ──
    listMonitorsFiltered @71 (filter :DisplayFilter, page :T.Pagination) -> (monitors :List(Monitor), total :UInt32);

    # ── Refresh rate float (audit-6: compliant alternative to UInt32/Float32 inconsistency) ──
    setRefreshRateFloat @72 (outputId :T.OutputId, rateHz :Float32) -> T.VoidResult;

    # ── Audit-9 additions ──

    # Wireless display pairing (Miracast, AirPlay, Chromecast).
    discoverWirelessDisplays @73 () -> (displays :List(WirelessDisplay));
    pairWirelessDisplay @74 (display :WirelessDisplay) -> T.VoidResult;
    disconnectWirelessDisplay @75 (outputId :T.OutputId) -> T.VoidResult;

    # Content streaming configuration.
    setContentStreaming @76 (config :ContentStreamingConfig) -> T.VoidResult;
    getContentStreaming @77 (outputId :T.OutputId) -> (config :ContentStreamingConfig);

    # Multi-user display sessions.
    createUserSession @78 (session :DisplayUserSession) -> T.VoidResult;
    destroyUserSession @79 (outputId :T.OutputId, userId :T.UserId) -> T.VoidResult;
    listUserSessions @80 (outputId :T.OutputId) -> (sessions :List(DisplayUserSession));

    # Gesture zones.
    setGestureZone @81 (zone :GestureZone) -> T.VoidResult;
    getGestureZones @82 (outputId :T.OutputId) -> (zones :List(GestureZone));
    removeGestureZone @83 (outputId :T.OutputId, name :Text) -> T.VoidResult;

    # Color accuracy testing.
    runColorAccuracyTest @84 (outputId :T.OutputId) -> (result :ColorAccuracyTest);

    # Console text forwarding.
    writeConsoleText @85 (text :Text) -> ();
}

interface BrightnessSubscription {
    pull @0 () -> (brightness :Float32);
    cancel @1 () -> T.VoidResult;
}

interface MonitorSubscription {
    pull @0 () -> (events :List(MonitorEvent));
    cancel @1 () -> T.VoidResult;
}

interface RefreshSubscription {
    pull @0 () -> (rate :Float32);
    cancel @1 () -> T.VoidResult;
}

interface HdrSubscription {
    pull @0 () -> (mode :HdrMode);
    cancel @1 () -> T.VoidResult;
}

struct Monitor {
    id @0 :T.OutputId;
    name @1 :Text;
    manufacturer @2 :Text;
    model @3 :Text;
    # Physical size in millimetres — enables real DPI calculation.
    physicalSizeMm @4 :T.Vec2;
    # Position in the global display layout.
    position @5 :T.Vec2i;
    # Primary display flag.
    primary @6 :Bool;
    # Connection type.
    connection @7 :DisplayConnection;
    # Whether currently enabled.
    enabled @8 :Bool;
    # Current orientation.
    orientation @9 :T.SurfaceTransform;
    # ID of the active color profile.
    colorProfileId @10 :T.ColorProfileId;
    # List of available modes.
    modes @11 :List(DisplayMode);
    # Current active mode.
    currentMode @12 :DisplayMode;
    # Current refresh rate in Hz (float for VRR).
    refreshRate @13 :Float32;
    # HDR enabled on this output.
    hdr @14 :Bool;
    # Adaptive sync (FreeSync/G-Sync) supported.
    adaptiveSync @15 :AdaptiveSyncCaps;
    # Backlight present (for brightness control).
    backlight @16 :Bool;
    # Current brightness 0..1.
    brightness @17 :Float32;
    # Night light state.
    nightLight @18 :Bool;
    # Night light temperature in Kelvin (2700-6500 typical).
    nightLightTempKelvin @19 :Float32;
    # HDCP content protection state.
    hdcp @20 :HdcpState;

    # Audit-7: Explicit DPI with diagonal measurement.
    dpi @21 :DisplayDpi;
    # Audit-7: Device pixel ratio for content scaling (1.0 = standard, 2.0 = Retina).
    devicePixelRatio @22 :Float32;
    # Audit-7: Foldable device state.
    foldState @23 :FoldState;
    # Audit-7: Detailed fold geometry (hinge angle, crease position).
    foldPosition @24 :FoldPosition;
    # Audit-7: Circular display configuration (watch faces, instrument clusters).
    circularConfig @25 :CircularDisplayConfig;
    # Audit-7: Color depth in bits per pixel.
    colorDepthBits @26 :UInt32;
}

enum DisplayConnection {
    unknown @0;
    builtIn @1;
    hdmi @2;
    displayPort @3;
    usbC @4;
    edp @5;
    virtual @6;
    composite @7;
    svideo @8;
    other @9;
    # Backend-specific connection type.
    custom @10;
}

struct DisplayMode {
    id @0 :T.DisplayModeId;
    width @1 :UInt32;
    height @2 :UInt32;
    # Refresh rate in Hz × 100 (6000 = 60.00 Hz, 6001 = 60.01 Hz).
    refreshRatex100 @3 :UInt32;
    # Pixel aspect ratio (e.g., 1 = square, 100 = 100:99 for anamorphic).
    pixelAspect @4 :UInt32 = 1;
    # Whether this mode is preferred (EDID).
    preferred @5 :Bool;
    # Whether the mode is interlaced.
    interlace @6 :Bool;
    # Physical size in mm (from EDID).
    physicalSizeMm @7 :T.Vec2;
}

struct AdaptiveSyncCaps {
    supported @0 :Bool;
    # Adaptive sync variant identifier (backend-decided encoding).
    variant @1 :UInt8;
    minRefreshRate @2 :UInt32;
    maxRefreshRate @3 :UInt32;
}

enum DpmsState {
    on @0;
    standby @1;
    suspend @2;
    off @3;
    other @4;
    # Backend-specific DPMS state.
    custom @5;
}

struct ColorProfile {
    id @0 :T.ColorProfileId;
    name @1 :Text;
    # Named color space.
    colorSpace @2 :ColorSpace;
    # White point (x, y) in CIE 1931.
    whitePoint @3 :T.Vec2;
    # Luminance range in nits.
    minLuminance @4 :Float32;
    maxLuminance @5 :Float32;
    # Is this HDR-capable (maxLuminance > 250 nits).
    isHdr @6 :Bool;
}

enum ColorSpace {
    srgb @0;
    displayP3 @1;
    bt2020 @2;
    dciP3 @3;
    adobeRgb @4;
    rec601 @5;
    rec709 @6;
    linearSrgb @7;
    linearDisplayP3 @8;
    other @9;
    # Backend-specific color space.
    custom @10;
}

struct HdrMode {
    enabled @0 :Bool;
    # HDR standard in use.
    standard @1 :HdrStandard;
    # Content Max CLL in nits.
    maxCll @2 :UInt32;
    # Frame Average Light Level in nits.
    fall @3 :UInt32;
    # Dolby Vision PQ mode (L1/L5).
    pqMode @4 :PqMode;
}

enum HdrStandard {
    none @0;
    hdr10 @1;
    hlg @2;
    dolbyVision @3;
    hdr10Plus @4;
    other @5;
    # Backend-specific HDR standard.
    custom @6;
}

enum PqMode {
    l1 @0;
    l5 @1;
    other @2;
    # Backend-specific PQ mode.
    custom @3;
}

struct HdcpState {
    # HDCP is currently active.
    active @0 :Bool;
    # HDCP version negotiated (0 = none, 12 = 1.2, 22 = 2.2, etc.).
    version @1 :UInt8;
}

struct ContentProtectionResult {
    success @0 :Bool;
    error @1 :T.Error;
}

struct ContentProtectionState {
    enabled @0 :Bool;
    version @1 :UInt8;
    streamType @2 :Text;
}

struct ApplyResult {
    # true = all changes applied successfully.
    ok @0 :Bool;
    # Per-field errors when ok=false.
    failures @1 :List(FieldError);
}

struct FieldError {
    field @0 :Text;
    reason @1 :Text;
}

struct MonitorEvent {
    monitorId @0 :T.OutputId;
    union {
        added @1 :Void;
        removed @2 :Void;
        modeChanged @3 :DisplayMode;
        refreshRateChanged @4 :Float32;
        brightnessChanged @5 :Float32;
        hdrModeChanged @6 :HdrMode;
        hdcpChanged @7 :HdcpState;
        enabledChanged @8 :Bool;
        positionChanged @9 :T.Vec2i;
        # Backend-specific monitor event type.
        custom @10 :Data;
    }
}

# ── Logical monitor (workspace-level, not hardware) ──
struct LogicalMonitor {
    id @0 :T.LogicalMonitorId;
    name @1 :Text;
    # Which physical output(s) this logical monitor spans.
    outputIds @2 :List(T.OutputId);
    # Position in the logical (virtual) display space.
    position @3 :T.Vec2i;
    scale @4 :Float32;
    transform @5 :T.SurfaceTransform;
}

struct LogicalMonitorConfig {
    name @0 :Text;
    outputIds @1 :List(T.OutputId);
    position @2 :T.Vec2i;
    scale @3 :Float32;
    transform @4 :T.SurfaceTransform;
    primary @5 :Bool;
}

# ── Audit-7 additions ────────────────────────────────────────

struct DisplayDpi {
    horizontal @0 :Float32;
    vertical @1 :Float32;
    diagonalInches @2 :Float32;
}

enum FoldState {
    unfolded @0;
    halfFolded @1;
    folded @2;
    flat @3;
    other @4;
    custom @5;
}

struct FoldPosition {
    hingeAngle @0 :Float32;
    creasePosition @1 :T.Vec2i;
    foldDirection @2 :FoldDirection;
}

enum FoldDirection {
    horizontal @0;
    vertical @1;
    other @2;
    custom @3;
}

enum AdaptiveRefreshPolicy {
    fixed @0;
    adaptive @1;
    alwaysLowLatency @2;
    powerSaver @3;
    other @4;
    custom @5;
}

struct IccProfile {
    id @0 :T.ColorProfileId;
    name @1 :Text;
    data @2 :T.DataHandle;
    colorSpace @3 :ColorSpace;
    version @4 :Text;
}

struct ColorManagementConfig {
    outputProfile @0 :T.ColorProfileId;
    renderingIntent @1 :RenderingIntent;
    gamutMapping @2 :GamutMapping;
}

enum RenderingIntent {
    perceptual @0;
    relativeColorimetric @1;
    saturation @2;
    absoluteColorimetric @3;
    other @4;
    custom @5;
}

enum GamutMapping {
    clip @0;
    compress @1;
    other @2;
    custom @3;
}

struct StylusDisplayEvent {
    outputId @0 :T.OutputId;
    position @1 :T.Vec2;
    pressure @2 :Float32;
    tilt @3 :T.Vec2;
    buttons @4 :UInt32;
    proximity @5 :Bool;
}

interface StylusInputSubscription {
    pull @0 () -> (events :List(StylusDisplayEvent));
    cancel @1 () -> T.VoidResult;
}

struct ArDisplayConfig {
    outputId @0 :T.OutputId;
    refreshMode @1 :T.DisplayRefreshMode;
    fovH @2 :Float32;
    fovV @3 :Float32;
    ipdMm @4 :Float32;
    stereoscopic @5 :T.DisplayStereoscopicMode;
    passthrough @6 :Bool;
}

struct CircularDisplayConfig {
    diameterMm @0 :Float32;
    bezelWidthMm @1 :Float32;
    centerCutout @2 :Bool;
}

struct SignageConfig {
    rotation @0 :T.SurfaceTransform;
    autoRotate @1 :Bool;
    rotationInterval @2 :T.Duration;
    lockedContent @3 :Bool;
}

struct KioskConfig {
    lockedApp @0 :T.AppId;
    allowedApps @1 :List(T.AppId);
    unlockGesture @2 :Text;
    unlockTimeout @3 :T.Duration;
}

struct DisplayTilingConfig {
    logicalDisplayId @0 :T.LogicalMonitorId;
    physicalOutputs @1 :List(T.OutputId);
    tilingMode @2 :TilingMode;
}

enum TilingMode {
    span @0;
    mirror @1;
    independent @2;
    other @3;
    custom @4;
}

struct DisplayPowerBudget {
    outputId @0 :T.OutputId;
    maxWatts @1 :Float32;
    currentWatts @2 :Float32;
    powerSavingMode @3 :Bool;
}

interface PowerBudgetSubscription {
    pull @0 () -> (budgets :List(DisplayPowerBudget));
    cancel @1 () -> T.VoidResult;
}

struct DisplayAccessibilityConfig {
    highContrast @0 :Bool;
    reducedMotion @1 :Bool;
    screenReaderEnabled @2 :Bool;
    largeText @3 :Bool;
    magnification @4 :Float32;
}

struct DisplayCapabilities {
    maxResolution @0 :T.Size;
    colorDepthBits @1 :UInt32;
    hdrStandards @2 :List(HdrStandard);
    foldable @3 :Bool;
    arCapable @4 :Bool;
    stylusSupport @5 :Bool;
    circular @6 :Bool;
    maxRefreshRate @7 :Float32;
    minRefreshRate @8 :Float32;
}

struct NightLightSchedule {
    mode @0 :NightLightMode;
    customStart @1 :Text;
    customEnd @2 :Text;
    location @3 :T.Vec2;
}

enum NightLightMode {
    sunsetSunrise @0;
    custom @1;
}

struct HdrCapabilities {
    standards @0 :List(HdrStandard);
    maxCllRange @1 :T.Vec2;
    fallRange @2 :T.Vec2;
    dolbyVisionProfiles @3 :List(Text);
}

struct DisplayFilter {
    connection @0 :DisplayConnection;
    enabled @1 :T.BoolFilter;
    hdrCapable @2 :T.BoolFilter;
}

enum ContentProtectionLevel {
    none @0;
    hdcp14 @1;
    hdcp22 @2;
    hdcp30 @3;
    other @4;
    custom @5;
}

struct CalibrationStatus {
    calibrated @0 :Bool;
    profileId @1 :T.ColorProfileId;
    lastCalibrated @2 :T.Timestamp;
    accuracy @3 :Float32;
}

struct DisplayRecommendation {
    setting @0 :Text;
    reason @1 :Text;
    confidence @2 :Float32;
}

struct NightLightGeoConfig {
    latitude @0 :Float64;
    longitude @1 :Float64;
    enabled @2 :Bool;
}

struct DisplayThermal {
    throttlingActive @0 :Bool;
    brightnessCap @1 :Float32;
    temperatureC @2 :Float32;
}

# ════════════════════════════════════════════════════════════════════════
# Audit-9 additions: wireless display pairing, content streaming,
# multi-user displays, gesture zones, and color accuracy testing.
# ════════════════════════════════════════════════════════════════════════

# ── Wireless Display ───────────────────────────────────────────────────
# Wireless display pairing and discovery (Miracast, AirPlay, Chromecast).
# Manages pairing, connection, and status of wireless displays.
struct WirelessDisplay {
    outputId @0 :T.OutputId;
    name @1 :Text;
    protocol @2 :WirelessDisplayProtocol;
    # Signal strength (0.0–1.0).
    signalStrength @3 :Float32;
    # Whether currently connected.
    connected @4 :Bool;
    # Device manufacturer.
    manufacturer @5 :Text;
    # Device model.
    model @6 :Text;
    # MAC address (for reconnection).
    macAddress @7 :Text;
}

enum WirelessDisplayProtocol {
    miracast @0;
    airplay @1;
    chromecast @2;
    dlna @3;
    other @4;
    custom @5;
}

# ── Content Streaming Config ───────────────────────────────────────────
# Codec negotiation and configuration for streaming content to displays.
# Controls video/audio codec, bitrate, and latency.
struct ContentStreamingConfig {
    outputId @0 :T.OutputId;
    videoCodec @1 :Text;
    audioCodec @2 :Text;
    # Target bitrate in bits per second.
    bitrate @3 :UInt64;
    # Target latency in milliseconds.
    latencyMs @4 :UInt32;
    # Resolution to stream at.
    width @5 :UInt32;
    height @6 :UInt32;
    # Frame rate.
    frameRate @7 :Float32;
}

# ── Display User Session ───────────────────────────────────────────────
# Multi-user display support. Enables multiple users to have
# independent content on the same display (e.g., split-screen).
struct DisplayUserSession {
    outputId @0 :T.OutputId;
    userId @1 :T.UserId;
    # Viewport assigned to this user (normalized 0.0–1.0).
    viewportX @2 :Float32;
    viewportY @3 :Float32;
    viewportWidth @4 :Float32;
    viewportHeight @5 :Float32;
    # Whether this user session is active.
    active @6 :Bool;
}

# ── Gesture Zone ───────────────────────────────────────────────────────
# Touch/gesture zones on displays. Defines regions that respond
# to specific gestures (e.g., swipe from edge for navigation).
struct GestureZone {
    outputId @0 :T.OutputId;
    # Zone name/identifier.
    name @1 :Text;
    # Zone region (normalized 0.0–1.0).
    x @2 :Float32;
    y @3 :Float32;
    width @4 :Float32;
    height @5 :Float32;
    # Gestures recognized in this zone.
    gestures @6 :List(GestureType);
    # Whether this zone is active.
    active @7 :Bool;
}

enum GestureType {
    swipeFromEdge @0;
    doubleTap @1;
    longPress @2;
    pinch @3;
    rotate @4;
    custom @5;
}

# ── Color Accuracy Test ────────────────────────────────────────────────
# Automated color accuracy verification for QA workflows. Measures
# Delta-E values for display color accuracy certification.
struct ColorAccuracyTest {
    outputId @0 :T.OutputId;
    # Overall Delta-E value (lower = more accurate, <1.0 = imperceptible).
    deltaE @1 :Float32;
    # Per-channel Delta-E values.
    redDeltaE @2 :Float32;
    greenDeltaE @3 :Float32;
    blueDeltaE @4 :Float32;
    # Gamma accuracy.
    gamma @5 :Float32;
    # White point accuracy (x, y in CIE 1931).
    whitePointX @6 :Float32;
    whitePointY @7 :Float32;
    # Whether the display passes accuracy thresholds.
    passed @8 :Bool;
    testedAt @9 :T.Timestamp;
}

# ═══════════════════════════════════════════════════════════════════════
# v0.0.2 additions — Display Provider
#
# A display driver is a capability. It produces frames (via the
# buffer scheme) and consumes surface commit requests. The driver
# framework's `DeviceService.bind` + `DriverLifecycle.start` is
# how this capability comes online. Once online, this provider
# interface is what the rest of the system uses.
# ═══════════════════════════════════════════════════════════════════════

interface DisplayProvider {
    # What kind of output is this? (HDMI, DP, eDP, MIPI-DSI, ...)
    getConnectorType @0 () -> (connectorType :Text);
    # Static EDID-equivalent metadata.
    getMetadata @1 () -> (metadata :DisplayMetadata);
    # What modes can this connector support?
    listModes @2 () -> (modes :List(ModeSpec));
    # Set the active mode; driver decides how to negotiate with HW.
    setMode @3 (modeId :Text) -> (result :T.VoidResult);
    # Whether the connector is physically attached.
    getConnectionStatus @4 () -> (status :ConnectionStatus);
    # Subscribe to hotplug events.
    subscribeConnection @5 () -> (subscription :ConnectionSubscription);
    # Health ping (see DriverLifecycle.ping).
    ping @6 () -> (health :T.DriverHealth);
}

struct DisplayMetadata {
    vendor @0 :Text;
    product @1 :Text;
    serial @2 :Text;
    # Manufactured week/year, if available.
    manufacturedWeek @3 :UInt16;
    manufacturedYear @4 :UInt16;
    # Capnp encoding of EDID / DisplayID data — driver decides.
    rawDescriptor @5 :Data;
}

struct ModeSpec {
    modeId @0 :Text;
    width @1 :UInt32;
    height @2 :UInt32;
    refreshHzMilli @3 :UInt32;  # 60000 = 60.000 Hz
    pixelClockHz @4 :UInt64;
    # Bit flags bitwise-ORed from DisplayModeFlags.
    flags @5 :UInt32;
    # Driver's reported preferred mode.
    preferred @6 :Bool;
}

# Driver-defined status; lives in display.capnp to keep
# connection events structured.
enum ConnectionStatus {
    connected @0;
    disconnected @1;
    unknown @2;
    error @3;
    custom @4;
}

interface ConnectionSubscription {
    pull @0 () -> (events :List(ConnectionEvent));
    cancel @1 () -> T.VoidResult;
}

struct ConnectionEvent {
    at @0 :UInt64;
    status @1 :ConnectionStatus;
}
