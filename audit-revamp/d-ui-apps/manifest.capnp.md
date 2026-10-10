# Audit — manifest.capnp (311 lines)

## Verdict
**FIX (targeted) — the batch's closest-to-exemplary file, and I say so plainly.** The doctrine already lists manifest.capnp as exemplary (DESIGN_PRINCIPLES:507), and the audit confirms why: identity via typed `T.ManifestName`, opaque `contentHash :Data`, ABIs and entry points backend-agnostic, capabilities requested *as operations over targets* by importing `capability.capnp` (110), dependencies by `T.SchemaId` with semver ranges, an asset model, runtime hints as open name/value pairs (178–183), and no platform noun in a required position. It is the file `package.capnp` should reference and doesn't. Four targeted defects: (1) **`resolve @0 (name :T.ManifestName)` cannot resolve by name** — `ManifestName` is an opaque `UInt64` (types.capnp:451) while the struct comment says "Unique name within issuer's namespace" (18): a consumer knowing only the human name of a bundle has no way to address it, so every backend invents a name→id map. (2) `ManifestEvent` (230–236) has no `unknown` variant — validator E6 flags it at line 230; a future catalog event kind is unroutable. (3) `VersionRange` (270) and `DependencyWithAttestation` (260) are orphans — no method references either. (4) `OciImageManifest` (276–288) duplicates package.capnp's OCI vocabulary (436), a technology noun both files should drop or share.

## Wire-breakers
None. `using import "abi.capnp".Abi` (78) and `using import "capability.capnp".Operation` (110) resolve.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R4/R7 | `manifest.capnp:17, 188` | `Manifest.name @0 :T.ManifestName` with doc "Unique name within issuer's namespace" (18), and `resolve @0 (name :T.ManifestName)` — but `T.ManifestName` is a bare `struct { id :UInt64 }` (types.capnp:451) | The service's only lookup is by opaque number while the schema's own text says manifests are *named*. A consumer (shell, index, app) that knows `org.example.editor` cannot resolve it: each backend ships its own name registry and string→id mapping is non-interoperable. Either the name is Text (with uniqueness by convention) or a text→typed lookup must exist |
| R7 | `manifest.capnp:230` | `ManifestEvent { added, removed, updated }` — no `unknown @N :UnknownEvent` variant | A future catalog event (deprecation, migration, attestation revocation) arrives at old consumers as an unrecognized union member with no dispatch data. The doctrine's forward-compat shape (TIMELESSNESS:98) is violated in the one file held up as timeless (validator E6, reported) |
| R6 | `manifest.capnp:260, 270` | `DependencyWithAttestation` and `VersionRange` referenced by no method, no struct, no interface — dead definitions | `Dependency @114–124` already carries attestation and min/max; the orphans are a second draft of the same idea that will mislead implementers about which is normative |
| R5 | `manifest.capnp:276–288` | `OciImageManifest { mediaType, layers, annotations }` + `BundleShape.ociImage @11` (150) — OCI (a 2010s container format) as a bundle *shape* in the timeless file | A 2046 distribution format (content-addressed bundles, neural-model packages) has no shape ordinal; `container @10` is the generic shape, `ociImage` is one instance of it. Same class as `PackageType` in package.capnp and `OciImageInstallRequest` |
| R1 | `manifest.capnp:126` | `BundleShape { app, service, firmware, plugin, snapshot, asset, theme, library, system, user, container, ociImage, federated, custom }` | `federated` and `ociImage` are technology-era nouns; the enum is mostly defensible because it has `custom @13`, but two of fourteen values name 2026 tooling. Prefer generic shapes + open metadata over named instances |
| R7 | `manifest.capnp:202, 208, 220` | `validate @6 -> (valid :Bool, errors :List(Text))`, `verify @8 -> (verified :Bool, signer :Text)`, `validateDependencies @12 -> (valid :Bool, errors :List(Text))` — failures as free-text lists | The protocol's error type carries a machine-routable code plus retryable; these three return prose. Consumers cannot act programmatically on "invalid" |

## Duplicates & overlaps
- `ManifestProvenance` (251–257) vs `package.capnp:267 Provenance` — identical five-field structs (buildSystem, commitHash, pipelineId, builtAt, builder); one home, this one (package imports it).
- `OciImageManifest`/`OciDescriptor` (276–288) vs `package.capnp:436 OciImageInstallRequest` + the OciCredentials sibling — one OCI vocabulary leak across two files.
- `VersionRange` vs `Dependency.minVersion/maxVersion` (118–119) — the orphan is a duplicate of the inline fields.
- This file's `CapabilityRequirement { target, operations :List(Operation), optional, reason }` (99–108) is the **model** app.capnp's `AppPermission` (382) and extension's `ExtensionCapability` (195) should have copied — cite this file when fixing those.

## Gaps & holes
- **Nothing in the protocol consumes Manifest yet**: the package service, appindex, and intent registration all carry their own metadata. Until `PackageInfo` embeds `Manifest`, the universal self-description the file advertises (5–12) is a schema without a host. This is the single highest-leverage merge in the batch (see package audit, action 1).
- `resolve` is the only read path; no way to enumerate manifests by schema offered (`list @1` has `offersSchemaId @3 :T.SchemaId` in the filter — present, good) — consistent, no gap. (Recorded to keep the audit honest: this gap is *already closed*.)

## Zero-cost / eco
- `assets @12 :List(Asset)` carry `path`/`kind`/`mime` + `sizeBytes :UInt32` — references, not contents; an implementation streaming a bundle copies nothing it doesn't need. Correct.
- `Dependency.attestation @5 :Data` (123) — attestation blobs are small; inline is right.
- No bulk payloads anywhere in the file — the discipline is consistent.

## UX & implementer guidance
- `Semver.major/minor/patch :UInt16` (81–83): a 16-bit major means the schema's version arithmetic wraps at 65535 — `T.Version` (types.capnp:64) uses UInt32 and carries epoch/preRelease; the file defines a *second* version type two schemas deep. Either promote Semver semantics into `T.Version` or import it.
- `Asset.sizeBytes @3 :UInt32` (164): a 4-byte cap on asset size silently truncates multi-GB assets; UInt64 is the standard everywhere else in the batch.
- `ManifestService.compose @4`/`composeWithConfig @11` with `MergeConfig` (300–311) — composition is well-shaped but `ManifestChange.oldValue/newValue :Text` (244–248) loses typing on diff; a manifest diff of structured fields arrives as strings.

## Recommended actions
1. **Fix manifest addressing**: either make `Manifest.name` human-readable and unique (Text + issuer namespace, or a `name :Text` field alongside the typed id) or add `resolveByName (name :Text)`. Gain: every consumer in the protocol can address a bundle by the name its users know; the backend name-registry fork closes. Cost: one field or one method.
2. **Add `unknown` to `ManifestEvent`** (and typed errors on validate/verify/validateDependencies: `T.Error` alongside the human list). Gain: forward-compatible catalog events and machine-routable validation failures. Cost: one union member + three return shapes.
3. **Delete the orphans** (`VersionRange`, `DependencyWithAttestation`). Gain: one normative dependency shape. Cost: nothing references them.
4. **Make `PackageInfo` embed `Manifest`** (package.capnp action 1) and have `ManifestProvenance` be the single provenance type. Gain: the exemplary file becomes *load-bearing* — one bundle self-description serves packages, apps, services, plugins. Cost: package refactor, described in the package audit.
5. **Drop `ociImage` from `BundleShape` and delete `OciImageManifest`/`OciDescriptor`** (generic `container` shape + opaque payload metadata covers it; package's OCI path shrinks to an opaque reference). Gain: no container-format noun in the timeless file. Cost: one enum value + two structs deleted.
6. **Unify with `T.Version`** (or promote `Semver` to types.capnp and use it everywhere). Gain: one version arithmetic — app, package, index, and manifest currently compare versions with three different structs. Cost: one struct decision.
