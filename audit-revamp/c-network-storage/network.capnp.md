# Audit — network.capnp (1028 lines)

## Verdict
**FIX (targeted) — the heaviest targeted fix in the batch.** The interface shape is right: per-interface state, pull+cancel subscriptions, pagination, `T.VoidResult`. The type layer is the problem: 18 enums, most of which name today's radio technology (a 2046 implementer has no value to give), and five structs (`MeshNetwork`, `LoraNetwork`, `BleMeshNetwork`, `PacketRadioNetwork`, `MultiLinkConfig` at :289, :320, :335, :350, :363) that no method in the entire repo returns. Also the NIC provider path — the highest-volume data in the whole protocol, network frames — has no buffer reference in its wire format, so zero-copy is impossible by construction.

## Wire-breakers
None (compiles clean: no duplicate ordinals, no undefined `T.*`). Name collisions with other schemas that force qualification when both are imported: `NetworkType` (`network.capnp:257` vs `telephony.capnp:97` vs `shell.capnp:432` — three different meanings), `AddressFamily` (:866 vs `endpoint.capnp:788`), `ConnectionStatus` (:387 vs `display.capnp:881`), `BluetoothDevice` (:730 vs `bluetooth.capnp:61` vs `shell.capnp:456`), `CapRef` (:253 vs `device.capnp:141`), `DhcpLease` (:850 vs `boot.capnp:507`), `QualityMetrics` (:421 vs `speech.capnp:479`).

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R1 | `network.capnp:257-285` | `NetworkType` enumerates 19 link technologies incl. `lora`, `sigfox`, `nbIoT`, `bleMesh`, `packetRadio`, `multiLink` | A new physical layer has no value; `custom @19` is a valueless enum variant (can't carry data). Every consumer's `switch(type)` must handle an unroutable future |
| R1 | `network.capnp:697-710` | `WifiSecurity` freezes wep/wpa/wpa2/wpa3/owe/enhancedOpen/sae/wpa3Enterprise/eapPwd/eapTtls | 2046 failure: an enterprise auth method invented after 2026 has no value; `wep @1` is already-insecure yet eternal. This is exactly the "today's list ages into a lie" argument at `ai.capnp:16-21` |
| R1 | `network.capnp:765-774` | `VpnKind` = wireguard/openvpn/ikev2/ipsec/l2tp/pptp — six product names, two of them already deprecated | A 2046 VPN protocol cannot be named except via `custom`; a consumer's VPN UI cannot offer it |
| R1 | `network.capnp:909-917` | `TransportProtocol` = tcp/udp/icmp/sctp/quic, consumed by `FirewallRule.protocol @3` and `QosMatch.protocol @3` | A future transport cannot appear in a firewall rule or QoS match — security policy silently excludes it |
| R1 | `network.capnp:826-832` | `WifiBand` = band24GHz/band5GHz/band6GHz | Spectrum allocation is political, not mathematical; 6 GHz is a 2020 regulator decision, not a constant |
| R1 | `network.capnp:310-316`, `:374-381` | `MeshRoutingAlgorithm`, `BondingStrategy` — routing/scheduling algorithm names | TIMELESSNESS.md:84 rejects algorithm hints ("Rejected — kernel internal"); routing is backend-internal |
| R4 | `network.capnp:224`, `:152`, `:716` | `hwAddress`, `setHotspotClientFilter(macAddresses)`, `bssid` all typed `T.BluetoothAddress` | A WiFi AP MAC is not a Bluetooth address; the type name asserts semantics that don't hold. Implementers must guess whether BT address semantics (privacy/random) apply to WiFi |
| R5 | `network.capnp:242`, `:991` | `NetworkInterface.driver @12 :Text` ("Vendor/Driver of the underlying NIC"); `NicCapabilities.permanentId @4` | A distributed-FS, browser-runtime or capability-fabric backend has no NIC driver name and must fabricate one consumers then depend on |
| R8 | `network.capnp:289`, `:320`, `:335`, `:350`, `:363` | `MeshNetwork`, `LoraNetwork`, `BleMeshNetwork`, `PacketRadioNetwork`, `MultiLinkConfig` (+ `MeshRoutingAlgorithm`, `BondingStrategy`, `MeshRoute`) are returned by no method in the repo | False contract surface: a consumer reading the schema believes mesh/LoRa/packet-radio state is queryable and builds against a struct no service will ever emit |
| R8 | `network.capnp:964-979` | `NicProvider` is returned by no method anywhere in the repo | Per the repo's own E4 rationale (`scripts/validate.py:172-179`) a driver provider may be host-injected — but nothing in the file says so, so reachability is undocumented guesswork |
| R2 | `network.capnp:992-1010` | `NicFrameDesc` carries `bufferSlot`/`length`/`offset` but **no buffer reference**; the comment at :1000-1002 defers to `buffer.capnp`, which the API never names | The frame path is the protocol's highest-volume data path and its zero-copy mechanism has no wire representation. Each backend invents a slot→memory mapping outside the contract — fork risk on the one path where copies are most expensive |
| R2 | `network.capnp:500` | `DtnBundle.payload @3 :Data` inline | A store-and-forward bundle is by definition large; inline Data copies the whole payload through the message. Should be `T.DataHandle` |
| R7 | `network.capnp:128-129` | `createSlice`/`removeSlice` use bare `Text` for slice ids, and `NetworkInterface.sliceId @16 :Text` repeats the pattern | Two string ID namespaces invented for the same entity while typed IDs are the repo norm (`T.SubnetId` exists at `types.capnp:1512`) |
| UX | `network.capnp:102`, `:38` | `getCounters(interfaceId, since :T.Duration)` | "since a Duration" is ambiguous (window ending now? from now-backwards?). `window :T.Duration` or `since :T.Timestamp` would say what is meant |
| UX | `network.capnp:55` | `wifiConnect(ssid :Text, password :Text)` | A network secret crosses the wire in cleartext in the message. The capability/secret model exists (`T.SecretKeyId`, `types.capnp:1658`); passing the secret as payload bypasses it |

Validator counts for this file: E7 (no open extension point) ×39, E8 (enum `@0` not a neutral sentinel) ×16, E6 ×0.

## Duplicates & overlaps
- Time synchronization is declared three times in this batch with three shapes: `network.capnp:146` `getTimeSync` (tuple result), `clock.capnp:47-58` `ClockSyncInfo`, `time.capnp:239-261` `ClockSource`/`ClockSourceType`. A consumer reading sync status must know which service it holds.
- `TransportProtocol` (:909) vs `socket.capnp:265` `SocketKind` vs `endpoint.capnp:854` `TransportPreference` — three overlapping transport vocabularies.
- `BluetoothDevice` triplicated (see wire-breakers); the file itself notes bluetooth was superseded (`:60`) — the structs remain wired into the enum and scan method.

## Gaps & holes
- No transport profile statement: a consumer holding a `Network` reference cannot learn how the reference travels (channel security, framing, message-size limits). This is the batch-level gap — see `BATCH-SUMMARY.md`.
- `traceroute @59` (:139) returns an unbounded hop list (bounded only by TTL in practice); no pagination field exists for it.
- No resume/checkpoint contract for `sendDtnBundle` — the highest-latency send in the protocol has no way to report custody acceptance vs. loss.

## Zero-cost / eco
- `NicFrameDesc` (above): the frame path forces per-frame copies or out-of-band memory agreement; the comment admits the buffer relationship but the schema can't express it.
- `DtnBundle.payload` inline `Data` (above).
- `getTopology @48` returns two lists plus a total in one result — bounded by pagination, fine.
- No busy-poll pattern in this file (subscriptions are pull+cancel, the canonical shape).

## UX & implementer guidance
- `renameInterface @45 (:113)` lets a consumer rename an interface *id* — renaming is a backend/udev concern, not a consumer operation; the method invites consumers to treat ids as mutable labels.
- `NetworkConfig.remember @5`/`autoConnect @6` default `true` (:692-694) — stored-credential behavior implied by struct defaults; fine, but worth documenting that "remember" stores a password backend-side.
- The header comment block (:8-37) lists 30+ claimed features; 5 of the listed structs are unreachable (see R8), so the overclaim is inside the same file.

## Recommended actions
1. **Delete `MeshNetwork`, `LoraNetwork`, `BleMeshNetwork`, `PacketRadioNetwork`, `MultiLinkConfig` and their private enums** (:289-381). Gain: removes ~90 lines of false contract surface and the R8 flag; implementers stop building to types no service emits. Cost: zero — nothing in the repo references them.
2. **Give `NicFrameDesc` a buffer reference** (add `buffer @4 :T.BufferId` or change `bufferSlot` to a `T.DataHandle`-style reference; :999-1010). Gain: the frame path becomes expressible zero-copy — the single largest copy cost in the protocol. Cost: one field on a struct; pre-release, free.
3. **Open the technology enums**: `NetworkType`, `WifiSecurity`, `VpnKind`, `TransportProtocol`, `WifiBand`, `SaMode`, `NanRole` → open `Text` tokens with unknown-tolerance (the `ai.capnp:122-131` `CapabilityDescriptor` pattern), keeping only math-closed enums. Gain: 2046 values are expressible without a schema edit; today's list stops being a commitment. Cost: consumers lose exhaustive matching — but `custom` already prevents exhaustive matching, so the cost is honesty about what they already had.
4. **Stop typing WiFi/Ethernet MACs as `T.BluetoothAddress`** (batched with a-foundation/b-devices: rename to `T.MacAddress`, alias the old name). Gain: honest naming across network/bluetooth/socket/endpoint. Cost: one types.capnp rename with a repo-wide ripple — cheap now, expensive after release.
5. **Move the WiFi password off the wire**: `wifiConnect` takes a `T.SecretKeyId`/capability reference instead of `password :Text`. Gain: secrets stop crossing the wire in cleartext. Cost: one method-signature change plus a credential-registration flow.
6. **Clarify `getCounters`' `since :T.Duration`** → `window` or a `T.Timestamp`. Gain: removes an ambiguity every implementer resolves differently. Cost: one field rename.
