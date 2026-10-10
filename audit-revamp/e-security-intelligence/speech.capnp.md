# Audit — speech.capnp (518 lines)

## Verdict
**FIX (targeted).** The file's zero-cost migration was done properly and is genuine: `SpeakResult.audio`, `MultiSpeakerResult.audio`, `SpeechTranslationResult.sourceAudio/translatedAudio`, `VoiceCloneRequest.sourceAudio` are all `T.DataHandle` (`:153`, `:440`, `:331-332`, `:295`), which is the single hardest thing to retrofit and this schema got right. What it lacks is an error model and open vocabularies. The file contains **zero unions** — not one method in it can report a failure — and two of its enums (`AudioEncoding`, the two emotion enums) freeze today's technology. The structure is sound; the defects are enumerable and mechanical.

## Wire-breakers
None. Method ordinals @0–@33 are unique (`:31-101`), the five subscription interfaces each use @0/@1, and every `T.*` reference resolves. One dead import: `using Translation = import "translation.capnp";` (`:4`) is never referenced anywhere in the file (R8 — dead import).

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R7 | whole file — `listen @0`, `speak @2`, `speakSsml @3`, `transcribeStructured @12`, `transcribeDiarized @13`, `alignText @21`, `detectEmotion @26`, `getQualityMetrics @30`, `listVoices @7`, `getDefaultVoice @8`, `cloneVoice @14`, `negotiateCodec @29` (`:31-101`) | No union anywhere in the file; ~12 methods that can fail return bare structs | "Did STT fail, or did it hear silence?" is unanswerable from the wire. `ListenResult.text` is empty on both. Every consumer must invent a failure heuristic and every backend must pick a convention for signalling one (empty transcript? `isFinal = true` with empty text?) — the classic fork |
| R1 | `speech.capnp:196-206` `AudioEncoding` (pcm/opus/aac/mp3/flac/vorbis/alaw/mulaw/custom) | Closed codec vocabulary in a required position (`AudioFormat.encoding @0`, `:189`) | A 2046 neural or LC3-family codec has no ordinal; `custom @8` carries no identification, so a stream cannot even name what it is. The file already imports `T` and `T.MimeType` exists — the open value costs nothing. Interop is *not* lost: `negotiateCodec @29` (`:93`) already negotiates, and would negotiate spellings |
| R1 | `speech.capnp:254-268` `EmotionalStyle` vs `:413-424` `SpeechEmotion` | Two overlapping emotion vocabularies in one file with divergent value sets (`EmotionalStyle` has whisper/shout/dramatic; `SpeechEmotion` has calm/excited and lacks whisper/shout) | `SpeakOptions.emotionalStyle @4 :EmotionalStyle` (`:147`) requests an emotion; `EmotionResult.emotion @0 :SpeechEmotion` (`:404`) reports one. A consumer cannot map request to response, and 2046's "contempt"/"sarcasm"/"boredom" lands in two different `custom` slots that mean nothing |
| R3 | `speech.capnp:30-102` (whole interface) | No capability gating at all — no `using import "capability.capnp"` | `cloneVoice @14` (`:56`) creates a voice that can impersonate a real person, and `setTtsFormat @17` / `addPronunciationRule @31` mutate global state. Any holder of the `Speech` reference can clone any voice from any audio. Compare the gated accessors of `ai.capnp:578-584` |
| R7 (soft) | `speech.capnp:36-38` `stopSpeaking @4` / `pauseSpeaking @5` / `resumeSpeaking @6`; `:76` `stopWakeWordDetection @23` | Global, targetless control methods | `speakStream @27` (`:86-87`) and `startWakeWordDetection @22` (`:75`) return stream/subscription handles, but the stop methods take no argument and cannot address them. In a multi-stream system the implementer must invent session identity out of band, and a consumer cannot stop the right stream |
| R1 (soft) | `speech.capnp:35` `speakSsml @3 (ssml :Text)` | SSML is a frozen external markup in a required position | A 2046 TTS backend that speaks no SSML must reject a method that exists only to serve a 2004 W3C spec |

## Duplicates & overlaps
- `EmotionalStyle` vs `SpeechEmotion` (same file) — see above.
- `SpeechTranslationRequest/Result` (`:316-334`) overlaps `translation.capnp`'s core contract; the `translatedText` field is the overlap and is produced by re-implementing translation inside speech.
- `AlignmentResult` (`:351-358`) and `alignText @21` (`:72`) collide **by name** with `translation.capnp:309-316` `AlignmentResult` and `alignTexts @16` (`:72`), with different fields (`words`/`confidence`/`duration` vs `pairs`/`sourceLanguage`/`targetLanguage`). Two schemas, one name, two shapes.
- `getSupportedTranslationPairs @19` (`:65`) + `LanguagePair` (`:336-339`) live in speech while `translation.capnp` owns language selection and has only `isAvailable @4` (`:34`) for pairs.

## Gaps & holes
- No failure path (above). This is the file's dominant gap.
- No contract for what happens to an in-flight `listenStream`/`speakStream` when the device changes (hotplug, audio-focus loss). `AudioEnhancement` and `AudioFormat` are declared, but nothing says a stream survives or must restart — every backend decides. Demonstrated cost: a consumer that loses its microphone mid-transcription has no way to learn why the stream went quiet.
- **Dead import** (`:4`) — `translation.capnp` is imported and never used, which will mislead the next reader into thinking speech reconciles its language handling with translation.capnp. It does not.

## Zero-cost / eco
All payloads are `T.DataHandle` — genuine pass, recorded as praise. Two residual costs: `AudioStream.pull @0` (`:105`) and `SpeechStreamResult.pull @0` (`:516`) have no `maxBytes` backpressure (compare `ai.capnp:277`), so a producer may push larger chunks than a consumer can hold; and `StructuredTranscript.words @1 :List(WordTiming)` (`:228`) plus `AlignmentResult.words @0` (`:353`) are unbounded word lists — bounded by the audio length in practice, but a 6-hour meeting produces a very large inline list.

## UX & implementer guidance
- `ListenResult.language @3 :T.Language` (`:125`) is typed while every method parameter takes a language as `T.Language` too — consistent, and better than translation.capnp (see that file).
- `EnrollStep` (`:374-384`) emits ordinals 0,1,5,6,7,8,2,3,4 out of order. Harmless on the wire, but it signals hand-editing and invites an accidental reuse.
- `AuthSubscription.pull @0 () -> (result :AuthResult, attempt :AuthAttempt)` (`:356`) names a field `result` that shadows its own type; `AuthResult` (`:217-226`) is a bare enum with no payload, so `failed` and `error` are indistinguishable to the consumer.
- The header (`:9-20`) documents its own improvements accurately; the two claims it makes about forward compatibility ("VoiceGender has custom variant") are true only formally — `custom` exists but carries no identity, which is the defect the R1 rows describe.

## Recommended actions
1. **Wrap every fallible result in a union carrying `T.Error`** (`ListenResult`, `SpeakResult`, `StructuredTranscript`, `AlignmentResult`, `EmotionResult`, `QualityMetrics`, `VoiceCloneResult`, `CodecNegotiationResult`). Gain: failures stop being encoded as empty structs; this is the file's single largest defect and the fix is mechanical. Cost: ~8 wrapper types; no existing ordinal moves (the union is new, the struct moves inside it).
2. **Replace `AudioEncoding` with `T.MimeType`.** Gain: codecs become open, so 2046 codecs are expressible and `negotiateCodec` negotiates real spellings instead of a closed list; cost: consumers switch on `type`/`subtype` strings, and a one-time conformance-token list (`audio/pcm`, `audio/opus`) should be published as `const`s, exactly as `ai.capnp:600-606` does.
3. **Collapse the two emotion enums into one open `Text` token** (or one `T.StringMap` style spec). Gain: request and response speak the same vocabulary; cost: consumers lose compile-time checking on a vocabulary that was never closed anyway.
4. **Give the stream controls a target** (`stopSpeaking(stream)`, `stopWakeWordDetection(subscription)`). Gain: multi-stream operation becomes expressible; cost: signature change on four methods, permitted pre-release.
5. **Add `maxBytes` to `AudioStream.pull` and `SpeechStreamResult.pull`.** Gain: matches `ai.capnp:277`; cost: one parameter.
6. **Gate `cloneVoice` behind a capability accessor.** Gain: voice cloning stops being available to every reference holder; cost: one accessor method.
7. **Remove the dead `using Translation` import (`:4`).** Gain: stops implying a reconciliation with translation.capnp that does not exist; cost: one line. Note this is only safe *after* the alignment-type collision in Duplicates is resolved.
