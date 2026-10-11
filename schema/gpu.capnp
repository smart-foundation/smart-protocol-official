@0xa1b2c3d4e5f60099;

# ═══════════════════════════════════════════════════════════════════════
# GPU — vendor-agnostic graphics acceleration contract.
#
# Naledzi does not embed vendor APIs (Vulkan, Metal, OpenGL, D3D12,
# CUDA). The protocol defines the contract; backends implement it.
# A userspace GPU driver (gpu-intel, gpu-amd, gpu-nvidia) speaks this
# interface and the OS hosts it.
#
# This is the durable artifact. Vendors change, hardware changes, but
# the contract is timeless — applications targeting this interface
# remain binary-compatible across all GPU implementations.
#
# ── WHAT THIS FILE REFUSED TO DO (and why) ────────────────────────────
# The imported revision carried three enums: `GpuVendor` (twelve named
# vendors), `ShaderStage` (six of today's pipeline stages) and
# `BufferUsage` (fourteen of today's buffer affordances). None is closed
# by mathematics:
#
#   * A 2046 GPU vendor needs an ordinal, or answers `custom @11` and
#     becomes uncomparable — and R5 forbids vendor nouns outright.
#   * A mesh, ray-tracing or amplification stage needs an ordinal. The
#     set is this decade's pipeline, not a law.
#   * A video-decode, tensor-atomic or encryption-capable buffer needs
#     an ordinal.
#
# All three are now open `Text` tokens with the vocabulary documented
# here rather than frozen in the wire. An unrecognised token is ignored,
# never rejected (ai.capnp:43-47) — which is what makes a 2046 buffer
# usage expressible today with no schema change. The vendor and device
# numeric ids stay as raw numbers, because PCI-SIG assigns those; the
# *names* were the part that aged.
#
# Design rules that survive unchanged:
#   - Zero-copy: buffer payloads are T.DataHandle handles. Nothing that
#     can be large travels inline — a command stream, a shader binary
#     and a vendor escape payload are all buffer references.
#   - Forward compatibility: every union carries `unknown @N` in the
#     doctrine shape (typeId + opaque payload), never a bare `custom`.
#   - No vendor-specific *fields* leak through the API. Vendor-private
#     data goes through `VendorCommand`, identified by an open token.
#   - Authority is the interface reference: `GpuService` gates once, at
#     acquisition, and no provider method takes a capability parameter.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using import "capability.capnp".Capability;

# ── Vendor ────────────────────────────────────────────────────────
# OPEN TOKEN, was an enum of twelve vendor names. A consumer that does
# not recognise a vendor skips it. The numeric ids below are the ones
# that are actually assigned and stable; a name is not.
#
# Documented vocabulary (not exhaustive, not checked):
#   "intel", "amd", "nvidia", "arm", "imgtec", "virtio", "apple",
#   "qualcomm", "broadcom", "software" (a CPU rasteriser or emulator)

# ── Buffer usage (was a 14-value enum) ───────────────────────────
# OPEN TOKEN LIST, not a bitfield and not an enum: a consumer can
# pattern-match on individual usage with no bit assignment to publish,
# and a 2046 usage needs no ordinal.
#
# Documented vocabulary (not exhaustive, not checked):
#   "scanout"          presentable to a display
#   "shaderRead"       sampled / read in a shader
#   "shaderWrite"      written from a shader
#   "transferSrc"      source of a copy
#   "transferDst"      destination of a copy
#   "hostVisible"      CPU can map the memory
#   "hostCoherent"     no explicit host sync needed
#   "renderTarget"     colour attachment
#   "depthStencil"     depth/stencil attachment
#   "linear"           linear (untiled) layout
#   "tiled"            tiled (compressed) layout
#   "protected"        hardware-encrypted buffer

# ── Pixel format ────────────────────────────────────────────────
# T.PixelFormat (types.capnp:120) is the one colour-format vocabulary,
# and it is used verbatim. The contract forbids baking a specific
# format's byte layout — drivers decide.

# ── Shader stage (was a 6-value enum) ───────────────────────────
# OPEN TOKEN. The numeric index is what the GPU uses; the semantic
# name is an aid for humans and tools, and it is this decade's
# pipeline. A frontend decides what each stage means in its own
# language; the contract stays agnostic about which stages a given API
# exposes.
#
# Documented vocabulary (not exhaustive, not checked):
#   "vertex", "tessellationControl", "tessellationEvaluation",
#   "geometry", "fragment", "compute", "mesh", "task", "raygen"

# ── Buffer descriptor (client → driver) ───────────────────────
struct BufferDesc {
    sizeBytes @0 :UInt64;
    usage @1 :List(Text);
    # T.PixelFormat when used as a color/depth attachment; empty when
    # used only for storage or transfer.
    format @2 :T.PixelFormat;
    # Width/height in pixels for 2D surfaces; both zero for 1D buffers.
    width @3 :UInt32;
    height @4 :UInt32;
    # Tiling modifier — an opaque, driver-assigned number (the DRM
    # modifier encoding is one backend's choice). 0 = linear.
    modifier @5 :UInt64;
    label @6 :Text;
    metadata @7 :T.StringMap;
}

# ── Opaque handles ──────────────────────────────────────────
struct GpuDeviceId   { id @0 :UInt64; }
struct GpuBufferId   { id @0 :UInt64; }
struct GpuTextureId  { id @0 :UInt64; }
struct GpuPoolId     { id @0 :UInt64; }
struct GpuSurfaceId  { id @0 :UInt64; }
struct GpuFenceId    { id @0 :UInt64; }
struct GpuShaderId   { id @0 :UInt64; }

# ── Returned buffer info ───────────────────────────────────
struct GpuBuffer {
    id @0 :GpuBufferId;
    sizeBytes @1 :UInt64;
    # Optional shareable handle exposed to other services; 0 = not
    # shareable. Opaque: how a handle crosses a process boundary is
    # backend-decided, and the protocol never names the mechanism.
    shareHandle @2 :UInt64;
    # Optional mapped region id if hostVisible was requested.
    mappedRegion @3 :T.MappedRegionId;
    # Actual size the driver allocated (may be larger due to alignment).
    allocatedBytes @4 :UInt64;
}

# ── Shader module ───────────────────────────────────────
# Compiled binary. The format is vendor-specific. Drivers receive
# opaque blobs; consumers compile their own source.
struct ShaderModule {
    id @0 :GpuShaderId;
    entryPoint @1 :Text;
    # T.DataHandle: a shader binary is bulk and must not be copied into
    # the message arena (ai.capnp:74-75).
    vendorBinary @2 :T.DataHandle;
    vendor @3 :Text;
    metadata @4 :T.StringMap;
}

# ── Command buffer (vendor-specific opcode stream) ───────
# The driver is the only thing that interprets this. Length is
# bounded by GpuCapabilities.maxCommandBytes.
struct CommandBuffer {
    # T.DataHandle: the opcode stream is the bulk payload of a frame.
    opcodes @0 :T.DataHandle;
    # Submission fence: caller-allocated GpuFence that gets signaled
    # when the GPU completes this batch. Zero id = no fence.
    signalFence @1 :GpuFenceId;
    # List of buffers referenced (for lifetime tracking).
    referencedBuffers @2 :List(GpuBufferId);
    metadata @3 :T.StringMap;
}

# ── Surface present (frame submission to a display) ─────
struct SurfacePresent {
    surface @0 :GpuSurfaceId;
    image @1 :GpuBufferId;
    # Vertical-sync wait (0 = no vsync, 1 = next vsync, ...).
    vsyncCount @2 :UInt32;
    # Damage rectangle (0,0,0,0 = full surface).
    damage @3 :T.Rect;
}

# ── Capabilities (reported by the driver) ─────────────
struct GpuCapabilities {
    vendor @0 :Text;
    deviceName @1 :Text;
    apiVersion @2 :UInt32;            # BCD: 0x010200 = 1.2
    maxBufferBytes @3 :UInt64;
    maxTextureBytes @4 :UInt64;
    maxCommandBytes @5 :UInt32;
    maxPushConstants @6 :UInt32;
    maxSamplers @7 :UInt32;
    maxBoundTextures @8 :UInt32;
    maxColorAttachments @9 :UInt32;
    supportsCompute @10 :Bool;
    supportsGraphics @11 :Bool;
    supportsTiling @12 :Bool;
    supportsTimestampQueries @13 :Bool;
    supportsAsyncSubmit @14 :Bool;
    # Subset of formats the driver can sample / render to.
    supportedFormats @15 :List(T.PixelFormat);
    # Memory heap sizes in bytes.
    heapLocalBytes @16 :UInt64;
    heapSharedBytes @17 :UInt64;
    # Buffer usages this driver can allocate — open token vocabulary,
    # documented above. A consumer that does not recognise a token
    # ignores it rather than treating the buffer as unusable.
    supportedUsages @18 :List(Text);
    metadata @19 :T.StringMap;
}

# ── Vendor private blob (driver-interpreted) ──────────
# Use this for escape hatches the contract does not yet model. The
# vendor is identified by an open token; the payload is opaque to other
# vendors and to non-driver code.
struct VendorCommand {
    vendor @0 :Text;
    op @1 :UInt32;
    payload @2 :T.DataHandle;
    metadata @3 :T.StringMap;
}

# ── Result types ───────────────────────────────────────
# Unions, not `success :Bool` + `error :T.Error` siblings: two fields
# that can both be set leave a client guessing which one is true
# (DESIGN_PRINCIPLES.md:428, "NEVER swallow errors silently").
struct SubmitResult {
    union {
        ok @0 :Void;
        error @1 :T.Error;
    }
    # When ok, GPU-side command submission fence id.
    submittedFence @2 :GpuFenceId;
}

struct PresentResult {
    union {
        ok @0 :Void;
        error @1 :T.Error;
    }
    # Presentation timestamp (driver-set, in nanoseconds).
    presentedAt @2 :UInt64;
    # Actual vsync count waited on.
    vsyncsWaited @3 :UInt32;
}

# ── Unknown values are ignored, never rejected ─────────
struct UnknownGpuEvent {
    typeId @0 :UInt64;
    payload @1 :Data;
}

# ── Device event (hotplug / driver state) ──────────────
struct GpuDeviceEvent {
    at @0 :UInt64;
    union {
        gpuAttached @1 :GpuDevice;
        gpuDetached @2 :GpuDeviceId;
        driverLoaded @3 :Text;
        driverUnloaded @4 :Text;
        unknown @5 :UnknownGpuEvent;
    }
}

struct GpuDevice {
    id @0 :GpuDeviceId;
    vendor @1 :Text;
    deviceName @2 :Text;
    vendorId @3 :UInt16;
    deviceId @4 :UInt16;
    # Opaque hardware locator — how the OS finds this device. On a
    # machine with a PCI bus it encodes the bus/device/function triple;
    # on a platform with no PCI it is whatever that platform uses. The
    # protocol does not name the encoding, so a 2046 bus needs no field.
    location @5 :Data;
}

# ═══════════════════════════════════════════════════════════════════════
# The driver interface.
#
# A userspace GPU driver publishes a GpuProvider capability. The
# compositor / display service binds to it; applications bind through
# the compositor — or directly, via GpuService.openProvider below.
# ═══════════════════════════════════════════════════════════════════════
interface GpuProvider {
    # ── Static info ──
    getCapabilities @0 () -> (caps :GpuCapabilities);
    getVendorInfo @1 () -> (vendor :Text, deviceName :Text, vendorId :UInt16, deviceId :UInt16);
    ping @2 () -> T.VoidResult;

    # ── Buffer management ──
    allocateBuffer @3 (desc :BufferDesc) -> (result :GpuBufferResult);
    freeBuffer @4 (id :GpuBufferId) -> T.VoidResult;
    # Map a hostVisible buffer; returns a mapped region id usable
    # for CPU read/write. Unmap via the host's region service.
    mapHost @5 (id :GpuBufferId) -> (result :MappedRegionResult);
    unmapHost @6 (id :GpuBufferId, region :T.MappedRegionId) -> T.VoidResult;

    # ── Texture / sampler management ──
    createTexture @7 (desc :BufferDesc) -> (result :GpuTextureResult);
    destroyTexture @8 (id :GpuTextureId) -> T.VoidResult;

    # ── Shaders ──
    createShader @9 (module :ShaderModule) -> (result :GpuShaderResult);
    destroyShader @10 (id :GpuShaderId) -> T.VoidResult;

    # ── Command submission ──
    createPool @11 () -> (result :GpuPoolResult);
    destroyPool @12 (pool :GpuPoolId) -> T.VoidResult;
    submitCommandBuffer @13 (pool :GpuPoolId, cmd :CommandBuffer) -> (result :SubmitResult);

    # ── Synchronization ──
    createFence @14 (signaled :Bool) -> (result :GpuFenceResult);
    destroyFence @15 (id :GpuFenceId) -> T.VoidResult;
    waitFence @16 (id :GpuFenceId, timeout :T.Duration) -> (result :FenceWaitResult);

    # ── Surfaces (display presentation) ──
    createSurface @17 (outputId :T.OutputId, width :UInt32, height :UInt32) -> (result :GpuSurfaceResult);
    destroySurface @18 (surface :GpuSurfaceId) -> T.VoidResult;
    presentToSurface @19 (present :SurfacePresent) -> (result :PresentResult);

    # ── Vendor escape hatch (for features the contract doesn't model) ──
    vendorCommand @20 (cmd :VendorCommand) -> (result :VendorCommandResult);

    # ── 3D command stream ──
    # A structured draw convenience over the raw command path above. It
    # grants no power `submitCommandBuffer` does not already confer — the
    # opcode stream is opaque and vendor-encoded, so any provider holder
    # can already submit 3D work — so there is one capability-gated
    # provider and one grant, not a second interface with its own accessor
    # (DESIGN_PRINCIPLES.md: "one accessor per service").
    submitRenderCommandBuffer @21 (pipeline :PipelineState, attributes :List(VertexAttribute), buffers :List(VertexBuffer), draw :DrawCall) -> SubmitResult;
    # Upload a shader in the frontend's chosen source language. The
    # contract is: a (stage, source bytes) pair. The frontend decides
    # what language; the GPU backend compiles.
    uploadShader @22 (stage :Text, source :T.DataHandle) -> (result :CompiledShaderResult);
}

struct GpuBufferResult {
    union {
        ok @0 :GpuBuffer;
        error @1 :T.Error;
    }
}

struct MappedRegionResult {
    union {
        ok @0 :T.MappedRegionId;
        error @1 :T.Error;
    }
}

struct GpuTextureResult {
    union {
        ok @0 :GpuTextureId;
        error @1 :T.Error;
    }
}

struct GpuShaderResult {
    union {
        ok @0 :GpuShaderId;
        error @1 :T.Error;
    }
}

struct GpuPoolResult {
    union {
        ok @0 :GpuPoolId;
        error @1 :T.Error;
    }
}

struct GpuFenceResult {
    union {
        ok @0 :GpuFenceId;
        error @1 :T.Error;
    }
}

struct GpuSurfaceResult {
    union {
        ok @0 :GpuSurfaceId;
        error @1 :T.Error;
    }
}

struct FenceWaitResult {
    union {
        signaled @0 :Void;
        error @1 :T.Error;
    }
}

struct VendorCommandResult {
    union {
        ok @0 :T.DataHandle;
        error @1 :T.Error;
    }
}

# ═══════════════════════════════════════════════════════════════════════
# 3D command stream
#
# A 3D command stream is a sequence of vendor-encoded opcodes that the
# GPU's command streamer executes in order. The driver knows how to
# interpret the opcodes; consumers compile their pipeline state into
# opcodes and submit.
#
# The encoding is the backend's business. The previous revision
# documented one vendor's dword layout in the schema header, which
# taught implementers a private format and promised nothing to anyone
# else. A driver publishes its own convention through GpuCapabilities
# or `label`; the contract carries the bytes, not the grammar.
# ═══════════════════════════════════════════════════════════════════════

# Compiled shader binary. The vendor binary is the GPU-specific
# instruction stream. The shader binary is opaque to the consumer;
# only the GPU driver for the matching vendor can interpret it. Every
# frontend's intermediate representation is a `binary` blob from this
# contract's perspective.
struct CompiledShader {
    stage @0 :Text;
    vendor @1 :Text;
    binary @2 :T.DataHandle;
    # Number of constant buffer entries (push constants / uniforms).
    constantCount @3 :UInt32;
    # Number of input varyings.
    inputCount @4 :UInt32;
    # Number of output varyings.
    outputCount @5 :UInt32;
    entryPoint @6 :Text;
    metadata @7 :T.StringMap;
}

# 3D pipeline state. The consumer fills this in to describe what they
# want the GPU to do; the driver compiles it into its native commands.
#
# The numeric mode fields (cull, front face, topology, vertex format)
# are deliberately opaque integers with their vocabulary documented,
# not enums: they are this decade's rasteriser knobs, and a 2046 GPU
# with a new blend equation or a new primitive type must not need an
# ordinal in an eternal schema. `properties` carries anything a
# driver needs that the contract does not model.
struct PipelineState {
    # Whether the GPU writes to the framebuffer.
    enableColorWrite @0 :Bool;
    # Whether the GPU does depth testing.
    enableDepthTest @1 :Bool;
    # Whether the GPU does stencil testing.
    enableStencil @2 :Bool;
    # Cull mode: 0 = none, 1 = front, 2 = back.
    cullMode @3 :UInt8;
    # Front face: 0 = counter-clockwise, 1 = clockwise.
    frontFace @4 :UInt8;
    # Topology: 0 = triangles, 1 = triangle strip, 2 = triangle fan,
    # 3 = lines, 4 = line strip, 5 = points.
    topology @5 :UInt8;
    # Pixel format of the framebuffer attachment.
    colorFormat @6 :T.PixelFormat;
    # Viewport width / height in pixels.
    viewportWidth @7 :UInt32;
    viewportHeight @8 :UInt32;
    # Vertex shader handle (id from createShader).
    vertexShader @9 :GpuShaderId;
    # Fragment shader handle.
    fragmentShader @10 :GpuShaderId;
    # Anything the driver needs that the fields above do not carry.
    properties @11 :T.StringMap;
}

# One draw call. The driver compiles this into its native draw command.
struct DrawCall {
    # Index of the first vertex.
    firstVertex @0 :UInt32;
    # Number of vertices to draw.
    vertexCount @1 :UInt32;
    # First instance (for instanced draws).
    firstInstance @2 :UInt32;
    # Number of instances.
    instanceCount @3 :UInt32;
}

# A vertex attribute. The driver composes its native vertex-buffer and
# vertex-element commands from these.
struct VertexAttribute {
    buffer @0 :UInt32;        # Which vertex buffer this attribute reads from
    offset @1 :UInt32;        # Byte offset within the buffer
    format @2 :UInt32;        # 0=Float, 1=Float2, 2=Float3, 3=Float4, 4=Byte, ...
    components @3 :UInt8;      # 1, 2, 3, or 4
    divisor @4 :UInt8;        # 0 = per-vertex, 1 = per-instance
}

struct VertexBuffer {
    address @0 :UInt64;
    stride @1 :UInt32;
    size @2 :UInt64;
}

# Extended interface for 3D command stream submission.
# Methods are paradigm-agnostic: any frontend can drive this interface,
# translating its own language into GpuProvider calls.
struct CompiledShaderResult {
    union {
        ok @0 :CompiledShader;
        error @1 :T.Error;
    }
}

# ═══════════════════════════════════════════════════════════════════════
# GpuService — the entry point.
#
# The imported revision declared `GpuProvider` and `Gpu3DProvider` and
# NO METHOD ANYWHERE returned either, so the whole file was unreachable
# contract: a driver author following it implemented twenty types that
# no client could ever call (R8). This root closes that hole.
#
# The pattern follows ai.capnp:57-60 exactly — discovery is ungated so a
# caller can learn what exists before it holds any authority, and every
# operation that consumes GPU resources is behind a single accessor that
# takes a Capability exactly once. Holding the returned provider IS the
# authority; no provider method takes a token.
# ═══════════════════════════════════════════════════════════════════════
interface GpuService {
    # ── Ungated discovery ──
    listDevices @0 (page :T.Pagination) -> (devices :List(GpuDevice), total :UInt64);
    getDevice @1 (id :GpuDeviceId) -> (device :GpuDevice);
    getCapabilities @2 (id :GpuDeviceId) -> (result :GpuCapabilitiesResult);
    subscribeDevices @3 () -> (subscription :GpuEventSubscription);

    # ── Gated once, at acquisition ──
    # One accessor. Holding the returned provider IS the authority to
    # allocate buffers, submit commands and drive 3D work; the raw command
    # path already confers that power, so a separate 3D interface and grant
    # would add surface without a privilege boundary.
    openProvider @4 (authority :Capability, id :GpuDeviceId) -> (provider :GpuProvider);
}

# getCapabilities is a discovery read, not an acquisition, so it keeps an
# explicit result union: a backend that cannot report capabilities (a
# device that was just detached) has something honest to return.
struct GpuCapabilitiesResult {
    union {
        ok @0 :GpuCapabilities;
        error @1 :T.Error;
    }
}

# The accessors below return the service interface directly, exactly as
# ai.capnp:578-584 does: a backend that refuses the capability fails the
# call, and holding the returned provider IS the authority to allocate
# buffers and submit commands — no per-method token, and no wrapper
# struct holding a second authority for the same outcome.

interface GpuEventSubscription {
    # Bounded: the pull takes the caller's maximum, so a hotplug burst
    # cannot be materialised whole and a slow consumer cannot grow the
    # server's queue without limit.
    pull @0 (maxEvents :UInt32) -> (events :List(GpuDeviceEvent));
    cancel @1 () -> T.VoidResult;
}
