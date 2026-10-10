# Audit — dns.capnp (670 lines)

## Verdict
**FIX (targeted).** The contract is well-shaped — typed records, privacy preference, subscriptions with cancel, pagination on the admin lists. Two real defects: the primary call `resolve @0` has **no error representation at all**, and the file carries a deprecated local `IpAddress` plus three reverse-resolve methods (@1, @6, @9) for one job. The header's audit claims about durations are not reflected in the schema.

## Wire-breakers
None (compiles clean). `ResolveResult` name collision: `dns.capnp:158` (plain struct) vs `endpoint.capnp:763` (success/error union) — a consumer holding a DNS result cannot pass it to endpoint code without conversion, and the two shapes read identically in prose.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R7 | `dns.capnp:524`, `:527` | `resolve @0` and `srvLookup @5` return `ResolveResult`, a struct with **no error variant**; SERVFAIL/timeout are unrepresentable | A resolver on a degraded link fails; the consumer sees empty `records` + empty `canonicalName`, indistinguishable from NXDOMAIN-without-`negativeCache`. Every backend forks: some encode the error as a pseudo-record, some add a field at a new ordinal — two client behaviors for the same failure |
| R7 | `dns.capnp:530`, `:533`, `:544` | Three reverse-resolve methods: `@1 (address :Data)`, `@6 (address :IpAddress)` (local), `@9 (address :T.IpAddress)` | The file documents the migration (:605-615) but keeps all three; the "preferred" one is the third-written. The local `IpAddress` (:616-625) is a fourth address type in the batch after `T.IpAddress`, `T.IpAddressV4/V6` |
| R7 | `dns.capnp:117-127`, `:170-175` | Header claims (:23-25) "SoaRecord refresh/retry/expire → T.Duration" and "NegativeCacheInfo.ttl → T.Duration"; the schema still declares them `UInt32` (:122-126, :174), and `ResolveResult.ttl @3` / `DnsRecord.ttl @2` are `UInt32` seconds elsewhere in the file while `ResolveHints.timeout` is `T.Duration` | Two time-unit conventions in one struct family. A consumer computing cache expiry must know which fields are seconds and which are `T.Duration` nanoseconds — an easy 10^9 error that compiles |
| R1 | `dns.capnp:59-76` | `DnsRecordType` — closed by RFCs today, but `other @13`/`custom @14` carry no typed data, and `a @0` is the default sentinel | 2046 failure: the HTTPS/SVCB generation showed record types do turn over; typed consumers' `switch(typedData)` breaks on a new type. (Mostly defensible — flagged for the sentinel, not the set) |
| R1 | `dns.capnp:595-603` | `DnsPrivacy` = plain/dot/doh/odoh | Oblivious-DNS is a 2020s spelling; a successor privacy technology has no value. `custom @5` exists but carries no configuration |
| R1 | `dns.capnp:244-253` | `BlocklistCategory` freezes a policy taxonomy (malware/phishing/advertising/tracking/gambling/adult/socialMedia) | Taxonomy is editorial, not mathematical; "socialMedia" as a blocking category is a 2024 cultural fact |
| R6 | `dns.capnp:508`, `:387`, `:284`, `:299`, `:429` | Resolver addresses are bare `Text` (`DnsServerConfig.address`, `ResolverHealth.address`, `DnsAppRouting.resolver`, `DnsResolverPin.resolver`, `DnsFailoverConfig.primaryResolver`) while the same file uses `T.IpAddress` at :227 | Inconsistent address representation inside one file; consumer code must parse Text defensively for some fields and not others |
| R6 | `dns.capnp:112` | `SrvRecord.port @2 :UInt16` | `T.Port` exists (`types.capnp:759`) precisely because "dns.capnp SrvRecord.port and network.capnp DnsServer.port are raw UInt16" — the promotion was documented, not done |

Validator counts: E7 ×24, E8 ×9 (`DnsRecordType.@0 = a` means an absent type silently reads as "A"), E6 ×1 (`RecordData` union has no unknown/custom — though `opaque @9` is a de-facto escape, see actions).

## Duplicates & overlaps
- `IpAddress` local struct vs `types.capnp:745` `T.IpAddress` (documented deprecation, still present and still returned by `reverseResolveTyped @6`).
- `ResolveResult` vs `endpoint.capnp:763` (different shapes, same name).
- `DnsServerConfig` (:507) vs `network.capnp:873` `DnsServer` — two DNS-server descriptor types in the batch, different fields (network's has `dohPath`/`auth`; dns's has `dohHostname`/`trusted`).

## Gaps & holes
- **No security level attached to transport choice.** `DnsTransport` (:212) selects UDP/TCP/TLS/HTTPS/QUIC, and `DnsConfig.dohTemplate :Text` (:483) is a URL string — but nothing states whether resolution is *required* to be authenticated/encrypted, so two backends satisfy the same config with different security.
- `resolveBatch @35` (:592) takes an unbounded request list and returns an unbounded result list in one message.
- `getResolverHealth @28` (:579) unbounded.
- No normative statement of where a `DnsService` reference comes from or how it travels (batch transport gap).

## Zero-cost / eco
- No bulk payloads — records are small by nature. No polling pattern: subscriptions are pull+cancel. No findings.

## UX & implementer guidance
- `flushCache @2 (name :Text)` (:535) — flushing by name has no wildcard/empty-for-all semantics documented; an implementer must guess whether empty string means "flush everything".
- `cacheStatus @3` returns `ttl :UInt32` while `DnsCacheEntry.ttlRemaining :T.Duration` (:316) — same concept, two units, adjacent semantics.
- `DnsEvent.custom @5 :Data` exists (:641) — good; but `RecordData`'s missing variant (E6) is the more important one because consumers exhaustively switch it.

## Recommended actions
1. **Add an error representation to `ResolveResult`**: `union { result @0 :ResolveData; error @1 :T.Error; }` (new shape at the existing ordinals is fine pre-release; alternatively add `error @6 :T.Error` to the struct). Gain: SERVFAIL/timeout become honest and retryable-settable instead of pretending to be an empty answer. Cost: every consumer touches the result type once — the cheapest possible moment is before first release.
2. **Finish the reverse-resolve consolidation**: make `@9` the only live path, mark `@1`/`@6` deprecated with comments pointing at `@9`, and delete the local `IpAddress` after the deprecation cycle (or now, pre-release). Gain: one address type, one method. Cost: two retired ordinals — free now.
3. **Align the header with the schema**: either convert SoaRecord/ttl fields to `T.Duration` as claimed, or fix the comments to say `UInt32 seconds` and state the DNS-RFC-seconds convention once, at the top. Gain: removes a 10^9-error trap. Cost: either a type change (wire break, acceptable now) or comment edits (free).
4. **Rename `RecordData.opaque @9` → `custom`** so the E6 machinery and the repo's naming convention agree; add the typed data for a *future* record as `custom :Data`. Gain: forward-compat naming consistency at zero cost. Cost: one variant rename.
5. **Use `T.IpAddress`/`T.Port` uniformly** for all resolver/server addresses and ports (:508, :112, :387, :284, :299, :429, :509). Gain: one parser, one comparison path. Cost: mechanical field-type changes.
