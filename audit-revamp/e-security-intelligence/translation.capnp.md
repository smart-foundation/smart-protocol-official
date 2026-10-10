# Audit — translation.capnp (437 lines)

## Verdict
**FIX (targeted).** Feature coverage is good and the file is honest about its open values in places (`AlternateTranslation.model @1 :Text` at `:136` is explicitly open). But it has three defects that make parts of its surface unusable rather than merely imperfect: the streaming session returned by `startStream` is not an interface, the batch-progress subscription is keyed on an identifier no method produces, and the language-tag format is never declared while three conventions coexist. Plus zero unions — no method in this file can report a failure either.

## Wire-breakers
No ordinal collisions (`Translation` @0–@32 unique; `TranslationStreamSession` @0–@3; `BatchProgressSubscription` @0–@1) and all `T.*` references resolve. Two *reachability* breaks, which are worse than compile breaks:
- `translation.capnp:151-154` `TranslationStream { sessionId @0 :Text }` is a **struct, not an interface**, returned by `startStream @9` (`:47-48`). The pullable interface, `TranslationStreamSession`, is reachable only through a different method (`subscribeTranslationStream @18`, `:80-81`). So the object `startStream` hands back has no protocol meaning, nothing can pull from it, and no method declares who generates its `sessionId`.
- `translation.capnp:99` `subscribeBatchProgress @26 (batchId :Text)` — `translateBatch @1` (`:28-30`) returns `(results, total)`, not a batch id. The subscription's key comes from a namespace no method writes.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R8 | `translation.capnp:47-48` + `:151-154` | `startStream` returns a non-interface struct; the usable stream type is returned by a different method | An implementer cannot tell whether `startStream` should also open a session (and therefore whether its `sessionId` is caller-chosen or server-assigned). Two backends will answer differently, and any consumer of `startStream` gets a dead value. Compare `ai.capnp:316` `openStream @1 -> (stream :ArtifactStream)` — the correct shape |
| R8 | `translation.capnp:99` | `subscribeBatchProgress` keyed on a `batchId` no method produces | Either the method is unreachable, or every implementer invents a batch-id source. Demonstrated fork risk: two backends' `batchId`s are unrelated namespaces |
| R1/R4 | `translation.capnp:27, 28-30, 43, 58, 88` — every method takes `sourceLang :Text, targetLang :Text` | The language-tag format is never declared, and three conventions coexist: `T.Language.code` is documented ISO 639-1 (`types.capnp:679`), `TranslationContext.regionalVariant`'s example is `"en-US"` (`:403`, BCP-47), and `AutoFallbackPolicy.fallbackChain :List(Text)` (`:206`) is unspecified | A 2046 implementer cannot know whether `"en"` means English, an ISO 639-1 code, or a BCP-47 prefix. Language negotiation — the file's core purpose — is implemented by guesswork per backend. Every consumer must normalise three spellings into one |
| R7 | whole file — `translate @0`, `translateMultiTarget @8`, `detectLanguage @2`, `detectLanguageDetailed @10`, `startStream`, `estimateQuality @15`, `checkGlossary @17`, `importMemory @20`, `exportAlignment @27` (`:27-103`) | No union in the file; all results are bare structs | `TranslationResult.translatedText` is empty both when translation fails and when the input was empty. A consumer cannot distinguish; every backend invents a failure convention |
| R7 | `translation.capnp:28-30` `translateBatch (texts :List(Text), …, pagination :T.Pagination)` | Pagination is applied to the *caller's own input list* | The caller must chunk its own data (so the pagination buys nothing for wire size) and the returned `total` (`:30`) now means something different from every other paginated method in the tree. Two pagination models in one file (`:33`, `:84`, `:92` use the standard one) |
| R7 | `translation.capnp:85` `importMemory @20 (segments :List(MemorySegment))` | Unbounded input list; translation memories are millions of segments | Importing a real TM exceeds the message limit. There is no handle-based or chunked ingest, so the caller must reinvent batching outside the protocol |

## Duplicates & overlaps
- `AlignmentResult` (`:309-316`) and `alignTexts @16` (`:72`) collide by name with `speech.capnp:351-358` / `speak.capnp:72` `alignText @21`, with different fields.
- `translate`/`LanguagePair` (`:336-339`) overlap `speech.capnp`'s real-time speech-translation pipeline (`:316-334`).
- `ConflictResolution`-style sync vocabulary is duplicated in `vcard.capnp:667-672` and `calendar.capnp:423-428` (three identical enums across the batch) — this file's `getSyncToken` peers are the other two.
- `getTranslationCache @6` / `clearTranslationCache @7` (`:37-38`) and `getMemoryStats @14` (`:65`) expose cache accounting that no consumer can act on; they are observability, not contract.

## Gaps & holes
- No declared language-tag format (above). This is the gap that most constrains the file.
- `importMemoryDedup @30` (`:110-111`) takes a `DedupStrategy` but the deduplication key is declared only in the enum's comment (`:411`: "same sourceText + targetText + sourceLang + targetLang"). A backend that dedups on `sourceText` alone will silently drop distinct translations — the contract should state the key, not the enum's doc comment.
- `reportQualityIssue @25` (`:95-96`) accepts `issues :List(Text)` — free-form quality issue strings with no vocabulary, so no two backends produce comparable feedback.

## Zero-cost / eco
`translateMultiTarget @8` (`:43-44`) takes an unbounded `List(Text)` of target languages; `translateBatch` takes an unbounded text list; `exportMemory @19` (`:84`) is paginated but each `MemorySegment` holds two `Text` fields, so a large page is a large copy. The dominant eco issue is the unbounded input lists above. No `T.DataHandle` payload exists because there is no payload worth one — documents arrive as inline `Text` (`:27`), which means a 10 MB translated document is copied into the message. `T.DataHandle` is available and unused.

## UX & implementer guidance
- `StreamConfig.interimInterval @0 :T.Duration` (`:144-146`) is described as "maximum time to wait before sending interim results", with no declared lower bound or behaviour when `provideInterim @1` is false — a backend may stream anyway.
- `BatchProgress.percentComplete @1 :UInt8` (`:358`) is documented as 0–100 while `segmentsCompleted/segmentsTotal` carry the same information as a fraction; two backends will disagree on whether `percentComplete` is rounded or floored when `segmentsTotal` is 0.
- `Glossary.glossaryId @0 :Text` (`:332`) and `createGlossary @21 -> (glossaryId :Text)` (`:88-89`) are opaque-Text identifiers, which is acceptable, but they are the *only* unstructured IDs in a tree that types everything else; `rollbackGlossary @32` and `getGlossaryVersions @31` both take them.
- The file's header (`:12-23`) claims "Auto-fallback chains for graceful degradation" as an improvement; `setFallbackPolicy @11` does that, but `translate @0` never mentions the fallback applies, so a caller cannot learn that a degraded translation occurred except by comparing languages.

## Recommended actions
1. **Make `startStream` return `TranslationStreamSession` (or an equivalent interface), and delete `TranslationStream`.** Gain: the stream becomes usable and the session-id namespace becomes owned; cost: one method signature change, permitted pre-release.
2. **Either return a `batchId` from `translateBatch` or drop `subscribeBatchProgress`.** Gain: removes an unreachable contract; cost: a new result field (cheap) if kept.
3. **Declare the language-tag format once, as `T.Language`, and use it on every method parameter.** Gain: the file's core parameter stops being three conventions at once; cost: a signature change on ~25 methods — but all are additive-safe pre-release, and `T.Language` already exists (`types.capnp:678-682`).
4. **Wrap fallible results in `T.Error` unions.** Gain: failures stop being encoded as empty text; cost: ~6 wrapper types.
5. **Accept documents as `T.DataHandle` rather than inline `Text`.** Gain: large documents stop being copied into the message; cost: callers must materialise a handle for small strings, which is the same pattern `ai.capnp:117-120` already establishes.
6. **Chunk or handle-ify `importMemory`.** Gain: real translation memories become importable; cost: a streaming counterpart method.
7. **State the deduplication key in the schema, not the enum comment.** Gain: two backends stop deduping differently; cost: one comment.
