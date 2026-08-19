@0xa1b2c3d4e5f6002c;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Translation — text translation between languages.
#
# Backend-agnostic: works with any translation engine (Google Translate,
# DeepL, local models, etc.). The schema defines the translation
# contract, not the implementation.
#
# Improvements (audit-7):
#   - Multi-target translation (translate to N languages in one call).
#   - Streaming translation for real-time speech/text feeds.
#   - Formatting preservation across translation.
#   - Tone/register control (formal, informal, technical, casual).
#   - Auto-fallback chains for graceful degradation.
#   - Language detection with per-sentence and mixed-script support.
#   - Translation memory for segment reuse.
#   - Glossary enforcement for domain-specific terminology.
#   - Quality estimation without reference text.
#   - Translation alignment for word-level source-target mapping.
#   - Translation context for domain-specific accuracy.
# ═══════════════════════════════════════════════════════════════════════

interface Translation {
    translate @0 (text :Text, sourceLang :Text, targetLang :Text) -> (result :TranslationResult);
    translateBatch @1 (texts :List(Text), sourceLang :Text, targetLang :Text,
                       pagination :T.Pagination)
                   -> (results :List(TranslationResult), total :UInt64);
    detectLanguage @2 (text :Text) -> (language :T.Language, confidence :Float32);

    listSupportedLanguages @3 (pagination :T.Pagination) -> (languages :List(T.Language), total :UInt64);
    isAvailable @4 (sourceLang :Text, targetLang :Text) -> (available :Bool);
    isOffline @5 (sourceLang :Text, targetLang :Text) -> (offline :Bool);

    getTranslationCache @6 (sourceLang :Text, targetLang :Text) -> (sizeBytes :UInt64);
    clearTranslationCache @7 () -> T.VoidResult;

    # ── Audit-7 additions ────────────────────────────────────

    # Translate to multiple target languages in one call.
    translateMultiTarget @8 (text :Text, sourceLang :Text, targetLangs :List(Text))
                         -> (results :List(TranslationResult));

    # Start a streaming translation session for real-time feeds.
    startStream @9 (sourceLang :Text, targetLang :Text, config :StreamConfig)
                 -> (session :TranslationStream);

    # Detect language with per-sentence and mixed-script support.
    detectLanguageDetailed @10 (text :Text) -> (result :LanguageDetectionResult);

    # Set auto-fallback policy for graceful degradation.
    setFallbackPolicy @11 (sourceLang :Text, targetLang :Text, policy :AutoFallbackPolicy)
                      -> T.VoidResult;

    # Look up a segment in translation memory.
    lookupMemory @12 (sourceText :Text, sourceLang :Text, targetLang :Text)
                 -> (result :MemoryLookupResult);

    # Store a segment in translation memory.
    storeMemory @13 (segment :MemorySegment) -> T.VoidResult;

    # Get translation memory statistics.
    getMemoryStats @14 () -> (stats :TranslationMemoryStats);

    # Estimate translation quality without reference text.
    estimateQuality @15 (sourceText :Text, translatedText :Text, sourceLang :Text, targetLang :Text)
                     -> (result :QualityEstimation);

    # Align source and target texts at word level.
    alignTexts @16 (sourceText :Text, targetText :Text, sourceLang :Text, targetLang :Text)
                -> (result :AlignmentResult);

    # Check terminology against a glossary.
    checkGlossary @17 (text :Text, sourceLang :Text, targetLang :Text, glossaryId :Text)
                   -> (violations :List(GlossaryViolation));

    # ── Audit-9: Streaming subscription ──
    subscribeTranslationStream @18 (sourceLang :Text, targetLang :Text, config :StreamConfig)
        -> (session :TranslationStreamSession);

    # ── Audit-9: Translation memory export/import ──
    exportMemory @19 (pagination :T.Pagination) -> (segments :List(MemorySegment), total :UInt64);
    importMemory @20 (segments :List(MemorySegment)) -> (imported :UInt64);

    # ── Audit-9: Glossary CRUD ──
    createGlossary @21 (name :Text, sourceLang :Text, targetLang :Text, entries :List(GlossaryEntry))
        -> (glossaryId :Text);
    updateGlossary @22 (glossaryId :Text, entries :List(GlossaryEntry)) -> T.VoidResult;
    deleteGlossary @23 (glossaryId :Text) -> T.VoidResult;
    listGlossaries @24 (pagination :T.Pagination) -> (glossaries :List(Glossary), total :UInt64);

    # ── Audit-9: Quality feedback ──
    reportQualityIssue @25 (sourceText :Text, translatedText :Text, sourceLang :Text,
                            targetLang :Text, issues :List(Text)) -> T.VoidResult;

    # ── Audit-9: Batch progress subscription ──
    subscribeBatchProgress @26 (batchId :Text) -> (subscription :BatchProgressSubscription);

    # ── Audit-9: Alignment export ──
    exportAlignment @27 (sourceText :Text, targetText :Text, sourceLang :Text, targetLang :Text)
        -> (result :AlignmentExport);

    # ── Audit-10: Translation context/domain ──
    setTranslationContext @28 (context :TranslationContext) -> T.VoidResult;
    getTranslationContext @29 () -> (context :TranslationContext);

    # ── Audit-10: Translation memory deduplication ──
    importMemoryDedup @30 (segments :List(MemorySegment), strategy :DedupStrategy)
        -> (imported :UInt64, skipped :UInt64, duplicates :UInt64);

    # ── Audit-10: Glossary version history ──
    getGlossaryVersions @31 (glossaryId :Text, pagination :T.Pagination)
        -> (versions :List(GlossaryVersion), total :UInt32);
    rollbackGlossary @32 (glossaryId :Text, versionId :Text) -> T.VoidResult;
}

# ── Translation Result ───────────────────────────────────────

struct TranslationResult {
    translatedText @0 :Text;
    detectedLanguage @1 :T.Language;
    # Confidence score in the range 0.0 (no confidence) to 1.0 (certain).
    # Implementations may use intermediate values for probabilistic models.
    confidence @2 :Float32;
    translations @3 :List(AlternateTranslation);
    # Tone/register used for this translation (audit-7).
    tone @4 :TranslationTone;
}

struct AlternateTranslation {
    text @0 :Text;
    # Model identifier (implementation-specific). No typed model enum
    # exists because model catalogs vary across backends.
    model @1 :Text;
    # Score in the range 0.0 to 1.0. Higher values indicate the
    # model considers this translation more likely correct.
    score @2 :Float32;
}

# ── Streaming Translation (audit-7) ──────────────────────────

struct StreamConfig {
    # Maximum time to wait before sending interim results.
    interimInterval @0 :T.Duration;
    # Whether to provide interim results during translation.
    provideInterim @1 :Bool;
}

struct TranslationStream {
    # Unique stream session identifier.
    sessionId @0 :Text;
}

interface TranslationStreamSession {
    # Push source text for translation.
    pushSource @0 (text :Text, final :Bool) -> T.VoidResult;

    # Pull the next batch of translated results (interim or final).
    pullResults @1 () -> (results :List(StreamTranslationResult), hasMore :Bool);

    # Commit the stream (finalize translation).
    commit @2 () -> T.VoidResult;

    # Cancel the stream.
    cancel @3 () -> T.VoidResult;
}

struct StreamTranslationResult {
    # The translated text (interim or final).
    translatedText @0 :Text;
    # Whether this is a final (committed) result.
    isFinal @1 :Bool;
    # Confidence score.
    confidence @2 :Float32;
    # Source text range this result corresponds to.
    sourceOffset @3 :UInt32;
    sourceLength @4 :UInt32;
}

# ── Language Detection (audit-7) ─────────────────────────────

struct LanguageDetectionResult {
    # Detected languages (may be multiple for mixed-script text).
    languages @0 :List(LanguageDetection);
    # Whether mixed-script text was detected.
    mixedScript @1 :Bool;
    # Whether code-switching was detected (language changes mid-text).
    codeSwitchDetected @2 :Bool;
}

struct LanguageDetection {
    language @0 :T.Language;
    # Confidence score (0.0 to 1.0).
    confidence @1 :Float32;
    # Byte range in the source text where this language was detected.
    byteOffset @2 :UInt32;
    byteLength @3 :UInt32;
}

# ── Auto-Fallback Policy (audit-7) ───────────────────────────

struct AutoFallbackPolicy {
    # Ordered list of fallback language codes to try.
    fallbackChain @0 :List(Text);
    # Maximum number of retry attempts per fallback.
    maxRetries @1 :UInt32;
    # Timeout per attempt before trying the next fallback.
    timeoutPerAttempt @2 :T.Duration;
}

# ── Formatting Preservation (audit-7) ────────────────────────

struct FormattedText {
    # The raw text content.
    text @0 :Text;
    # Inline formatting tags.
    tags @1 :List(TextTag);
}

struct TextTag {
    # Character offset in the text.
    offset @0 :UInt32;
    # Length of the tagged region.
    length @1 :UInt32;
    # Tag type (e.g., "bold", "italic", "link", "placeholder").
    type @2 :Text;
    # Optional tag value (e.g., URL for "link" tags).
    value @3 :Text;
}

# ── Tone / Register (audit-7) ────────────────────────────────

enum TranslationTone {
    formal @0;
    informal @1;
    technical @2;
    casual @3;
    literary @4;
    custom @5;
}

# ── Translation Memory (audit-7) ─────────────────────────────

struct MemorySegment {
    sourceText @0 :Text;
    targetText @1 :Text;
    sourceLang @2 :Text;
    targetLang @3 :Text;
    # When this segment was stored.
    storedAt @4 :T.Timestamp;
    # Confidence in this translation (0.0 to 1.0).
    confidence @5 :Float32;
    # Domain/category (e.g., "medical", "legal", "technical").
    domain @6 :Text;
}

struct MemoryLookupResult {
    # Whether a match was found.
    found @0 :Bool;
    # The matched segment (if found).
    segment @1 :MemorySegment;
    # Match score (0.0 = no match, 1.0 = exact match).
    score @2 :Float32;
    # Similar segments if no exact match.
    alternatives @3 :List(MemorySegment);
}

struct TranslationMemoryStats {
    # Total segments stored.
    totalSegments @0 :UInt64;
    # Cache hit rate (0.0 to 1.0).
    hitRate @1 :Float32;
    # When the memory was last updated.
    lastUpdated @2 :T.Timestamp;
    # Total memory usage in bytes.
    sizeBytes @3 :UInt64;
}

# ── Glossary Enforcement (audit-7) ───────────────────────────

struct GlossaryViolation {
    # Source term that was not translated per glossary.
    sourceTerm @0 :Text;
    # What the glossary says it should be.
    expected @1 :Text;
    # What the translation actually produced.
    actual @2 :Text;
    # Character offset in the translated text.
    offset @3 :UInt32;
}

# ── Quality Estimation (audit-7) ─────────────────────────────

struct QualityEstimation {
    # Overall quality score (0.0 = poor, 1.0 = excellent).
    score @0 :Float32;
    # Confidence in the quality estimate.
    confidence @1 :Float32;
    # Specific issues found.
    issues @2 :List(Text);
    # Estimated post-editing time.
    estimatedPostEditTime @3 :T.Duration;
}

# ── Translation Alignment (audit-7) ──────────────────────────

struct AlignmentResult {
    # Word-level alignment pairs.
    pairs @0 :List(AlignmentPair);
    # Source language.
    sourceLanguage @1 :Text;
    # Target language.
    targetLanguage @2 :Text;
}

struct AlignmentPair {
    # Source text range.
    sourceStart @0 :UInt32;
    sourceEnd @1 :UInt32;
    # Target text range.
    targetStart @2 :UInt32;
    targetEnd @3 :UInt32;
    # Alignment confidence score (0.0 to 1.0).
    score @4 :Float32;
}

# ── Glossary CRUD (audit-9) ─────────────────────────────────────────────────

struct Glossary {
    glossaryId @0 :Text;
    name @1 :Text;
    sourceLang @2 :Text;
    targetLang @3 :Text;
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

# ── Batch Progress Subscription (audit-9) ───────────────────────────────────

interface BatchProgressSubscription {
    pull @0 () -> (progress :BatchProgress);
    cancel @1 () -> T.VoidResult;
}

struct BatchProgress {
    batchId @0 :Text;
    # Overall progress percentage (0-100).
    percentComplete @1 :UInt8;
    # Number of segments completed.
    segmentsCompleted @2 :UInt64;
    # Total segments.
    segmentsTotal @3 :UInt64;
    # Estimated time remaining.
    eta @4 :T.Duration;
    # Current segment being processed.
    currentSegment @5 :Text;
}

# ── Alignment Export (audit-9) ─────────────────────────────────────────────

struct AlignmentExport {
    # Source language.
    sourceLang @0 :Text;
    # Target language.
    targetLang @1 :Text;
    # Word-level pairs with timing info for subtitle sync.
    timedPairs @2 :List(TimedAlignmentPair);
    # Standard alignment result.
    alignment @3 :AlignmentResult;
}

struct TimedAlignmentPair {
    sourceStart @0 :UInt32;
    sourceEnd @1 :UInt32;
    targetStart @2 :UInt32;
    targetEnd @3 :UInt32;
    # Start time in milliseconds for subtitle sync.
    startMs @4 :UInt32;
    # End time in milliseconds.
    endMs @5 :UInt32;
}

# ── Translation Context (audit-10) ────────────────────────────────────

struct TranslationContext {
    # Domain context (e.g., "medical", "legal", "technical", "general").
    domain @0 :Text;
    # Sub-domain for more specific terminology.
    subDomain @1 :Text;
    # Target audience (e.g., "consumer", "professional", "academic").
    audience @2 :Text;
    # Regional variant (e.g., "en-US", "en-GB", "pt-BR").
    regionalVariant @3 :Text;
    # Custom context tags for backend-specific terminology.
    customTags @4 :List(Text);
}

# ── Deduplication Strategy (audit-10) ─────────────────────────────────

enum DedupStrategy {
    # Skip segments that already exist (same sourceText + targetText + sourceLang + targetLang).
    skip @0;
    # Overwrite existing segments with new data.
    overwrite @1;
    # Merge: keep existing, add new only if not present.
    merge @2;
    # Fail if any duplicates are found.
    fail @3;
    custom @4;
}

# ── Glossary Version (audit-10) ───────────────────────────────────────

struct GlossaryVersion {
    # Version identifier.
    versionId @0 :Text;
    # Semantic version after this change.
    version @1 :T.Version;
    # When this version was created.
    createdAt @2 :T.Timestamp;
    # Author or service that made the change.
    author @3 :Text;
    # Number of entries in this version.
    entryCount @4 :UInt32;
    # Change description.
    description @5 :Text;
}
