@0xa1b2c3d4e5f6000b;

# ═══════════════════════════════════════════════════════════════════════
# Theme — visual theme tokens, dark/light mode, motion, typography.
#
# WHAT THIS IS
#   A named token set, a subscription to changes, and the ability to install
#   and select themes. The protocol describes the tokens; it never assumes a
#   theming engine (Material You, Fluent, custom). The engine implementation
#   lives behind the interface, and swapping engines must not change
#   contract-visible behaviour.
#
# FOUR ALGORITHMS ARE GONE
#   `extractColorsFromImage`, `generateThemeFromColors`, `checkContrastRatio`
#   and `simulateColorBlindness` were algorithms exposed as IPC. Two engines
#   swapping produced different palettes from the same wallpaper while the
#   contract named no winner, so consumers could not depend on the output and
#   every implementer had to reverse-engineer the others' extraction. Contrast
#   ratio is arithmetic on two colours the caller already holds — the round
#   trip computed what the caller could compute locally for free and added a
#   rounding-convention fork. All four, and the five structs they returned,
#   are deleted.
#
# THE MIGRATION SUBSYSTEM IS GONE
#   Cap'n Proto's additive field evolution IS the migration story: unknown
#   fields are ignored and new fields default. `ThemeMigration`/
#   `ThemeMigrationResult` duplicated machinery the wire format already
#   provides and invented a second versioning channel beside abi.capnp.
#
# WHAT ELSE CHANGED
#   - `ThemeSubscription.pullPaged` deleted: paginating a snapshot stream is
#     meaningless, and one backend would have implemented it as "last N
#     snapshots" while another returned an error.
#   - `pullTheme` deleted: a manual poll beside the subscription is a second
#     path to one fact.
#   - `ThemeTokens` no longer nests a second full `ThemeTokens` for the light
#     palette — that doubled every snapshot delivered to every subscriber. A
#     companion theme is now referenced by id and fetched on demand.
#   - `ThemeTokens` carries an open token map, so a display paradigm that
#     needs a token this schema never named adds a key instead of waiting for
#     an ordinal.
#   - `installTheme` declares the bundle's content type, so user themes stay
#     portable across backends instead of each backend inventing a format.
#   - `ThemeVariantKind` (default/highContrast/monochrome/colorful/
#     accessibility/brand) became an open token: "colorful" and "brand" are
#     2020s design-tool vocabulary, and a future variant has no ordinal.
#     The open `setThemeVariant` name field already existed, so the enum was
#     a second naming system beside it.
#   - The three `getSystem*Preference` methods and their enums are deleted.
#     One owner: accessibility.capnp's `AccessibilityPreferences` is the
#     authoritative preference set. This service reports the ACTIVE theme,
#     not the user's preferences, and a theme consumer reads preferences from
#     the accessibility service — which it must do anyway to serve an AT.
#   - `SystemColorScheme.@0` was `light`, so an absent preference silently
#     meant light.
#   - `EasingCurve` is replaced by `T.AnimationSpec`, the canonical animation
#     vocabulary the rest of the protocol already uses. A theme can now
#     express bezier and spring curves the local three-value enum could not.
#   - `ThemeTokens` has ONE identity (`T.ThemeId`); the parallel `id :Text`
#     field is gone.
#
# WHAT WAS KEPT
#   The token model itself — colors, typography, spacing, shape, motion — is
#   the right shape for a timeless theme contract and is unchanged apart from
#   the choices above.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

interface Theme {

    # Snapshot of the active theme.
    getTheme @0 () -> (result :ThemeResult);

    # Subscribe to theme changes.
    subscribeTheme @1 () -> (subscription :ThemeSubscription);

    cancelTheme @2 (subscription :ThemeSubscription) -> T.VoidResult;

    # Setters — return T.VoidResult for typed error propagation.
    setDarkMode      @3 (dark :Bool) -> T.VoidResult;
    setAccentColor   @4 (color :T.Color) -> T.VoidResult;
    setFontScale     @5 (scale :Float32) -> T.VoidResult;

    # Apply a named theme variant. Backend resolves name -> tokens. The name
    # is an open token; conformance constants are published at the end of
    # this file.
    setThemeVariant  @6 (variant :Text) -> T.VoidResult;

    # List available theme variants the user can choose.
    listVariantsPaged @7 (pagination :T.Pagination)
                      -> (variants :List(ThemeVariant), total :UInt64);

    # List installed themes (user-installed + system-provided).
    listThemesPaged  @8 (pagination :T.Pagination)
                     -> (themes :List(ThemeInfo), total :UInt64);

    # Look up a specific theme by typed ID.
    getThemeById     @9 (themeId :T.ThemeId) -> (result :ThemeResult);

    # Query backend capabilities (which features are available).
    getCapabilities  @10 () -> (capabilities :ThemeCapabilities);

    # Install/uninstall a user theme provided as a serialized token bundle.
    # `format` declares the bundle's content type, so a theme stays portable
    # across backends instead of each backend inventing an encoding.
    installTheme     @11 (themeId :T.ThemeId, data :T.DataHandle,
                          format :T.MimeType) -> T.VoidResult;
    uninstallTheme   @12 (themeId :T.ThemeId) -> T.VoidResult;

    # Toggle high-contrast mode.
    setHighContrast  @13 (enabled :Bool) -> T.VoidResult;

    # Time-of-day theme scheduling.
    setThemeSchedule @14 (schedule :ThemeSchedule) -> T.VoidResult;
    getThemeSchedule @15 () -> (schedule :ThemeSchedule);

    # Per-app theme override. The HOST gates this: whether app X may override
    # the theme is a capability decision made at acquisition, not a parameter
    # this service re-decides per call.
    setPerAppTheme @16 (appId :T.AppId, themeId :T.ThemeId, priority :UInt32)
                    -> T.VoidResult;
}

# Subscription interface — pull+cancel pattern.
interface ThemeSubscription {
    pull   @0 () -> (tokens :ThemeTokens);
    cancel @1 () -> T.VoidResult;
}

struct ThemeResult {
    union {
        tokens  @0 :ThemeTokens;
        error   @1 :T.Error;
        unknown @2 :Void;
    }
}

# A full set of theme tokens.
struct ThemeTokens {
    # The one identity. A companion light/dark palette is a separate theme
    # referenced by id, not a nested copy of this struct.
    themeId @0 :T.ThemeId;
    name @1 :Text;
    dark @2 :Bool;
    # Open variant token — see the conformance constants at the end.
    variant @3 :Text;

    colors    @4 :ThemeColors;
    typography @5 :ThemeTypography;
    spacing   @6 :ThemeSpacing;
    shape     @7 :ThemeShape;
    motion    @8 :ThemeMotion;

    # Tokens this schema never named. A future display paradigm adds a key
    # here with no ordinal and no schema change; unrecognised keys are
    # ignored, never rejected.
    tokens @9 :T.StringMap;

    # The companion palette (light when this theme is dark, and vice versa),
    # fetched on demand. Previously this field held a second full ThemeTokens,
    # which doubled every snapshot delivered to every subscriber.
    companionThemeId @10 :T.ThemeId;

    # Optional parent theme for inheritance. Inherited themes fall back to
    # parent for any field not explicitly set.
    parentThemeId @11 :T.ThemeId;

    # Named subsystem this theme applies to (e.g., "shell", "editor",
    # "terminal"). Empty = global. A name, because a subsystem IS named; an
    # opaque id could not express "shell".
    subsystem @12 :Text;

    # Whether this theme is read-only (system theme) or user-editable.
    readOnly @13 :Bool;

    # Free-form metadata (author, version, license, source URL).
    metadata @14 :List(T.Meta);

    # Declaration that this theme is power-frugal. WHAT the engine does about
    # it — OLED-safe blacks, no blur, no shadow — is the engine's business,
    # not a wire instruction.
    powerFrugal @15 :Bool;

    # Schema version of these tokens; backend uses to interpret older sets.
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

# Motion durations and curves. Each slot is a full `T.AnimationSpec`, the
# canonical animation vocabulary the rest of the protocol uses, so a theme
# can express a bezier or spring curve and not only a named easing.
struct ThemeMotion {
    durationInstant   @0 :T.Duration;
    durationFast      @1 :T.Duration;
    durationShort     @2 :T.Duration;
    durationMedium    @3 :T.Duration;
    durationLong      @4 :T.Duration;
    durationExtraLong @5 :T.Duration;

    standard    @6 :T.AnimationSpec;
    emphasized  @7 :T.AnimationSpec;
    legacy      @8 :T.AnimationSpec;
}

# A named theme variant offered by the backend.
struct ThemeVariant {
    variantId   @0 :T.ThemeId;
    name        @1 :Text;
    # Open variant token.
    kind        @2 :Text;
    isActive    @3 :Bool;
    isUserInstalled @4 :Bool;
    metadata    @5 :List(T.Meta);
}

# Summary of an installed theme (used by listThemesPaged).
struct ThemeInfo {
    themeId         @0 :T.ThemeId;
    name            @1 :Text;
    variant         @2 :Text;
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

# What the backend can actually do. Booleans, not an enum: a new capability
# is a new field, which is additive and needs no ordinal.
struct ThemeCapabilities {
    supportsDarkMode           @0 :Bool;
    supportsAccentColor        @1 :Bool;
    supportsFontScale          @2 :Bool;
    supportsHighContrast       @3 :Bool;
    supportsUserInstalledThemes @4 :Bool;
    supportsDualPalette        @5 :Bool;
    supportsThemeInheritance   @6 :Bool;
    supportsPerSubsystemTheming @7 :Bool;
    supportsScheduling         @8 :Bool;
    # Maximum number of user-installed themes.
    maxUserThemes              @9 :UInt32;
}

# ── Theme Schedule ───────────────────────────────────────────

struct ThemeSchedule {
    entries @0 :List(ScheduleEntry);
    timezone @1 :Text;
    enabled @2 :Bool;
}

struct ScheduleEntry {
    # Local time of day, "HH:MM", 24-hour, zero-padded, interpreted in the
    # schedule's `timezone`. The format is stated so no backend parses
    # "22:00" its own way.
    startTime @0 :Text;
    endTime   @1 :Text;
    themeId @2 :T.ThemeId;
    transitionDuration @3 :T.Duration;
}

# ══════════════════════════════════════════════════════════════════════
# CONFORMANCE TOKENS — conventions, NOT contract
#
# Nothing above depends on any value in this section. They are published so
# that today's tools have a discoverable spelling, and an unrecognised value
# MUST be ignored rather than rejected. They are Text and deliberately NOT
# enums: an enum here would be an eternal commitment to today's spelling of
# a theme variant.
# ══════════════════════════════════════════════════════════════════════

const variantDefault      :Text = "default";
const variantHighContrast :Text = "highContrast";
const variantMonochrome   :Text = "monochrome";
const variantAccessible   :Text = "accessible";
const variantCustom       :Text = "custom";
