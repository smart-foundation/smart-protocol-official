# Smart Protocol — Binding Conventions (v0.0.1)

> **Status: LEGACY / GENERATED.** This document was generated against an earlier draft and its schema counts and ordinals may be stale. The `.capnp` files in `schema/` are the source of truth; cross-check before relying on any number here. Current tree: 89 schemas (see `python3 scripts/validate.py`).

**Status:** First implementation. Not yet committed. Nothing has been built against these
schemas yet, so the wire format is free to evolve within v0.0.1 without breaking anything.

This document explains the **non-obvious contract decisions** that a language binding author
must follow to build interfaces from the `*.capnp` schemas in `schema/`. The schemas all
compile cleanly (89/89), but the fixes applied during the audit-10 cleanup introduced a few
patterns that differ from how Cap'n Proto codegen would normally read the source.

---

## 1. Enum naming: `snake_case` → `camelCase` was forced

Cap'n Proto requires enum variant names to be `camelCase`. The original schemas used
`snake_case` (e.g. `tar_gz`, `pbkdf2_hmac_sha256`, `rsa_pkcs1_sha256`). These were **renamed**
to comply. The generated code will use the camelCase forms.

### 1.1 Renamed variants — alias them in your binding

For human readability, expose the original semantic name as an alias in your language
binding.

| Schema | Renamed variant (wire) | Original intent |
|--------|------------------------|-----------------|
| `audio.capnp` | `surround51` | `surround_5_1` |
| `audio.capnp` | `surround71` | `surround_7_1` |
| `audio.capnp` | `surround21` / `surround40` / `surround41` / `surround50` / `surround70` | `surround2_1`, `surround4_0`, … |
| `archive.capnp` | `tarGz` / `tarBz2` / `tarXz` / `tarZst` / `tarLz4` / `tarLzma` | `tar_gz`, `tar_bz2`, … |
| `archive.capnp` | `cpioGz` | `cpio_gz` |
| `archive.capnp` | `reduced1` / `reduced2` / `reduced3` / `reduced4` | `reduced_1`, … |
| `archive.capnp` | `zstdFast` / `zstdHigh` | `zstd_fast`, `zstd_high` |
| `crypto.capnp` | `sha512224` / `sha512256` / `sha3224` / `sha3256` / `sha3384` / `sha3512` | `sha512_224`, `sha3_224`, … |
| `crypto.capnp` | `pbkdf2HmacSha256` / `pbkdf2HmacSha512` | `pbkdf2_hmac_sha256`, … |
| `crypto.capnp` | `hkdfSha256` / `hkdfSha384` / `hkdfSha512` / `hkdfBlake2b` / `hkdfBlake3` | `hkdf_sha256`, … |
| `crypto.capnp` | `kbkdfHmacSha256` / `kbkdfAesCmac` | `kbkdf_hmac_sha256`, … |
| `crypto.capnp` | `x963Sha256` / `x963Sha384` / `x963Sha512` | `x963_sha256`, … |
| `crypto.capnp` | `aes256Gcm` / `aes128Gcm` / `chacha20Poly1305` / `xchacha20Poly1305` | `aes256_gcm`, `chacha20_poly1305`, … |
| `crypto.capnp` | `aes256Siv` / `aes128Siv` / `pqcHybrid` | `aes256_siv`, `pqc_hybrid` |
| `crypto.capnp` | `ecdsaP256` / `ecdsaP384` / `ecdsaP521` / `ecdsaSecp256k1` | `ecdsa_p256`, … |
| `crypto.capnp` | `ecdhP256` / `ecdhP384` / `ecdhP521` | `ecdh_p256`, … |
| `crypto.capnp` | `rsaPssSha256` / `rsaOaepSha256` / `rsaPkcs1Sha256` | `rsa_pss_sha256`, … |
| `crypto.capnp` | `mlKem512` / `mlDsa65` / `slhDsaSha2128s` / `x25519MlKem768` | `ml_kem_512`, `ml_dsa_65`, … |
| `crypto.capnp` | `aes256Kw` / `aes256Kwp` | `aes256_kw`, `aes256_kwp` |
| `boot.capnp` | `x8664` | `x86_64` |
| `sandbox.capnp` | `x8664` | `x86_64` |
| `vcard.capnp` | `v21` / `v30` / `v40` / `v50` | `v2_1`, `v3_0`, `v4_0`, `v5_0` |
| `usb.capnp` | `usb420G` / `usb440G` / `usb480G` / `thunderbolt340G` | `usb4_20G`, … |
| `network.capnp` | `band24GHz` | `band2_4GHz` |
| `hal.capnp` | `mipiCsi` | `mipi CSI` (was invalid — had a space) |

> Recommendation: in the generated binding layer, write
> `pub const AES_256_GCM: AeadAlgorithm = AeadAlgorithm::aes256Gcm;` or equivalent so consumers
> don't need to memorize the camelCase forms.

### 1.2 Architecture naming collision (important)

Both `boot.capnp` and `sandbox.capnp` have an enum variant `x8664` (renamed from `x86_64`).
If you generate both into a flat namespace, **rename on import** to avoid collision, e.g.
`BootArchitecture::x8664` vs `CpuArchitecture::x8664`.

---

## 2. Collapsed ordinal gaps — wire ordinals changed from draft-9

Several enums had intentional ordinal gaps (used for "future grouping") that Cap'n Proto
rejects. The gaps were **collapsed** so the schema compiles. This changes the wire ordinals
vs. any pre-audit-10 draft.

Examples:
- `types.capnp` `Currency`: `btc @100`, `eth @101`, `custom @1000` → `btc @9`, `eth @10`, `custom @11`
- `crypto.capnp` `HashAlgorithm`: `custom @1000` → `custom @20`
- `crypto.capnp` `KdfAlgorithm`: `custom @1000` → `custom @19`
- `archive.capnp` `ArchiveFormat`: `custom @1000` → `custom @34`
- `mount.capnp` `FilesystemType`: grouping gaps (e.g. `@7`→`@10`, `@28`→`@30`) → sequential

**Since no implementation exists yet, this is fine.** But the audit-10 `*.capnp.md` docs were
written against the OLD ordinals and now **do not match** the schemas. Treat the `.capnp`
files as source of truth, not the docs.

---

## 3. `union` types became `struct { union { … } }`

Cap'n Proto does not allow a bare `union` declaration at file scope as a standalone type.
Where the original draft had `union Foo { … }` used as a field type, it was converted to:

```capnp
struct Foo {
    union {
        variantA @0 :TypeA;
        variantB @1 :TypeB;
    }
}
```

Examples: `DatabaseValue`, `IoStatsTarget`, `MetricValue`, `VCardValue`, `SyscallIdentifier`,
`AbiEndorsement` (verify per-schema).

**Binding rule:** a field of type `Foo` is accessed as `foo.which()` / `foo.variant_a()` —
the union is *inside* the struct, not a separate type.

---

## 4. Subscription structs became interfaces

Several types named `*Subscription` used interface-method syntax (`pull @0 () -> …;
cancel @1 () -> …;`) **inside a `struct`**, which is invalid. They were converted to
`interface`:

- `ServiceEventSubscription`, `MountEventSubscription`, `IoStatsSubscription`,
  `HistoricalIoStatsSubscription`, `SignalSubscription`, `StateSubscription`,
  `DndSubscription`, `InputSubscription`, `CursorSubscription`, `GestureSubscription`,
  `ThemeSubscription`, `AccessSubscription`, `TreeSubscription`, `EventSubscription`,
  `AppSubscription`, `HealthSubscription`, `AppIndexSubscription`, `ProgressSubscription`,
  `StateSubscription`, `KeySubscription` (database), and others.

**Binding rule:** treat `*Subscription` as a **capability reference** (server-side object),
not a plain struct. The client holds a proxy; `pull()` and `cancel()` are RPC calls.

Also note: `subscribe` methods that returned a bare `SignalSubscription` (no field name)
were fixed to return `(subscription :SignalSubscription)` — named result fields are required.

---

## 5. Missing types defined in `types.capnp`

These were added to `types.capnp` during cleanup because multiple schemas reference them via
`T.` prefix:

- `T.TimeRange` — used by notification, diagnostics, timezone
- `T.DeviceGroupId` — used by update
- `T.TlsVersion` (enum) — used by socket
- `T.SearchBookmarkId` — used by system_search
- `T.PowerState` (enum, in `power.capnp`) — used by shell
- `T.HalCapability` (enum, in `hal.capnp`) — used by hal
- `T.StorageTier` (enum, in `storage.capnp`) — used by storage
- `T.ShellAction` (struct, in `shell.capnp`) — used by windowmanager
- `T.KeySubscription` (struct, in `database.capnp`) — used by key_management
- `T.AccessibilityNode` (struct, in `accessibility.capnp`) — used by surface

**Binding rule:** for cross-file references that were resolved by adding a wrapper struct or
importing another schema, follow the `using X = import "x.capnp";` and reference as
`X.TypeName`.

---

## 6. `const` inside structs: no ordinal

Some schemas had `const FOO @N :Type = value;` inside a struct. Cap'n Proto `const`
declarations **do not take an ordinal**. Fixed to `const FOO :Type = value;`. (Seen in
`endpoint.capnp` VsockEndpoint well-known CIDs.)

---

## 7. Duplicate type names

`web.capnp` had both an enum `ServiceWorkerState` and a struct `ServiceWorkerState`. The
struct was renamed to `ServiceWorkerInfo`. Binding authors: use `ServiceWorkerInfo` for the
struct, `ServiceWorkerState` for the enum.

---

## 8. Build categories (compile incrementally)

The full workspace has 17 crates and 89 schemas. **Do not compile all at once** — split by
category. The `smart-protocol` crate's `build.rs` currently compiles 67 schemas; the
remaining 23 must be added per category when their crate is built:

| Category | Schemas (not yet in build.rs) |
|----------|-------------------------------|
| Security/crypto | `crypto`, `key_management`, `signature`, `secret` |
| IO/storage | `storage`, `archive`, `mount`, `filesystem`, `files` |
| Network | `socket`, `dns`, `endpoint`, `network`, `tunnel`, `discovery` |
| HID/input | `input`, `ime`, `textinput`, `console`, `keyboard` (if exists) |
| Sensors/telemetry | `sensor`, `diagnostics`, `clock`, `timezone`, `klog` |
| Identity/comms | `contacts`, `vcard`, `calendar`, `telephony`, `nfc`, `bluetooth`, `biometric` |
| Runtime | `sandbox`, `task_scheduler`, `runtime_search`, `signal`, `intent`, `framebuffer`, `content`, `access` |

**Verification order (smallest first):**
1. `types.capnp` alone (foundation)
2. `abi.capnp` + `manifest.capnp` + `capability.capnp` (Tier 1)
3. `crypto.capnp` alone (largest enum renames)
4. `archive.capnp` alone (largest ordinal collapse)
5. Per-category batches above

---

## 9. What is NOT ready yet (contract gaps to close before v0.1.0)

- Audit `*.capnp.md` docs are **stale** (wrong ordinals, wrong enum names). Regenerate them
  from current schemas before publishing.
- No language binding beyond Rust exists. Go/Dart/C consumers must generate from these.
- No transport layer defined (Cap'n Proto RPC over what? Unix socket? vsock? kernel IPC?).
  The protocol describes the *what*, not the *how* of transport.
- No backend trait implementations in `smart-lib` wired to these interfaces yet.

---

*Generated for SpaceOs bootstrap. v0.0.1 is the contract-freeze baseline: schemas compile,
naming/ordinals are final for this version, implementations may now begin.*
