@0xa1b2c3d4e5f60023;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Print - printer discovery, job submission, job management.
#
# Improvements beyond the original schema:
#   - PrinterId typed ID replaces bare Text for printer identification.
#   - DataHandle for print job source data that may exceed 1KB.
#   - Subscription cancel method added.
#   - Custom/other variants on all enums.
#   - PageSize width/height documented as inches.
#   - PrintJob.progress documented as percentage (0-100).
#   - listPrinters and getJobs now use T.Pagination (audit-3).
#   - PrintersSubscription.pull now accepts T.Pagination (audit-3).
#   - MediaType enum added for typed media identification (audit-4).
#   - PrintOptions.mediaType changed from bare Text to MediaType (audit-4).
#
# Audit-7 improvements:
#   - Print interface methods: getQueueStatus, setPrintSecurity, getPrintSecurity,
#     getPrintAccounting, getScanCapability, setColorProfile, getColorProfile,
#     estimateCost, getTransport.
#   - PrintQueueStatus for queue management.
#   - PrintSecurity for encrypted/PIN release/audit logging.
#   - PrintAccounting for usage tracking and cost management.
#   - ScanCapability for MFP scanner discovery.
#   - PrintColorProfile / PrintColorSpace / PrintRenderingIntent for color management.
#   - PrintCostEstimate for pre-print cost estimation.
#   - PrintTransport for cloud/AirPrint/Mopria/Wi-Fi Direct discovery.
# ═══════════════════════════════════════════════════════════════════════

# ── Media Type ──────────────────────────────────────────────────────────
# Typed replacement for bare Text media type identification.
# Covers common print media categories. Custom variant provides
# escape hatch for vendor-specific media (e.g., "transparency",
# "labels", "iron-on"). Promotable to types.capnp if cross-schema
# media type references become necessary.

enum MediaType {
    plain @0;
    photo @1;
    envelope @2;
    letterhead @3;
    bond @4;
    recycled @5;
    continuous @6;
    label @7;
    receipt @8;
    custom @9;
}

interface Print {
    listPrinters @0 (pagination :T.Pagination) -> (printers :List(Printer), total :UInt32);
    getPrinter @1 (printerId :T.PrinterId) -> (printer :Printer);

    print @2 (printerId :T.PrinterId, request :PrintRequest) -> (jobId :T.PrintJobId);
    cancelJob @3 (jobId :T.PrintJobId) -> T.VoidResult;
    pauseJob @4 (jobId :T.PrintJobId) -> T.VoidResult;
    resumeJob @5 (jobId :T.PrintJobId) -> T.VoidResult;
    restartJob @6 (jobId :T.PrintJobId) -> T.VoidResult;

    getJobs @7 (printerId :T.PrinterId, pagination :T.Pagination) -> (jobs :List(PrintJob), total :UInt32);
    getJob @8 (jobId :T.PrintJobId) -> (job :PrintJob);

    setDefaultPrinter @9 (printerId :T.PrinterId) -> T.VoidResult;
    getDefaultPrinter @10 () -> (printerId :T.PrinterId);

    subscribePrinters @11 () -> (subscription :PrintersSubscription);

    # ── Audit-7 additions ──

    # Print queue management.
    getQueueStatus @12 (printerId :T.PrinterId) -> (status :PrintQueueStatus);

    # Print security.
    setPrintSecurity @13 (printerId :T.PrinterId, security :PrintSecurity) -> T.VoidResult;
    getPrintSecurity @14 (printerId :T.PrinterId) -> (security :PrintSecurity);

    # Print accounting.
    getPrintAccounting @15 (printerId :T.PrinterId) -> (accounting :PrintAccounting);

    # Scanner capability (MFP).
    getScanCapability @16 (printerId :T.PrinterId) -> (capability :ScanCapability);

    # Color management.
    setColorProfile @17 (printerId :T.PrinterId, profile :PrintColorProfile) -> T.VoidResult;
    getColorProfile @18 (printerId :T.PrinterId) -> (profile :PrintColorProfile);

    # Print cost estimation.
    estimateCost @19 (printerId :T.PrinterId, request :PrintRequest) -> (cost :PrintCostEstimate);

    # Printer transport discovery.
    getTransport @20 (printerId :T.PrinterId) -> (transport :PrintTransport);

    # ── ICC profile lifecycle (audit-9 What's Still Missing) ──
    uploadIccProfile @21 (printerId :T.PrinterId, profile :IccProfile) -> (profileId :Text);
    downloadIccProfile @22 (printerId :T.PrinterId, profileId :Text) -> (profile :IccProfile);
    listIccProfiles @23 (printerId :T.PrinterId, pagination :T.Pagination) -> (profiles :List(IccProfile), total :UInt32);
    setDefaultIccProfile @24 (printerId :T.PrinterId, profileId :Text) -> T.VoidResult;

    # ── Print scheduling (audit-9 What's Still Missing) ──
    schedulePrint @25 (printerId :T.PrinterId, request :PrintRequest, scheduling :PrintScheduling) -> (jobId :T.PrintJobId);
    cancelScheduledPrint @26 (jobId :T.PrintJobId) -> T.VoidResult;

    # ── Consumable monitoring (audit-9 What's Still Missing) ──
    getConsumableStatus @27 (printerId :T.PrinterId) -> (consumables :List(ConsumableStatus));

    # ── 3D printing (audit-9 What's Still Missing) ──
    print3d @28 (printerId :T.PrinterId, request :T.DataHandle, config :Print3dConfig) -> (jobId :T.PrintJobId);
}

interface PrintersSubscription {
    pull @0 (pagination :T.Pagination) -> (printers :List(Printer), total :UInt32);
    cancel @1 () -> T.VoidResult;
}

struct Printer {
    id @0 :T.PrinterId;
    name @1 :Text;
    description @2 :Text;
    location @3 :Text;
    make @4 :Text;
    model @5 :Text;
    state @6 :PrinterState;
    capabilities @7 :PrinterCapabilities;
    defaults @8 :PrintOptions;
}

enum PrinterState {
    idle @0;
    processing @1;
    stopped @2;
    custom @3;
}

struct PrinterCapabilities {
    formats @0 :List(PrintFormat);
    colorModes @1 :List(ColorMode);
    duplexModes @2 :List(DuplexMode);
    pageSizes @3 :List(PageSize);
    # Maximum resolution in DPI (dots per inch).
    # NOTE: Does not distinguish horizontal/vertical DPI. A T.Resolution
    # struct would be more precise but is deferred to avoid ordinal changes.
    maxResolution @4 :UInt32;
    supported @5 :Bool;
}

enum PrintFormat {
    pdf @0;
    postscript @1;
    png @2;
    jpeg @3;
    svg @4;
    custom @5;
}

enum ColorMode {
    color @0;
    monochrome @1;
    grayscale @2;
    custom @3;
}

enum DuplexMode {
    none @0;
    longEdge @1;
    shortEdge @2;
    custom @3;
}

struct PageSize {
    name @0 :Text;
    # Width in inches (e.g., 8.5 for US Letter width).
    width @1 :Float32;
    # Height in inches (e.g., 11.0 for US Letter height).
    height @2 :Float32;
    # Width in PostScript points (1 point = 1/72 inch).
    widthPoints @3 :UInt32;
    # Height in PostScript points (1 point = 1/72 inch).
    heightPoints @4 :UInt32;
}

struct PrintRequest {
    title @0 :Text;
    # Print job source data — use buffer handle for documents >1KB.
    source @1 :T.DataHandle;
    format @2 :PrintFormat;
    options @3 :PrintOptions;
}

struct PrintOptions {
    copies @0 :UInt16;
    colorMode @1 :ColorMode;
    duplexMode @2 :DuplexMode;
    pageSize @3 :PageSize;
    range @4 :PrintRange;
    orientation @5 :Orientation;
    # Scale factor: 1.0 = normal, 0.5 = half size, 2.0 = double size.
    scale @6 :Float32;
    collate @7 :Bool;
    reverse @8 :Bool;
    # Media type (audit-4: changed from bare Text to typed MediaType enum).
    mediaType @9 :MediaType;
    quality @10 :PrintQuality;
}

struct PrintRange {
    union {
        all @0 :Void;
        pages @1 :List(UInt32);
        range @2 :PageRange;
        # A selection form the contract has not named (a named selection, a
        # bookmark, a whole document set). The alternative is a backend
        # truncating a request into `all` or `range` and printing the wrong
        # thing, which is the failure mode an extension point exists to stop.
        unknown @3 :T.UnknownEvent;
    }
}

struct PageRange {
    start @0 :UInt32;
    end @1 :UInt32;
}

enum Orientation {
    portrait @0;
    landscape @1;
    auto @2;
    custom @3;
}

enum PrintQuality {
    draft @0;
    normal @1;
    high @2;
    photo @3;
    custom @4;
}

struct PrintJob {
    id @0 :T.PrintJobId;
    printerId @1 :T.PrinterId;
    title @2 :Text;
    state @3 :JobState;
    pages @4 :UInt32;
    # Progress as percentage 0-100.
    progress @5 :UInt32;
    created @6 :T.Timestamp;
    completed @7 :T.Timestamp;
}

enum JobState {
    pending @0;
    held @1;
    processing @2;
    stopped @3;
    cancelled @4;
    aborted @5;
    completed @6;
    custom @7;
}

# ═══════════════════════════════════════════════════════════════════════
# AUDIT-7 ADDITIONS — Queue, Security, Accounting, Scanner, Color, Transport
# ═══════════════════════════════════════════════════════════════════════

# ── Print Queue Status ──
struct PrintQueueStatus {
    pendingJobs @0 :UInt32;
    processingJobs @1 :UInt32;
    heldJobs @2 :UInt32;
    totalPages @3 :UInt32;
}

# ── Print Security ──
struct PrintSecurity {
    encrypted @0 :Bool;
    holdUntilAuth @1 :Bool;
    pinRelease @2 :Bool;
    auditLog @3 :Bool;
}

# ── Print Accounting ──
struct PrintAccounting {
    totalPages @0 :UInt64;
    totalColorPages @1 :UInt64;
    estimatedCost @2 :Float32;
    currency @3 :Text;
}

# ── Scan Capability (MFP) ──
struct ScanCapability {
    hasFlatbed @0 :Bool;
    hasAdf @1 :Bool;
    adfDuplex @2 :Bool;
    maxScanResolution @3 :UInt32;
}

# ── Print Color Profile ──
struct PrintColorProfile {
    colorSpace @0 :PrintColorSpace;
    renderingIntent @1 :PrintRenderingIntent;
    iccProfileData @2 :T.DataHandle;
}

enum PrintColorSpace {
    srgb @0;
    adobeRgb @1;
    cmyk @2;
    cmykK @3;
    lab @4;
    other @5;
    custom @6;
}

enum PrintRenderingIntent {
    perceptual @0;
    relativeColorimetric @1;
    saturation @2;
    absoluteColorimetric @3;
    other @4;
    custom @5;
}

# ── Print Cost Estimate ──
struct PrintCostEstimate {
    estimatedCost @0 :Float32;
    currency @1 :Text;
    colorPages @2 :UInt32;
    monoPages @3 :UInt32;
}

# ── Print Transport ──
enum PrintTransport {
    local @0;
    ipp @1;
    ipps @2;
    airprint @3;
    mopria @4;
    wifidirect @5;
    usb @6;
    bluetooth @7;
    cloud @8;
    other @9;
    custom @10;
}

# ── ICC Profile Lifecycle (audit-8 What's Still Missing) ──
struct IccProfile {
    id @0 :Text;
    name @1 :Text;
    colorSpace @2 :PrintColorSpace;
    profileData @3 :T.DataHandle;
    isDefault @4 :Bool;
}

# ── Print Queue Scheduling (audit-8 What's Still Missing) ──
struct PrintScheduling {
    scheduledTime @0 :T.Timestamp;
    priority @1 :UInt8;
    quotaGroup @2 :Text;
}

# ── Ink/Toner Monitoring (audit-8 What's Still Missing) ──
struct ConsumableStatus {
    type @0 :ConsumableType;
    levelPercent @1 :UInt8;
    isLow @2 :Bool;
    isEmpty @3 :Bool;
}

enum ConsumableType {
    ink @0;
    toner @1;
    wasteToner @2;
    maintenanceKit @3;
    other @4;
    custom @5;
}

# ── 3D Printing (audit-8 What's Still Missing) ──
struct Print3dConfig {
    material @0 :Text;
    layerHeight @1 :Float32;
    infillDensity @2 :Float32;
    supportEnabled @3 :Bool;
}
