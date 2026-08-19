@0xa1b2c3d4e5f6000b;

# ═══════════════════════════════════════════════════════════════════════
# Theme — visual theme tokens, dark/light mode, motion, typography.
#
# The protocol describes theme tokens (color, typography, spacing,
# shape, motion) and the ability to subscribe to theme changes. It
# never assumes a specific theming engine (Material You, Fluent,
# custom). The interface is the contract; the engine implementation
# lives behind the interface.
#
# Audit-6 improvements:
#   - ThemeTokens gains light/dark token variants (theme palettes
#     are mode-dependent; many backends carry dual sets).
#   - Variant enum makes "default / highContrast / monochrome /
#     custom" theme variants first-class.
#   - ThemeInfo / SubscriptionInfo clarify wire-format ergonomics.
#   - ThemeCapabilities surfaces what the backend can do.
#   - ThemeTokens.parentThemeId enables theme inheritance.
#   - ThemeSubsystemId typed for cross-schema subsystem refs.
#
# Audit-7 improvements:
#   - Theme interface methods: getSystemColorScheme, getSystemContrastPreference,
#     getSystemMotionPreference, setThemeSchedule, getThemeSchedule,
#     extractColorsFromImage, generateThemeFromColors, checkContrastRatio,
#     setPerAppTheme, simulateColorBlindness.
#   - SystemColorScheme / SystemContrastPreference / SystemMotionPreference for OS preferences.
#   - ThemeSchedule / ScheduleEntry for time-of-day theme transitions.
#   - DynamicColorPalette for wallpaper-to-theme color extraction.
#   - ContrastResult / WcagLevel for WCAG contrast auditing.
#   - ColorDeficiency for color blindness simulation.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

interface Theme {

    # Snapshot of the active theme.
    getTheme @0 () -> (tokens :ThemeTokens);

    # Subscribe to theme changes (background service-style push).
    subscribeTheme @1 () -> (subscription :ThemeSubscription);

    # Manual poll of the current theme (alternative to subscription).
    pullTheme @2 (subscription :ThemeSubscription) -> (tokens :ThemeTokens);
    cancelTheme @3 (subscription :ThemeSubscription) -> T.VoidResult;

    # Setters — return T.VoidResult for typed error propagation.
    setDarkMode      @4 (dark :Bool) -> T.VoidResult;
    setAccentColor   @5 (color :T.Color) -> T.VoidResult;
    setFontScale     @6 (scale :Float32) -> T.VoidResult;

    # Audit-6 additions — richer theme control surface.

    # Apply a named theme variant. Backend resolves name -> tokens.
    setThemeVariant  @7 (variant :Text) -> T.VoidResult;

    # List available theme variants the user can choose.
    listVariantsPaged @8 (pagination :T.Pagination)
                       -> (variants :List(ThemeVariant), total :UInt64);

    # List installed themes (user-installed + system-provided).
    listThemesPaged  @9 (pagination :T.Pagination)
                       -> (themes :List(ThemeInfo), total :UInt64);

    # Look up a specific theme by typed ID.
    getThemeById     @10 (themeId :T.ThemeId) -> (tokens :ThemeTokens);

    # Query backend capabilities (which features are available).
    getCapabilities  @11 () -> (capabilities :ThemeCapabilities);

    # Install/uninstall a user theme provided as a serialized token bundle.
    installTheme     @12 (themeId :T.ThemeId, data :T.DataHandle) -> T.VoidResult;
    uninstallTheme   @13 (themeId :T.ThemeId) -> T.VoidResult;

    # Toggle high-contrast mode.
    setHighContrast  @14 (enabled :Bool) -> T.VoidResult;

    # ── Audit-7 additions ──

    # System preference reporting (audit-7).
    getSystemColorScheme @15 () -> (scheme :SystemColorScheme);
    getSystemContrastPreference @16 () -> (preference :SystemContrastPreference);
    getSystemMotionPreference @17 () -> (preference :SystemMotionPreference);

    # Time-of-day theme scheduling (audit-7 false positive: theme_schedule.capnp belongs here).
    setThemeSchedule @18 (schedule :ThemeSchedule) -> T.VoidResult;
    getThemeSchedule @19 () -> (schedule :ThemeSchedule);

    # Dynamic color from wallpaper (audit-7 false positive: dynamic_color.capnp belongs here).
    extractColorsFromImage @20 (image :T.DataHandle) -> (palette :DynamicColorPalette);
    generateThemeFromColors @21 (palette :DynamicColorPalette) -> (tokens :ThemeTokens);

    # Contrast auditing (audit-7).
    checkContrastRatio @22 (foreground :T.Color, background :T.Color) -> (result :ContrastResult);

    # Per-app theme override.
    setPerAppTheme @23 (appId :T.AppId, themeId :T.ThemeId, priority :UInt32) -> T.VoidResult;

    # Color blindness simulation (audit-7 false positive: accessibility_theme.capnp belongs here).
    simulateColorBlindness @24 (tokens :ThemeTokens, deficiency :ColorDeficiency) -> (simulated :ThemeTokens);
}

# Subscription interface — pull+cancel pattern (Rule 7).
interface ThemeSubscription {
    pull   @0 () -> (tokens :ThemeTokens);
    cancel @1 () -> T.VoidResult;

    # Paginated retrieval for high-frequency theme events.
    pullPaged @2 (pagination :T.Pagination)
              -> (tokens :List(ThemeTokens), total :UInt64);
}

# A full set of theme tokens.
struct ThemeTokens {
    # NOTE: id is Text (ordinal @0) for wire-format compatibility.
    # Consumers should treat the Text value as a theme identifier.
    # The typed themeId field (ordinal @8) provides cross-schema identity
    # and is preferred for structured identification.
    id        @0  :Text;
    name      @1  :Text;
    dark      @2  :Bool;
    variant   @3  :ThemeVariantKind;

    colors    @4  :ThemeColors;
    typography @5 :ThemeTypography;
    spacing   @6  :ThemeSpacing;
    shape     @7  :ThemeShape;
    motion    @8  :ThemeMotion;

    # Typed theme identifier for cross-schema references. Consumers
    # should prefer this field over the Text id (ordinal @0) for
    # structured theme identification.
    themeId   @9  :T.ThemeId;

    # Audit-6 additions.

    # Token set for light mode. When the theme carries dual palettes,
    # dark-mode tokens live here. Optional — backends without dual
    # palettes leave this null.
    lightTokens @10 :ThemeTokens;

    # Optional parent theme for inheritance. Inherited themes fall
    # back to parent for any field not explicitly set.
    parentThemeId @11 :T.ThemeId;

    # Named subsystem this theme applies to (e.g., "shell", "editor",
    # "terminal"). Empty = global. Enables per-subsystem theming
    # without breaking the global theme API.
    subsystem    @12 :Text;

    # Subsystem identifier (audit-6 typed). Preferred over Text `subsystem`
    # for cross-schema references.
    subsystemId  @13 :T.SubsystemId;

    # Whether this theme is read-only (system theme) or user-editable.
    readOnly     @14 :Bool;

    # Free-form metadata (author, version, license, source URL).
    metadata     @15 :List(T.Meta);

    # Schema version of these tokens; backend uses to interpret older
    # token sets.
    schemaVersion @16 :T.Version;
}

# Theme color palette.
struct ThemeColors {
    primary            @0  :T.Color;
    onPrimary          @1  :T.Color;
    primaryContainer   @2  :T.Color;
    onPrimaryContainer @3  :T.Color;

    secondary            @4  :T.Color;
    onSecondary          @5  :T.Color;
    secondaryContainer   @6  :T.Color;
    onSecondaryContainer @7  :T.Color;

    tertiary            @8  :T.Color;
    onTertiary          @9  :T.Color;
    tertiaryContainer   @10 :T.Color;
    onTertiaryContainer @11 :T.Color;

    error             @12 :T.Color;
    onError           @13 :T.Color;
    errorContainer    @14 :T.Color;
    onErrorContainer  @15 :T.Color;

    background        @16 :T.Color;
    onBackground      @17 :T.Color;
    surface           @18 :T.Color;
    onSurface         @19 :T.Color;
    surfaceVariant    @20 :T.Color;
    onSurfaceVariant  @21 :T.Color;
    outline           @22 :T.Color;
    outlineVariant    @23 :T.Color;

    inverseSurface    @24 :T.Color;
    inverseOnSurface  @25 :T.Color;
    inversePrimary    @26 :T.Color;

    shadow            @27 :T.Color;
    scrim             @28 :T.Color;
}

# Typography scale.
struct ThemeTypography {
    displayLarge   @0  :TextStyle;
    displayMedium  @1  :TextStyle;
    displaySmall   @2  :TextStyle;

    headlineLarge  @3  :TextStyle;
    headlineMedium @4  :TextStyle;
    headlineSmall  @5  :TextStyle;

    titleLarge     @6  :TextStyle;
    titleMedium    @7  :TextStyle;
    titleSmall     @8  :TextStyle;

    bodyLarge      @9  :TextStyle;
    bodyMedium     @10 :TextStyle;
    bodySmall      @11 :TextStyle;

    labelLarge     @12 :TextStyle;
    labelMedium    @13 :TextStyle;
    labelSmall     @14 :TextStyle;
}

struct TextStyle {
    fontFamily   @0 :Text;
    fontWeight   @1 :UInt32;
    fontSize     @2 :FontSize;
    lineHeight   @3 :LineHeight;
    letterSpacing @4 :LetterSpacing;
}

struct FontSize    { points @0 :Float32; }
struct LineHeight  { points @0 :Float32; }
struct LetterSpacing { points @0 :Float32; }

# Design-token spacing scale values. Unit is implicit (logical pixels / dp).
# Values define a typographic scale; the protocol leaves rendering units
# to the consumer.
struct ThemeSpacing {
    xs  @0 :Float32;
    sm  @1 :Float32;
    md  @2 :Float32;
    lg  @3 :Float32;
    xl  @4 :Float32;
    xxl @5 :Float32;
}

struct ThemeShape {
    extraSmall @0 :T.CornerRadius;
    small      @1 :T.CornerRadius;
    medium     @2 :T.CornerRadius;
    large      @3 :T.CornerRadius;
    extraLarge @4 :T.CornerRadius;
}

# Motion durations and easings.
struct ThemeMotion {
    durationInstant   @0 :T.Duration;
    durationFast      @1 :T.Duration;
    durationShort     @2 :T.Duration;
    durationMedium    @3 :T.Duration;
    durationLong      @4 :T.Duration;
    durationExtraLong @5 :T.Duration;

    easingStandard    @6 :EasingCurve;
    easingEmphasized  @7 :EasingCurve;
    easingLegacy      @8 :EasingCurve;
}

struct EasingCurve {
    union {
        standard    @0 :Void;
        emphasized  @1 :Void;
        legacy      @2 :Void;
        # Text-based custom easing is an escape hatch for non-standard
        # curves (e.g., cubic-bezier strings). No standard easing curve
        # enum exists in types.capnp; the protocol leaves curve
        # interpretation to the consumer.
        custom      @3 :Text;
    }
}

# Audit-6: first-class theme variant kind.
enum ThemeVariantKind {
    default        @0;
    highContrast   @1;
    monochrome     @2;
    colorful       @3;
    accessibility  @4;
    brand          @5;
    custom         @6;
}

# A named theme variant offered by the backend.
struct ThemeVariant {
    variantId   @0 :T.ThemeId;
    name        @1 :Text;
    kind        @2 :ThemeVariantKind;
    isActive    @3 :Bool;
    isUserInstalled @4 :Bool;
    metadata    @5 :List(T.Meta);
}

# Summary of an installed theme (used by listThemesPaged).
struct ThemeInfo {
    themeId         @0 :T.ThemeId;
    name            @1 :Text;
    variant         @2 :ThemeVariantKind;
    # True when this theme is currently active.
    active          @3 :Bool;
    # True when this theme is dark-themed.
    dark            @4 :Bool;
    # Author / source metadata.
    author          @5 :Text;
    source          @6 :Text;
    # Theme version.
    version         @7 :T.Version;
    # Whether the theme supports a dual light/dark palette.
    hasDualPalette  @8 :Bool;
    # Tags (UI controls can filter by tag).
    tags            @9 :List(Text);
    metadata        @10 :List(T.Meta);
}

# What the backend can actually do.
struct ThemeCapabilities {
    supportsDarkMode           @0 :Bool;
    supportsAccentColor        @1 :Bool;
    supportsFontScale          @2 :Bool;
    supportsHighContrast       @3 :Bool;
    supportsUserInstalledThemes @4 :Bool;
    supportsDualPalette        @5 :Bool;
    supportsThemeInheritance   @6 :Bool;
    supportsPerSubsystemTheming @7 :Bool;
    # Maximum number of user-installed themes.
    maxUserThemes              @8 :UInt32;
}

# ═══════════════════════════════════════════════════════════════════════
# AUDIT-7 ADDITIONS — System Preferences, Scheduling, Dynamic Color, Accessibility
# ═══════════════════════════════════════════════════════════════════════

# ── System Preferences (audit-7) ──
enum SystemColorScheme {
    light @0;
    dark @1;
    noPreference @2;
    other @3;
    custom @4;
}

enum SystemContrastPreference {
    noPreference @0;
    high @1;
    low @2;
    other @3;
    custom @4;
}

enum SystemMotionPreference {
    noPreference @0;
    reduceMotion @1;
    fullMotion @2;
    other @3;
    custom @4;
}

# ── Theme Schedule (audit-7 false positive: theme_schedule.capnp belongs here) ──
struct ThemeSchedule {
    entries @0 :List(ScheduleEntry);
    timezone @1 :Text;
    enabled @2 :Bool;
}

struct ScheduleEntry {
    startTime @0 :Text;
    endTime @1 :Text;
    themeId @2 :T.ThemeId;
    transitionDuration @3 :T.Duration;
}

# ── Dynamic Color Palette (audit-7 false positive: dynamic_color.capnp belongs here) ──
struct DynamicColorPalette {
    dominantColor @0 :T.Color;
    vibrantColor @1 :T.Color;
    mutedColor @2 :T.Color;
    darkVibrant @3 :T.Color;
    darkMuted @4 :T.Color;
    lightVibrant @5 :T.Color;
    lightMuted @6 :T.Color;
}

# ── Contrast Result (audit-7) ──
struct ContrastResult {
    ratio @0 :Float32;
    passes @1 :Bool;
    wcagLevel @2 :WcagLevel;
}

enum WcagLevel {
    fail @0;
    aa @1;
    aaa @2;
    other @3;
    custom @4;
}

# ── Color Blindness Simulation (audit-7 false positive: accessibility_theme.capnp belongs here) ──
enum ColorDeficiency {
    protanopia @0;
    deuteranopia @1;
    tritanopia @2;
    achromatopsia @3;
    other @4;
    custom @5;
}

# ════════════════════════════════════════════════════════════════════════
# Audit-9 additions: eco-mode themes, AI-curated themes, theme
# migration/versioning, theme export/import, and ambient adaptation.
# ════════════════════════════════════════════════════════════════════════

# ── Eco-Mode Theme ─────────────────────────────────────────────────────
# Power-saving theme configuration. Reduces animation, disables
# blur/shadow, and uses OLED-safe dark colors to minimize power.
struct EcoModeConfig {
    # Whether eco-mode is enabled.
    enabled @0 :Bool;
    # Reduce or disable animations.
    reduceAnimations @1 :Bool;
    # Use OLED-safe pure black backgrounds.
    oledSafeDark @2 :Bool;
    # Disable blur effects.
    disableBlur @3 :Bool;
    # Disable shadow rendering.
    disableShadows @4 :Bool;
    # Reduce color saturation to save power.
    desaturateColors @5 :Bool;
    # Maximum brightness cap (0.0–1.0).
    brightnessCap @6 :Float32;
    # Theme ID to apply when eco-mode is active.
    ecoThemeId @7 :T.ThemeId;
}

# ── AI-Curated Theme ───────────────────────────────────────────────────
# Theme generated by AI from user preferences, wallpaper, or
# content analysis. Provides personalization without manual curation.
struct AiThemeRequest {
    # Source image (e.g., wallpaper) for color extraction.
    sourceImage @0 :T.DataHandle;
    # User preferences (e.g., "warm", "minimal", "vibrant").
    preferences @1 :List(Text);
    # Whether to match system color scheme (light/dark).
    matchSystemScheme @2 :Bool;
    # Target variant kind.
    variant @3 :ThemeVariantKind;
}

struct AiThemeResult {
    # Generated theme tokens.
    tokens @0 :ThemeTokens;
    # Confidence in the generated theme (0.0–1.0).
    confidence @1 :Float32;
    # Reasoning for the theme choices.
    reasoning @2 :Text;
}

# ── Theme Migration ────────────────────────────────────────────────────
# Schema version upgrade for theme tokens. Enables migrating
# older theme formats to the current schema version.
struct ThemeMigration {
    # Source schema version.
    fromVersion @0 :T.Version;
    # Target schema version.
    toVersion @1 :T.Version;
    # Theme tokens to migrate.
    tokens @2 :ThemeTokens;
    # Whether to preserve custom fields during migration.
    preserveCustom @3 :Bool;
}

struct ThemeMigrationResult {
    # Migrated theme tokens.
    tokens @0 :ThemeTokens;
    # Warnings during migration (e.g., lost fields).
    warnings @1 :List(Text);
    # Whether migration was successful.
    success @2 :Bool;
}

# ── Theme Export/Import ────────────────────────────────────────────────
# Portable theme format for sharing themes across devices.
# Enables users to export, share, and import theme bundles.
struct ThemeExport {
    # Theme tokens to export.
    tokens @0 :ThemeTokens;
    # Export format version.
    formatVersion @1 :T.Version;
    # Author of the theme.
    author @2 :Text;
    # License for the theme.
    license @3 :Text;
    # Tags for theme discovery.
    tags @4 :List(Text);
    # Preview image data.
    preview @5 :T.DataHandle;
}

struct ThemeImportRequest {
    # Theme export data to import.
    export @0 :ThemeExport;
    # Whether to overwrite existing theme with same ID.
    overwrite @1 :Bool;
    # Whether to validate theme tokens against current schema.
    validate @2 :Bool;
}

# ── Ambient Adaptation ─────────────────────────────────────────────────
# Theme adapts to ambient light conditions. Uses ambient light sensor
# data to adjust theme brightness, contrast, and color temperature.
struct AmbientConfig {
    # Whether ambient adaptation is enabled.
    enabled @0 :Bool;
    # Minimum brightness in low ambient light.
    minBrightness @1 :Float32;
    # Maximum brightness in high ambient light.
    maxBrightness @2 :Float32;
    # Color temperature range (Kelvin) for ambient adaptation.
    minColorTempKelvin @3 :Float32;
    maxColorTempKelvin @4 :Float32;
    # Transition duration when ambient conditions change.
    transitionDuration @5 :T.Duration;
    # Whether to adapt contrast as well as brightness.
    adaptContrast @6 :Bool;
}

struct AmbientReading {
    # Ambient light level in lux.
    lightLevelLux @0 :Float32;
    # Ambient color temperature in Kelvin (0 = unknown).
    colorTempKelvin @1 :Float32;
    # Timestamp of the reading.
    timestamp @2 :T.Timestamp;
}
