@0xa1b2c3d4e5f6002c;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Translation — text translation between languages.
#
# Backend-agnostic: works with any translation engine (local models,
# hosted services, offline rule systems). The schema defines the
# translation contract, not the implementation.
#
# ── FOUR DEFECTS, FIXED ───────────────────────────────────────────────
#
# 1. THE STREAM WAS NOT AN OBJECT. `startStream` returned a plain struct
#    (`TranslationStream { sessionId @0 :Text }`) that nothing could pull
#    from — the pullable interface was reachable only through a different
#    method (`subscribeTranslationStream`) — and no method declared who
#    generates the sessionId. `startStream` now returns the session
#    interface itself, as ai.capnp's ArtifactStream does.
#
# 2. THE BATCH SUBSCRIPTION KEY CAME FROM NOWHERE.
#    `subscribeBatchProgress` took a `batchId` that no method produced
#    (`translateBatch` returned results and a total). Either every
#    implementer invented a batch-id namespace or the method was
#    unreachable. `translateBatch` now returns the id.
#
# 3. THE LANGUAGE-TAG FORMAT WAS NEVER DECLARED, and three conventions
#    coexisted: T.Language.code documented as ISO 639-1, a
#    "regionalVariant" example written "en-US" (BCP-47), and an
#    unspecified fallback chain. A 2046 implementer could not know
#    whether "en" meant English, an ISO 639-1 code, or a BCP-47 prefix,
#    so the file's core parameter was guesswork per backend. Every
#    language parameter is T.Language now, and the regional variant is
#    a declared suffix of it.
#
# 4. NO ERROR PATH. The file contained zero unions, so a failure and an
#    empty input both produced an empty `translatedText` and a consumer
#    could not tell them apart. One `TranslationOutcome` union carries
#    T.Error beside the existing result structs, so no payload struct
#    changed shape.
#
# ── BULK INPUT IS A HANDLE ────────────────────────────────────────────
#
# Documents arrived as inline `Text`, so a 10 MB translated document was
# copied into the message, and `importMemory` accepted an unbounded
# segment list — importing a real translation memory (millions of
# segments) exceeded the message limit with no chunked contract.
#
# Improvements (audit-7), unchanged:
#   - Multi-target translation.
#   - Streaming translation for real-time feeds.
#   - Formatting preservation, tone/register control, auto-fallback.
#   - Language detection with per-sentence and mixed-script support.
#   - Translation memory, glossary enforcement, quality estimation.
#   - Word-level alignment, domain context.
# ═══════════════════════════════════════════════════════════════════════

interface Translation {
    translate @0 (text :T.DataHandle, sourceLang :T.Language, targetLang :T.Language)
               -> (outcome :TranslationOutcome);
    # Returns the batch id, which is the key `subscribeBatchProgress`
    # takes. Pagination on the caller's own input list was removed: the
    # caller chunks its own data, so it bought nothing for wire size,
    # and the returned `total` meant something different from every
    # other paginated method in the tree.
    translateBatch @1 (texts :List(T.DataHandle), sourceLang :T.Language, targetLang :T.Language)
                   -> (outcome :TranslationOutcome, batchId :Text);
    detectLanguage @2 (text :T.DataHandle) -> (outcome :TranslationOutcome);

    listSupportedLanguages @3 (pagination :T.Pagination) -> (languages :List(T.Language), total :UInt64);
    isAvailable @4 (sourceLang :T.Language, targetLang :T.Language) -> (available :Bool);
    isOffline @5 (sourceLang :T.Language, targetLang :T.Language) -> (offline :Bool);

    getTranslationCache @6 (sourceLang :T.Language, targetLang :T.Language) -> (sizeBytes :UInt64);
    clearTranslationCache @7 () -> T.VoidResult;

    # ── Audit-7 additions ────────────────────────────────────

    # Translate to multiple target languages in one call.
    translateMultiTarget @8 (text :T.DataHandle, sourceLang :T.Language, targetLangs :List(T.Language))
                         -> (outcome :TranslationOutcome);

    # Start a streaming translation session. Returns the SESSION
    # INTERFACE, so the object handed back is pullable and the
    # session-id namespace is owned by the backend that issued it.
    startStream @9 (sourceLang :T.Language, targetLang :T.Language, config :TranslationStreamConfig)
                 -> (session :TranslationStreamSession);

    # Detect language with per-sentence and mixed-script support.
    detectLanguageDetailed @10 (text :T.DataHandle) -> (outcome :TranslationOutcome);

    # Set auto-fallback policy for graceful degradation.
    setFallbackPolicy @11 (sourceLang :T.Language, targetLang :T.Language, policy :AutoFallbackPolicy)
                      -> T.VoidResult;

    # Look up a segment in translation memory.
    lookupMemory @12 (sourceText :T.DataHandle, sourceLang :T.Language, targetLang :T.Language)
                 -> (outcome :TranslationOutcome);

    # Store a segment in translation memory.
    storeMemory @13 (segment :MemorySegment) -> T.VoidResult;

    # Get translation memory statistics.
    getMemoryStats @14 () -> (stats :TranslationMemoryStats);

    # Estimate translation quality without reference text.
    estimateQuality @15 (sourceText :T.DataHandle, translatedText :T.DataHandle,
                         sourceLang :T.Language, targetLang :T.Language)
                    -> (outcome :TranslationOutcome);

    # Align source and target texts at word level.
    alignTexts @16 (sourceText :T.DataHandle, targetText :T.DataHandle,
                    sourceLang :T.Language, targetLang :T.Language)
                -> (outcome :TranslationOutcome);

    # Check terminology against a glossary.
    checkGlossary @17 (text :T.DataHandle, sourceLang :T.Language, targetLang :T.Language, glossaryId :Text)
                   -> (violations :List(GlossaryViolation));

    # ── Audit-9: Streaming subscription ──
    subscribeTranslationStream @18 (sourceLang :T.Language, targetLang :T.Language, config :TranslationStreamConfig)
        -> (session :TranslationStreamSession);

    # ── Audit-9: Translation memory export/import ──
    exportMemory @19 (pagination :T.Pagination) -> (segments :List(MemorySegment), total :UInt64);
    # A handle, so a real translation memory (millions of segments) is
    # importable instead of exceeding the message limit.
    importMemory @20 (segments :T.DataHandle) -> (imported :UInt64);

    # ── Audit-9: Glossary CRUD ──
    createGlossary @21 (name :Text, sourceLang :T.Language, targetLang :T.Language, entries :List(GlossaryEntry))
        -> (glossaryId :Text);
    updateGlossary @22 (glossaryId :Text, entries :List(GlossaryEntry)) -> T.VoidResult;
    deleteGlossary @23 (glossaryId :Text) -> T.VoidResult;
    listGlossaries @24 (pagination :T.Pagination) -> (glossaries :List(Glossary), total :UInt64);

    # ── Audit-9: Quality feedback ──
    reportQualityIssue @25 (sourceText :T.DataHandle, translatedText :T.DataHandle,
                            sourceLang :T.Language, targetLang :T.Language,
                            issues :List(T.Warning)) -> T.VoidResult;

    # ── Audit-9: Batch progress subscription ──
    # `batchId` is the value `translateBatch` returns.
    subscribeBatchProgress @26 (batchId :Text) -> (subscription :BatchProgressSubscription);

    # ── Audit-9: Alignment export ──
    exportAlignment @27 (sourceText :T.DataHandle, targetText :T.DataHandle,
                         sourceLang :T.Language, targetLang :T.Language)
        -> (outcome :TranslationOutcome);

    # ── Audit-10: Translation context/domain ──
    setTranslationContext @28 (context :TranslationContext) -> T.VoidResult;
    getTranslationContext @29 () -> (context :TranslationContext);

    # ── Audit-10: Translation memory deduplication ──
    # The deduplication KEY is stated in the schema, not only in an
    # enum's doc comment: a backend that deduplicated on sourceText
    # alone would silently drop distinct translations.
    importMemoryDedup @30 (segments :T.DataHandle, strategy :DedupStrategy)
        -> (imported :UInt64, skipped :UInt64, duplicates :UInt64);

    # ── Audit-10: Glossary version history ──
    getGlossaryVersions @31 (glossaryId :Text, pagination :T.Pagination)
        -> (versions :List(GlossaryVersion), total :UInt32);
    rollbackGlossary @32 (glossaryId :Text, versionId :Text) -> T.VoidResult;
}

# ── Translation Result ───────────────────────────────────────

struct TranslationResult {
    translatedText @0 :T.DataHandle;
    detectedLanguage @1 :T.Language;
    # Confidence score in the range 0.0 (no confidence) to 1.0 (certain).
    confidence @2 :Float32;
    translations @3 :List(AlternateTranslation);
    # Tone/register used for this translation (audit-7), as an open token.
    tone @4 :Text;
    custom @5 :Data;
}

struct AlternateTranslation {
    text @0 :T.DataHandle;
    # Model identifier (implementation-specific). No typed model enum
    # exists because model catalogs vary across backends.
    model @1 :Text;
    # Score in the range 0.0 to 1.0.
    score @2 :Float32;
}

# ── Streaming Translation ────────────────────────────────────

struct TranslationStreamConfig {
    # Maximum time to wait before sending interim results.
    interimInterval @0 :T.Duration;
    # Whether to provide interim results during translation. When false
    # a backend MUST NOT stream interim results — previously it might.
    provideInterim @1 :Bool;
    parameters @2 :T.StringMap;
}

# The session interface itself. `TranslationStream` (a struct carrying a
# bare sessionId) is deleted: nothing could pull from it, no method
# declared who generates its id, and the usable session type was
# returned by a different method.

interface TranslationStreamSession {
    # Push source text for translation.
    pushSource @0 (text :T.DataHandle, final :Bool) -> T.VoidResult;

    # Pull the next batch of translated results (interim or final).
    pullResults @1 () -> (results :List(StreamTranslationResult), hasMore :Bool);

    # Commit the stream (finalize translation).
    commit @2 () -> T.VoidResult;

    # Cancel the stream.
    cancel @3 () -> T.VoidResult;
}

struct StreamTranslationResult {
    # The translated text (interim or final).
    translatedText @0 :T.DataHandle;
    # Whether this is a final (committed) result.
    isFinal @1 :Bool;
    # Confidence score.
    confidence @2 :Float32;
    # Source text range this result corresponds to.
    sourceOffset @3 :UInt32;
    sourceLength @4 :UInt32;
}

# ── Language Detection ───────────────────────────────────────

struct LanguageDetectionResult {
    # Detected languages (may be multiple for mixed-script text).
    languages @0 :List(LanguageDetection);
    mixedScript @1 :Bool;
    codeSwitchDetected @2 :Bool;
    custom @3 :Data;
}

struct LanguageDetection {
    language @0 :T.Language;
    confidence @1 :Float32;
    # Byte range in the source text where this language was detected.
    byteOffset @2 :UInt32;
    byteLength @3 :UInt32;
}

# ── Auto-Fallback Policy ────────────────────────────────────
# The fallback chain is List(T.Language), so the format is the same one
# every other language parameter uses — previously an unspecified Text
# list was the third convention in one file.

struct AutoFallbackPolicy {
    fallbackChain @0 :List(T.Language);
    maxRetries @1 :UInt32;
    timeoutPerAttempt @2 :T.Duration;
    # Whether a degraded translation is reported: when true, a fallback
    # is visible in the result rather than only inferable by comparing
    # the requested and detected languages.
    reportDegradation @3 :Bool;
}

# ── Formatting Preservation ──────────────────────────────────

struct FormattedText {
    text @0 :T.DataHandle;
    tags @1 :List(TextTag);
}

struct TextTag {
    offset @0 :UInt32;
    length @1 :UInt32;
    # Tag type, as an open token (e.g., "bold", "italic", "link").
    type @2 :Text;
    # Optional tag value (e.g., URL for "link" tags).
    value @3 :Text;
}

# ── Tone / Register ─────────────────────────────────────────
# Open token: a 2046 register (or a domain-specific one) is nameable
# without a new ordinal.

# ── Translation Memory ───────────────────────────────────────

struct MemorySegment {
    sourceText @0 :T.DataHandle;
    targetText @1 :T.DataHandle;
    sourceLang @2 :T.Language;
    targetLang @3 :T.Language;
    storedAt @4 :T.Timestamp;
    confidence @5 :Float32;
    # Domain/category, as an open token (e.g., "medical", "legal").
    domain @6 :Text;
    custom @7 :T.StringMap;
}

struct MemoryLookupResult {
    found @0 :Bool;
    segment @1 :MemorySegment;
    score @2 :Float32;
    alternatives @3 :List(MemorySegment);
}

struct TranslationMemoryStats {
    totalSegments @0 :UInt64;
    hitRate @1 :Float32;
    lastUpdated @2 :T.Timestamp;
    sizeBytes @3 :UInt64;
}

# ── Glossary Enforcement ────────────────────────────────────

struct GlossaryViolation {
    sourceTerm @0 :Text;
    expected @1 :Text;
    actual @2 :Text;
    offset @3 :UInt32;
    # A warning code rather than free-form text, so two backends produce
    # comparable feedback.
    code @4 :UInt32;
}

# ── Quality Estimation ──────────────────────────────────────

struct QualityEstimation {
    score @0 :Float32;
    confidence @1 :Float32;
    # Typed issues, not free-form strings.
    issues @2 :List(T.Warning);
    estimatedPostEditTime @3 :T.Duration;
    custom @4 :Data;
}

# ── Translation Alignment ───────────────────────────────────

struct TextAlignmentResult {
    pairs @0 :List(AlignmentPair);
    sourceLanguage @1 :T.Language;
    targetLanguage @2 :T.Language;
    custom @3 :Data;
}

struct AlignmentPair {
    sourceStart @0 :UInt32;
    sourceEnd @1 :UInt32;
    targetStart @2 :UInt32;
    targetEnd @3 :UInt32;
    score @4 :Float32;
}

# ── Glossary CRUD ─────────────────────────────────────────────────

struct Glossary {
    glossaryId @0 :Text;
    name @1 :Text;
    sourceLang @2 :T.Language;
    targetLang @3 :T.Language;
    entryCount @4 :UInt32;
    createdAt @5 :T.Timestamp;
    updatedAt @6 :T.Timestamp;
}

struct GlossaryEntry {
    sourceTerm @0 :Text;
    targetTerm @1 :Text;
    caseSensitive @2 :Bool;
    locked @3 :Bool;
}

# ── Batch Progress Subscription ───────────────────────────────────

interface BatchProgressSubscription {
    pull @0 () -> (progress :BatchProgress);
    cancel @1 () -> T.VoidResult;
}

struct BatchProgress {
    # The id `translateBatch` issued.
    batchId @0 :Text;
    percentComplete @1 :UInt8;
    segmentsCompleted @2 :UInt64;
    segmentsTotal @3 :UInt64;
    eta @4 :T.Duration;
    currentSegment @5 :Text;
    # Declared: percentComplete is FLOORED when segmentsTotal is 0, so
    # two backends do not disagree about rounding on an empty batch.
    custom @6 :T.StringMap;
}

# ── Alignment Export ─────────────────────────────────────────────

struct AlignmentExport {
    sourceLang @0 :T.Language;
    targetLang @1 :T.Language;
    timedPairs @2 :List(TimedAlignmentPair);
    alignment @3 :TextAlignmentResult;
}

struct TimedAlignmentPair {
    sourceStart @0 :UInt32;
    sourceEnd @1 :UInt32;
    targetStart @2 :UInt32;
    targetEnd @3 :UInt32;
    startMs @4 :UInt32;
    endMs @5 :UInt32;
}

# ── Translation Context ───────────────────────────────────────────

struct TranslationContext {
    # Domain context, as an open token (e.g., "medical", "legal").
    domain @0 :Text;
    # Sub-domain for more specific terminology.
    subDomain @1 :Text;
    # Target audience, as an open token (e.g., "consumer").
    audience @2 :Text;
    # Regional variant, as a BCP-47 suffix of T.Language.code — declared
    # here so the two conventions stop competing.
    regionalVariant @3 :Text;
    customTags @4 :List(Text);
    parameters @5 :T.StringMap;
}

# ── Deduplication Strategy ─────────────────────────────────
# The deduplication key is the TUPLE (sourceText, targetText,
# sourceLang, targetLang). Stated in the schema, not only in the enum's
# doc comment, so a backend that deduplicated on sourceText alone
# cannot silently drop distinct translations.

enum DedupStrategy {
    unspecified @0;   # Sentinel: an unset strategy is not "skip"
    skip @1;
    overwrite @2;
    merge @3;
    fail @4;
    custom @5;
}

# ── Glossary Version ───────────────────────────────────────────────

struct GlossaryVersion {
    versionId @0 :Text;
    version @1 :T.Version;
    createdAt @2 :T.Timestamp;
    author @3 :Text;
    entryCount @4 :UInt32;
    description @5 :Text;
}

# ══════════════════════════════════════════════════════════════════════
# ONE OUTCOME TYPE — the file's error path
#
# The file previously contained zero unions, so a failure and an empty
# input both produced an empty `translatedText` and a consumer could not
# tell them apart. One union carries T.Error beside the existing result
# structs, so every payload struct keeps its field ordinals.
# ══════════════════════════════════════════════════════════════════════

struct TranslationOutcome {
    union {
        translated @0 :TranslationResult;
        detected @1 :LanguageDetectionResult;
        quality @2 :QualityEstimation;
        aligned @3 :TextAlignmentResult;
        exported @4 :AlignmentExport;
        error @5 :T.Error;
        # Opaque escape for an outcome this schema does not name.
        custom @6 :Data;
    }
}

# ══════════════════════════════════════════════════════════════════════
# CONFORMANCE TOKENS — conventions, NOT contract
#
# Today's spellings for the open `tone` and `domain` tokens. Nothing
# requires them; an unrecognized token MUST be ignored rather than
# rejected.
# ══════════════════════════════════════════════════════════════════════

const toneFormal    :Text = "formal";
const toneInformal  :Text = "informal";
const toneTechnical :Text = "technical";
const toneCasual    :Text = "casual";
const toneLiterary  :Text = "literary";
