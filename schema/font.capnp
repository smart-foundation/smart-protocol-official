@0xa1b2c3d4e5f6000a;

# ══════════════════════════════════════════════════════════════════════
# Font — font discovery, matching, loading, metrics, and lifecycle events.
#
# Zero-backend-assumption IPC contract. No FreeType, CoreText, or
# platform-specific font system assumed. The backend decides the font
# pipeline; the protocol defines the contract.
#
# Improvements (audit):
#   - FontSession methods use typed FontId (already defined locally).
#   - FontSession HandshakeRequest.applicationId typed as T.AppId.
#   - FontSession.listFamilies paginated via FamilyFilter.page.
#   - FontSession.matchFonts paginated (maxResults → T.Pagination).
#   - FontEventStream has cancel() (already present).
#   - FontCapability has other variant for forward compatibility.
#   - FontWeight has other variant for forward compatibility.
#   - FontStretch has other variant for forward compatibility.
#   - FontWidth has other variant for forward compatibility.
#   - FontSlant has other variant for forward compatibility.
#   - FontSource has other variant for forward compatibility.
#   - HintingMode has other variant for forward compatibility.
#   - FontEventKind has other variant for forward compatibility.
#   - LoadedFont.loaded timestamp documented.
#   - FontMetrics fields documented as font units (not pixels).
#
# Improvements (audit-3):
#   - Removed local FontId definition; use T.FontId from types.capnp (Rule 2).
#
# Improvements (audit-5):
#   - FontEvent unknown variant renamed to custom for naming consistency (Rule 8).
#
# Audit-7 improvements:
#   - FontSession methods: getVariationAxes, setVariationAxis, getEmojiInfo,
#     getLicense, getSynthesisCapabilities, getColorFontInfo, getScriptFallbackChain.
#   - ColorFontFormat / ColorFontInfo for color font detection (CBDT, SVG, COLR, sbix).
#   - VariationSettings / VariationAxisValue for variable font runtime control.
#   - EmojiStyle / EmojiInfo for emoji presentation and skin-tone handling.
#   - FontLicense / LicenseType / EmbeddingRights for font licensing queries.
#   - SynthesisCapability for bold/italic synthesis advertisement.
#   - ScriptFallbackChain for script-based fallback (beyond language-based).
# ══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

# ══════════════════════════════════════════════════════════════════════
# SESSION
# Every font client starts here. One session per application.
# ══════════════════════════════════════════════════════════════════════

interface FontSession {

    struct HandshakeRequest {
        applicationId @0 :T.AppId;
        version       @1 :T.Version;
        metadata      @2 :List(T.Meta);
    }

    struct HandshakeResponse {
        sessionId @0 :T.SessionId;
        fontServer @1 :FontServerInfo;
        result    @2 :HandshakeResult;
    }

    enum HandshakeResult {
        accepted         @0;
        acceptedDegraded @1;
        rejected         @2;
        other            @3;
    }

    struct FontServerInfo {
        name            @0 :Text;
        version         @1 :T.Version;
        capabilities    @2 :List(FontCapability);
        defaultLanguage @3 :Text;
        metadata        @4 :List(T.Meta);
    }

    handshake @0 (request :HandshakeRequest)
               -> (response :HandshakeResponse);

    # -- Family Discovery --

    listFamilies    @1  (filter :FamilyFilter)
                      -> (families :List(FontFamilyEntry));
    findFamily      @2  (name :Text)
                      -> (family :FontFamilyEntry, found :Bool);

    # -- Face Discovery --

    listFaces       @3  (familyName :Text)
                      -> (faces :List(FontFaceEntry));
    getFaceInfo     @4  (descriptor :FontDescriptor)
                      -> (face :FontFaceEntry, found :Bool);

    # -- Font Matching --

    matchFont       @5  (query :FontMatchQuery)
                      -> (match :FontMatch);
    matchFonts      @6  (query :FontMatchQuery, page :T.Pagination)
                      -> (matches :List(FontMatch));

    # -- Font Loading --

    loadFont        @7  (descriptor :FontDescriptor)
                      -> (font :LoadedFont, result :T.VoidResult);
    unloadFont      @8  (fontId :T.FontId)
                      -> (result :T.VoidResult);

    # -- Metrics --

    getFontMetrics  @9  (fontId :T.FontId)
                      -> (metrics :FontMetrics, result :T.VoidResult);
    getGlyphMetrics @10 (fontId :T.FontId, codepoint :UInt32)
                      -> (metrics :GlyphMetrics, result :T.VoidResult);
    getKerning      @11 (fontId :T.FontId, leftGlyph :UInt32, rightGlyph :UInt32)
                      -> (kerning :KerningValue, result :T.VoidResult);

    # -- Fallback Chains --

    getFallbackChain      @12 (language :Text)
                           -> (chain :FallbackChain);
    setFallbackChain      @13 (chain :FallbackChain)
                           -> (result :T.VoidResult);
    addFallbackFont       @14 (language :Text, descriptor :FontDescriptor, position :UInt32)
                           -> (result :T.VoidResult);
    removeFallbackFont    @15 (language :Text, index :UInt32)
                           -> (result :T.VoidResult);
    getSystemFallbackChains @16 ()
                           -> (chains :List(FallbackChainEntry));

    # -- System Font Directories --

    listFontDirectories @17 () -> (directories :List(FontDirectory));
    scanFontDirectories @18 () -> (result :T.VoidResult);

    # -- Events --

    subscribe      @19 (filter :FontEventFilter)
                    -> (stream :FontEventStream);

    # -- Query --

    query          @20 (query :FontQueryRequest) -> (result :FontQueryResult);

    # -- Audit-7 additions --

    # Variable font runtime control (audit-7 false positive: font_variation.capnp belongs here).
    getVariationAxes @21 (fontId :T.FontId) -> (axes :List(VariableAxis));
    setVariationAxis @22 (fontId :T.FontId, tag :Text, value :Float32) -> T.VoidResult;

    # Emoji rendering info.
    getEmojiInfo @23 (fontId :T.FontId, codepoint :UInt32) -> (info :EmojiInfo);

    # Font licensing (audit-7 false positive: font_licensing.capnp belongs here).
    getLicense @24 (fontId :T.FontId) -> (license :FontLicense);

    # Font synthesis capabilities (audit-7 false positive: font_synthesis.capnp belongs here).
    getSynthesisCapabilities @25 () -> (capabilities :List(SynthesisCapability));

    # Color font info.
    getColorFontInfo @26 (fontId :T.FontId) -> (info :ColorFontInfo);

    # Script-based fallback chains.
    getScriptFallbackChain @27 (script :Text) -> (chain :ScriptFallbackChain);

    # -- Audit-9 additions --

    # Font subsetting.
    subsetFont @28 (request :FontSubsetRequest) -> (result :FontSubsetResult);

    # Font streaming.
    loadFontFromStream @29 (source :FontStreamSource) -> (font :LoadedFont, result :T.VoidResult);

    # Font caching configuration.
    setCacheConfig @30 (config :FontCacheConfig) -> T.VoidResult;
    getCacheConfig @31 () -> (config :FontCacheConfig);
    clearFontCache @32 () -> T.VoidResult;

    # Per-font hinting control.
    setHintingPreference @33 (preference :HintingPreference) -> T.VoidResult;
    getHintingPreference @34 (fontId :T.FontId) -> (preference :HintingPreference);

    # Font accessibility options.
    setAccessibilityOptions @35 (options :FontAccessibilityOptions) -> T.VoidResult;
    getAccessibilityOptions @36 () -> (options :FontAccessibilityOptions);
}

# ══════════════════════════════════════════════════════════════════════
# EXISTING FONT INTERFACE
# Ordinals 0-6 preserved exactly as-is.
# ══════════════════════════════════════════════════════════════════════

interface Font {
    listFamilies @0 () -> (families :List(FontFamily));
    findFont @1 (query :FontQuery) -> (font :FontInfo);
    getSystemFont @2 (name :Text) -> (font :FontInfo);
    getMonospaceFont @3 () -> (font :FontInfo);

    getMetrics @4 (family :Text, style :FontStyle) -> (metrics :FontMetrics);
    getGlyphInfo @5 (family :Text, style :FontStyle, codepoints :List(UInt32)) -> (glyphs :List(GlyphInfo));
    measureText @6 (family :Text, style :FontStyle, text :Text) -> (width :Float32, height :Float32);
}

# ══════════════════════════════════════════════════════════════════════
# EXISTING TYPES
# Ordinals 0-15 preserved exactly as-is.
# ══════════════════════════════════════════════════════════════════════

struct FontFamily {
    name @0 :Text;
    styles @1 :List(Text);
}

struct FontStyle {
    weight @0 :UInt16;
    width @1 :FontWidth;
    slant @2 :FontSlant;
}

enum FontWidth {
    ultraCondensed @0;
    extraCondensed @1;
    condensed @2;
    semiCondensed @3;
    normal @4;
    semiExpanded @5;
    expanded @6;
    extraExpanded @7;
    ultraExpanded @8;
    other @9;
}

enum FontSlant {
    normal @0;
    oblique @1;
    italic @2;
    other @3;
}

struct FontInfo {
    family @0 :Text;
    style @1 :FontStyle;
    path @2 :Text;
    postscriptName @3 :Text;
}

# Font metrics in font design units (not pixels).
# Units per em defines the coordinate space.
struct FontMetrics {
    ascent @0 :Float32;
    descent @1 :Float32;
    lineGap @2 :Float32;
    underlinePos @3 :Float32;
    underlineThickness @4 :Float32;
    strikethroughPos @5 :Float32;
    strikethroughThickness @6 :Float32;
    capHeight @7 :Float32;
    xHeight @8 :Float32;
    emSize @9 :Float32;
    unitsPerEm @10 :UInt32;
    indexToGeomScale @11 :Float32;
}

struct GlyphInfo {
    codepoint @0 :UInt32;
    advance @1 :Float32;
    bbox @2 :T.Rect;
    width @3 :Float32;
    height @4 :Float32;
    horizontalBearingX @5 :Float32;
    horizontalBearingY @6 :Float32;
    verticalBearingX @7 :Float32;
    verticalBearingY @8 :Float32;
    verticalAdvance @9 :Float32;
    boundingBox @10 :GlyphBoundingBox;
}

struct GlyphBoundingBox {
    xMin @0 :Float32;
    yMin @1 :Float32;
    xMax @2 :Float32;
    yMax @3 :Float32;
}

struct FontQuery {
    family @0 :Text;
    weight @1 :UInt16;
    width @2 :FontWidth;
    slant @3 :FontSlant;
    pixelSize @4 :Float32;
}

# ══════════════════════════════════════════════════════════════════════
# NEW TYPES — Font descriptor, face, query, match, events, capabilities
# ══════════════════════════════════════════════════════════════════════

# -- Font Descriptor --

struct FontDescriptor {
    familyName  @0 :Text;
    style       @1 :FontStyle;
    weight      @2 :FontWeight;
    stretch     @3 :FontStretch;
    slant       @4 :Float32;
    opticalSize @5 :UInt32;
    features    @6 :List(FontFeature);
    metadata    @7 :List(T.Meta);
}

struct FontFeature {
    tag    @0 :Text;
    value  @1 :UInt32;
}

# -- Enums --

enum FontWeight {
    thin       @0;
    extralight @1;
    light      @2;
    regular    @3;
    medium     @4;
    semibold   @5;
    bold       @6;
    extrabold  @7;
    black      @8;
    other      @9;
}

enum FontStretch {
    ultraCondensed @0;
    extraCondensed @1;
    condensed      @2;
    semiCondensed  @3;
    normal         @4;
    semiExpanded   @5;
    expanded       @6;
    extraExpanded  @7;
    ultraExpanded  @8;
    other          @9;
}

# -- Font Family (extended) --

struct FontFamilyEntry {
    name        @0 :Text;
    description @1 :Text;
    faceCount   @2 :UInt32;
    languages   @3 :List(Text);
    variable    @4 :Bool;
    source      @5 :FontSource;
    metadata    @6 :List(T.Meta);
}

enum FontSource {
    system  @0;
    user    @1;
    app     @2;
    bundled @3;
    other   @4;
}

# -- Font Face --

struct FontFaceEntry {
    descriptor  @0 :FontDescriptor;
    familyName  @1 :Text;
    file        @2 :Text;
    index       @3 :UInt32;
    variable    @4 :Bool;
    variableAxes @5 :List(VariableAxis);
    openType    @6 :OpenTypeInfo;
    metadata    @7 :List(T.Meta);
}

struct VariableAxis {
    tag          @0 :Text;
    name         @1 :Text;
    minimumValue @2 :Float32;
    maximumValue @3 :Float32;
    defaultValue @4 :Float32;
}

struct OpenTypeInfo {
    tables        @0 :List(Text);
    languageTags  @1 :List(Text);
    scriptTags    @2 :List(Text);
    featureTags   @3 :List(Text);
}

# -- Font Query (extended) --

struct FontMatchQuery {
    familyName  @0 :Text;
    style       @1 :FontStyle;
    weight      @2 :FontWeight;
    stretch     @3 :FontStretch;
    slant       @4 :Float32;
    opticalSize @5 :UInt32;
    language    @6 :Text;
    features    @7 :List(FontFeature);
    hinting     @8 :HintingMode;
    antialias   @9 :Bool;
    metadata   @10 :List(T.Meta);
}

enum HintingMode {
    none   @0;
    slight @1;
    medium @2;
    full   @3;
    other  @4;
}

# -- Font Match --

struct FontMatch {
    descriptor     @0 :FontDescriptor;
    face           @1 :FontFaceEntry;
    score          @2 :Float32;
    substitute     @3 :Bool;
    originalFamily @4 :Text;
    distance       @5 :MatchDistance;
}

struct MatchDistance {
    familyDistance      @0 :Float32;
    weightDistance      @1 :Float32;
    slantDistance       @2 :Float32;
    stretchDistance     @3 :Float32;
    opticalSizeDistance @4 :Float32;
    totalDistance       @5 :Float32;
}

# -- Loaded Font --

struct LoadedFont {
    fontId     @0 :T.FontId;
    descriptor @1 :FontDescriptor;
    face       @2 :FontFaceEntry;
    metrics    @3 :FontMetrics;
    # When this font was loaded.
    loaded     @4 :T.Timestamp;
}

# FontId is defined in types.capnp as T.FontId.
# Use T.FontId everywhere. The local definition is removed
# to prevent duplicate definitions and enable cross-schema references.

# -- Kerning --

struct KerningValue {
    x @0 :Float32;
    y @1 :Float32;
}

# -- Glyph Metrics (extended) --
# All values in font design units (not pixels).

struct GlyphMetrics {
    codepoint            @0 :UInt32;
    width                @1 :Float32;
    height               @2 :Float32;
    horizontalBearingX   @3 :Float32;
    horizontalBearingY   @4 :Float32;
    horizontalAdvance    @5 :Float32;
    verticalBearingX     @6 :Float32;
    verticalBearingY     @7 :Float32;
    verticalAdvance      @8 :Float32;
    boundingBox          @9 :GlyphBoundingBox;
}

# -- Fallback Chains --

struct FallbackChain {
    language @0 :Text;
    fonts    @1 :List(FontDescriptor);
}

struct FallbackChainEntry {
    language     @0 :Text;
    familyNames  @1 :List(Text);
    fontCount    @2 :UInt32;
    systemDefault @3 :Bool;
}

# -- Font Directories --

struct FontDirectory {
    path        @0 :Text;
    source      @1 :FontSource;
    writable    @2 :Bool;
    fontCount   @3 :UInt32;
    lastScanned @4 :T.Timestamp;
}

# -- Family Filter --

struct FamilyFilter {
    style    @0 :FontStyle;
    weight   @1 :FontWeight;
    stretch  @2 :FontStretch;
    source   @3 :FontSource;
    language @4 :Text;
    variable @5 :T.BoolFilter;
    # Pagination for unbounded result sets.
    page     @6 :T.Pagination;
}

# ══════════════════════════════════════════════════════════════════════
# EVENTS
# ══════════════════════════════════════════════════════════════════════

interface FontEventStream {
    next   @0 () -> (event :FontEvent);
    # Explicit cancellation — stops the event stream and releases resources.
    cancel @1 ();
}

struct FontEventFilter {
    kinds     @0 :List(FontEventKind);
    languages @1 :List(Text);
}

enum FontEventKind {
    fontInstalled   @0;
    fontRemoved     @1;
    familyAdded     @2;
    familyRemoved   @3;
    fallbackChanged @4;
    directoryScanned @5;
    fontLoaded      @6;
    fontUnloaded    @7;
    other           @8;
}

struct FontEvent {
    union {
        fontInstalled        @0 :FontInstalledEvent;
        fontRemoved          @1 :FontRemovedEvent;
        familyAdded          @2 :FamilyAddedEvent;
        familyRemoved        @3 :FamilyRemovedEvent;
        fallbackChainChanged @4 :FallbackChainChangedEvent;
        directoryScanned     @5 :DirectoryScannedEvent;
        fontLoaded           @6 :FontLoadedEvent;
        fontUnloaded         @7 :FontUnloadedEvent;
        custom               @8 :UnknownFontEvent;
    }
}

struct UnknownFontEvent {
    typeId  @0 :UInt64;
    payload @1 :Data;
}

struct FontInstalledEvent {
    familyName @0 :Text;
    face       @1 :FontFaceEntry;
    path       @2 :Text;
    source     @3 :FontSource;
    timestamp  @4 :T.Timestamp;
}

struct FontRemovedEvent {
    familyName @0 :Text;
    descriptor @1 :FontDescriptor;
    path       @2 :Text;
    timestamp  @3 :T.Timestamp;
}

struct FamilyAddedEvent {
    family    @0 :FontFamilyEntry;
    timestamp @1 :T.Timestamp;
}

struct FamilyRemovedEvent {
    familyName @0 :Text;
    timestamp  @1 :T.Timestamp;
}

struct FallbackChainChangedEvent {
    chain     @0 :FallbackChain;
    timestamp @1 :T.Timestamp;
}

struct DirectoryScannedEvent {
    directory  @0 :FontDirectory;
    fontCount  @1 :UInt32;
    timestamp  @2 :T.Timestamp;
}

struct FontLoadedEvent {
    font      @0 :LoadedFont;
    timestamp @1 :T.Timestamp;
}

struct FontUnloadedEvent {
    fontId    @0 :T.FontId;
    timestamp @1 :T.Timestamp;
}

# ══════════════════════════════════════════════════════════════════════
# QUERY
# ══════════════════════════════════════════════════════════════════════

struct FontQueryRequest {
    union {
        allFamilies          @0 :Void;
        familyByName         @1 :Text;
        facesForFamily       @2 :Text;
        faceByDescriptor     @3 :FontDescriptor;
        fallbackChains       @4 :Void;
        fallbackChainForLang @5 :Text;
        fontDirectories      @6 :Void;
        fontServerCapabilities @7 :Void;
        custom               @8 :CustomFontQuery;
    }
}

struct CustomFontQuery {
    name       @0 :Text;
    parameters @1 :List(T.Meta);
}

struct FontQueryResult {
    union {
        families           @0 :List(FontFamilyEntry);
        family             @1 :FontFamilyEntry;
        faces              @2 :List(FontFaceEntry);
        face               @3 :FontFaceEntry;
        fallbackChains     @4 :List(FallbackChainEntry);
        fallbackChain      @5 :FallbackChain;
        fontDirectories    @6 :List(FontDirectory);
        capabilities       @7 :List(FontCapability);
        custom             @8 :List(T.Meta);
        notFound           @9 :Void;
        notSupported       @10 :Void;
    }
}

# ══════════════════════════════════════════════════════════════════════
# CAPABILITIES
# ══════════════════════════════════════════════════════════════════════

enum FontCapability {
    listFamilies        @0;
    matchFonts          @1;
    loadFonts           @2;
    fontMetrics         @3;
    glyphMetrics        @4;
    kerning             @5;
    fallbackChains      @6;
    directoryScanning   @7;
    variableFonts       @8;
    openTypeFeatures    @9;
    customCapabilities  @10;
    other               @11;
}

# ══════════════════════════════════════════════════════════════════════
# AUDIT-7 ADDITIONS — Color Fonts, Variations, Emoji, Licensing, Synthesis
# ══════════════════════════════════════════════════════════════════════

# ── Color Font Support ──
enum ColorFontFormat {
    cbdt @0;
    svg @1;
    colr @2;
    sbix @3;
    none @4;
    other @5;
    custom @6;
}

struct ColorFontInfo {
    format @0 :ColorFontFormat;
    layers @1 :UInt32;
    palette @2 :UInt32;
    bitmapSize @3 :UInt32;
}

# ── Variable Font Runtime Control (audit-7 false positive: font_variation.capnp belongs here) ──
struct VariationSettings {
    axes @0 :List(VariationAxisValue);
    instance @1 :Text;
}

struct VariationAxisValue {
    tag @0 :Text;
    value @1 :Float32;
}

# ── Emoji Rendering ──
enum EmojiStyle {
    text @0;
    emoji @1;
    default @2;
    other @3;
    custom @4;
}

struct EmojiInfo {
    presentation @0 :EmojiStyle;
    skinTones @1 :UInt32;
    zwjSequence @2 :Bool;
    flags @3 :List(Text);
}

# ── Font Licensing (audit-7 false positive: font_licensing.capnp belongs here) ──
struct FontLicense {
    type @0 :LicenseType;
    name @1 :Text;
    url @2 :Text;
    embedding @3 :EmbeddingRights;
    subsetting @4 :Bool;
    commercial @5 :Bool;
}

enum LicenseType {
    openSource @0;
    commercial @1;
    trial @2;
    restricted @3;
    unknown @4;
    other @5;
    custom @6;
}

enum EmbeddingRights {
    installable @0;
    preview @1;
    editable @2;
    restricted @3;
    other @4;
    custom @5;
}

# ── Font Synthesis (audit-7 false positive: font_synthesis.capnp belongs here) ──
enum SynthesisCapability {
    none @0;
    italic @1;
    bold @2;
    oblique @3;
    opticalSize @4;
    other @5;
    custom @6;
}

# ── Script-Based Fallback ──
struct ScriptFallbackChain {
    script @0 :Text;
    language @1 :Text;
    fonts @2 :List(FontDescriptor);
    emojiFonts @3 :List(FontDescriptor);
}

# ════════════════════════════════════════════════════════════════════════
# Audit-9 additions: font subsetting, font streaming, font caching,
# font hinting control, and font accessibility.
# ════════════════════════════════════════════════════════════════════════

# ── Font Subsetting ────────────────────────────────────────────────────
# Request a subset of a font containing only specified codepoints.
# Reduces font file size for web and embedded use cases.
struct FontSubsetRequest {
    fontId @0 :T.FontId;
    # Codepoints to include in the subset.
    codepoints @1 :List(UInt32);
    # Whether to include OpenType layout features.
    includeFeatures @2 :Bool;
    # Whether to drop hinting data.
    dropHinting @3 :Bool;
}

struct FontSubsetResult {
    # Subset font data.
    data @0 :T.DataHandle;
    # Original font size in bytes.
    originalSize @1 :UInt32;
    # Subset font size in bytes.
    subsetSize @2 :UInt32;
    # Number of glyphs in the subset.
    glyphCount @3 :UInt32;
}

# ── Font Streaming ─────────────────────────────────────────────────────
# Load fonts from network streams. Enables progressive font loading
# and streaming font data without requiring a local file path.
struct FontStreamSource {
    # URL to stream font data from.
    url @0 :T.Uri;
    # MIME type of the font data.
    mimeType @1 :Text;
    # HTTP headers for the request.
    headers @2 :T.StringMap;
    # Timeout for the streaming connection.
    timeout @3 :T.Duration;
    # Whether to cache the streamed font locally.
    cacheLocally @4 :Bool;
}

# ── Font Cache Configuration ───────────────────────────────────────────
# Configuration for font data caching. Controls cache size limits,
# eviction policies, and preloading behavior.
struct FontCacheConfig {
    # Maximum cache size in bytes.
    maxSizeBytes @0 :UInt64;
    # Eviction policy when cache is full.
    evictionPolicy @1 :CacheEvictionPolicy;
    # Fonts to preload into cache on startup.
    preloadFonts @2 :List(FontDescriptor);
    # Whether to enable disk caching.
    diskCache @3 :Bool;
    # Disk cache directory path (empty = system default).
    diskCachePath @4 :Text;
}

enum CacheEvictionPolicy {
    lru @0;
    lfu @1;
    fifo @2;
    random @3;
    custom @4;
}

# ── Font Hinting Control ───────────────────────────────────────────────
# Per-font hinting preferences. Controls how font hinting is applied
# for different rendering contexts (screen, print, animation).
struct HintingPreference {
    fontId @0 :T.FontId;
    # Hinting mode for this font.
    mode @1 :HintingMode;
    # Whether to use sub-pixel positioning.
    subpixelPositioning @2 :Bool;
    # Target DPI for hinting calculations.
    targetDpi @3 :UInt32;
    # Whether to auto-hint (use hinting from the font file).
    autoHint @4 :Bool;
}

# ── Font Accessibility ─────────────────────────────────────────────────
# Font accessibility options. Controls rendering adaptations for
# users with visual impairments (dyslexia, low vision).
struct FontAccessibilityOptions {
    # Whether to use dyslexia-friendly font substitution.
    dyslexiaFriendly @0 :Bool;
    # Whether to use high-contrast font rendering.
    highContrast @1 :Bool;
    # Minimum font size override (in points).
    minimumSizePoints @2 :Float32;
    # Letter spacing override (in points, added to natural spacing).
    letterSpacingOverride @3 :Float32;
    # Word spacing override (in points, added to natural spacing).
    wordSpacingOverride @4 :Float32;
    # Whether to use OpenType accessibility features.
    useAccessibilityFeatures @5 :Bool;
}
