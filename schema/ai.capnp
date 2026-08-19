@0xa1b2c3d4e5f60061;

# AI/ML Inference & Agent Coordination
#
# Universal contract for AI inference, model management, and multi-agent systems.
# Backend decides: local (llama.cpp, ONNX, tensorrt), remote (OpenAI, Anthropic),
# distributed (ray, k8s), or future runtimes.
# The protocol sees: tensors, capabilities, agents, tools, conversations, embeddings.
#
# Timeless design principles:
# - No assumption about model architecture (transformer, Mamba, RWKV, future)
# - No assumption about quantization (q4_k_m, q8_0, f16, bf16, future formats)
# - No assumption about execution (local GPU, remote API, distributed, WASM, future)
# - Extensible via opaque Data + custom variants everywhere
# - Capability-gated for security, subscription-based for streaming

using T = import "types.capnp";
using import "capability.capnp".Capability;

# ── Core Identifiers ──────────────────────────────────────────────
struct ModelId        { id @0 :UInt64; }
struct TensorId       { id @0 :UInt64; }
struct ConversationId { id @0 :UInt64; }
struct AgentId        { id @0 :UInt64; }
struct ToolId         { id @0 :UInt64; }
struct EmbeddingId    { id @0 :UInt64; }
struct SessionId      { id @0 :UInt64; }
struct RequestId      { id @0 :UInt64; }

# ── Model Architecture (Generic Categories - Timeless) ────────────
# These are ARCHITECTURAL PARADIGMS, not specific models.
# Transformer has been dominant since 2017. SSM/Mamba since 2023.
# New paradigms get added; old ones don't disappear.
enum ModelArchitecture {
    transformer @0;      # Attention-based (GPT, BERT, Llama, etc.)
    ssm @1;              # State Space Models (Mamba, RWKV, etc.)
    rnn @2;              # Recurrent (LSTM, GRU, etc.)
    cnn @3;              # Convolutional
    diffusion @4;        # Diffusion models
    linearAttention @5;  # Linear attention variants (RWKV, etc.)
    mixtureOfExperts @6; # MoE
    custom @7;           # Future/unknown paradigms
}

# ── Model Capabilities (What the Model CAN DO - Contract) ──────────
# This is the EXTERNAL CONTRACT. Backend decides which model provides it.
enum ModelCapability {
    completion @0;          # Text generation
    embedding @1;           # Vector embeddings
    vision @2;              # Image/video understanding
    audio @3;               # Audio processing (STT, TTS, understanding)
    toolUse @4;             # Function calling
    structuredOutput @5;    # Constrained generation (JSON schema)
    reasoning @6;           # Chain-of-thought, multi-step
    multimodal @7;          # Multiple input modalities
    custom @8;              # Future capabilities
}

# ── Standard Serialization Formats (Industry Standards) ───────────
# These ARE timeless standards, not vendor products.
enum ModelFormat {
    raw @0;           # Raw tensor weights (no container)
    onnx @1;          # ONNX (industry standard, supported everywhere)
    safetensors @2;   # SafeTensors (fast, safe, widely adopted)
    gguf @3;          # GGUF (quantized format, cross-backend standard)
    custom @4;        # Backend-specific
}

# ── Tensor Primitives ─────────────────────────────────────────────
# Tensor data types - uses standard types from types.capnp DataType
# f32, f16, bf16, i8, i16, i32, i64, u8, u16, u32, u64, bool
# q4_0, q4_k_m, q5_0, q5_1, q8_0 (STANDARD quantization schemes)
# custom

enum TensorDataType {
    # Standard floating point
    f32 @0; f16 @1; bf16 @2;
    # Standard integers
    i8 @3; i16 @4; i32 @5; i64 @6;
    u8 @7; u16 @8; u32 @9; u64 @10;
    bool @11;
    # Standard quantization schemes (cross-backend)
    q40 @12; q4km @13; q50 @14; q51 @15; q80 @16;
    custom @17;
}

struct TensorShape {
    dims @0 :List(UInt64);
    strides @1 :List(UInt64);  # Optional, for non-contiguous
}

struct Tensor {
    id @0 :TensorId;
    shape @1 :TensorShape;
    dtype @2 :TensorDataType;    # Tensor data type
    data @3 :T.DataHandle;       # Zero-copy via types.capnp
    name @4 :Text;
    quantization @5 :T.DataHandle;   # Optional: per-tensor quantization params
}

# ── Model Metadata (Generic - No Product Names) ───────────────────
struct ModelSpec {
    name @0 :Text;                    # Human-readable name
    architecture @1 :ModelArchitecture;  # Generic category
    format @2 :ModelFormat;           # Standard serialization
    params @3 :UInt64;                # Parameter count
    quantization @4 :TensorDataType;  # Quantization scheme
    contextLength @5 :UInt32;         # Max context window
    capabilities @6 :List(ModelCapability);  # What this model CAN DO
    # LoRA/adapter support
    adapterIds @7 :List(ModelId);
}

struct ModelInfo {
    spec @0 :ModelSpec;
    id @1 :ModelId;
    loaded @2 :Bool;
    memoryBytes @3 :UInt64;
    metadata @4 :T.StringMap;
}

struct ModelFilter {
    namePattern @0 :Text;
    architecture @1 :ModelArchitecture;
    capability @2 :ModelCapability;
    loadedOnly @3 :Bool;
}

# ── Completion/Generation (The Core Contract) ─────────────────────
struct CompletionRequest {
    model @0 :ModelId;
    # Either prompt OR messages (chat format preferred)
    prompt @1 :Text;
    messages @2 :List(ChatMessage);
    maxTokens @3 :UInt32;
    temperature @4 :Float32;
    topP @5 :Float32;
    topK @6 :UInt32;
    stopSequences @7 :List(Text);
    stream @8 :Bool;
    tools @9 :List(ToolSpec);
    toolChoice @10 :ToolChoice;
    responseFormat @11 :ResponseFormat;
    seed @12 :UInt64;
    presencePenalty @13 :Float32;
    frequencyPenalty @14 :Float32;
    logitBias @15 :T.StringMap;
    user @16 :Text;
    custom @17 :Data;
}

struct ChatMessage {
    role @0 :MessageRole;
    content @1 :Text;
    name @2 :Text;           # For tool messages
    toolCalls @3 :List(ToolCall);
    toolCallId @4 :Text;     # For tool responses
}

enum MessageRole {
    system @0; user @1; assistant @2; tool @3; developer @4; custom @5;
}

enum ToolChoice {
    auto @0;           # Model decides
    none @1;           # No tools
    required @2;       # Must use a tool
    specific @3;       # Force specific tool (name in toolName)
    custom @4;
}

struct ToolSpec {
    name @0 :Text;
    description @1 :Text;
    parameters @2 :T.DataHandle;  # JSON Schema
    returns @3 :T.DataHandle;     # JSON Schema for return type
    custom @4 :Data;
}

struct ToolCall {
    id @0 :Text;
    name @1 :Text;
    arguments @2 :T.DataHandle;  # JSON
}

enum ResponseFormatType {
    text @0; jsonObject @1; jsonSchema @2; custom @3;
}

struct ResponseFormat {
    type @0 :ResponseFormatType;
    jsonSchema @1 :T.DataHandle;  # For jsonSchema type
}

struct CompletionResponse {
    id @0 :RequestId;
    model @1 :ModelId;
    choices @2 :List(Choice);
    usage @3 :Usage;
    created @4 :T.Timestamp;
    custom @5 :Data;
}

struct Choice {
    index @0 :UInt32;
    message @1 :ChatMessage;
    finishReason @2 :FinishReason;
    logprobs @3 :LogProbs;
}

enum FinishReason {
    stop @0; length @1; toolCalls @2; contentFilter @3; custom @4;
}

struct LogProbs {
    content @0 :List(TokenLogProb);
}

struct TokenLogProb {
    token @0 :Text;
    logprob @1 :Float32;
    bytes @2 :List(UInt8);
}

struct Usage {
    promptTokens @0 :UInt32;
    completionTokens @1 :UInt32;
    totalTokens @2 :UInt32;
}

# ── Streaming (Pull-based, UInt64 subscription - standard pattern) ──
interface CompletionStream {
    pull @0 () -> (chunk :CompletionChunk);
    cancel @1 () -> T.VoidResult;
}

struct CompletionChunk {
    id @0 :RequestId;
    choices @1 :List(StreamChoice);
    usage @2 :Usage;
    custom @3 :Data;
}

struct StreamChoice {
    index @0 :UInt32;
    delta @1 :ChatMessage;
    finishReason @2 :FinishReason;
}

# ── Embeddings ────────────────────────────────────────────────────
struct EmbedRequest {
    model @0 :ModelId;
    input @1 :List(Text);  # Or single text
    encodingFormat @2 :EncodingFormat;  # float, base64
    dimensions @3 :UInt32;  # For models supporting truncation
    user @4 :Text;
    custom @5 :Data;
}

enum EncodingFormat {
    float @0; base64 @1; custom @2;
}

struct EmbedResponse {
    model @0 :ModelId;
    embeddings @1 :List(Embedding);
    usage @2 :Usage;
    custom @3 :Data;
}

struct Embedding {
    index @0 :UInt32;
    vector @1 :List(Float32);  # Or T.DataHandle for large
    embeddingId @2 :EmbeddingId;
}



interface ToolRegistry {
    register @0 (spec :ToolSpec) -> (tool :ToolId);
    unregister @1 (tool :ToolId) -> T.VoidResult;
    get @2 (tool :ToolId) -> (spec :ToolSpec);
    list @3 (page :T.Pagination) -> (tools :List(ToolSpec), total :UInt64);
    invoke @4 (tool :ToolId, args :T.DataHandle) -> (result :ToolResult);
}

struct ToolResult {
    success @0 :Bool;
    result @1 :T.DataHandle;  # JSON
    error @2 :T.Error;
    custom @3 :Data;
}

# ── Agents & Multi-Agent ──────────────────────────────────────────
struct AgentSpec {
    name @0 :Text;
    description @1 :Text;
    model @2 :ModelId;
    systemPrompt @3 :Text;
    tools @4 :List(ToolId);
    memoryConfig @5 :MemoryConfig;
    handoffConfig @6 :HandoffConfig;
    custom @7 :Data;
}

struct MemoryConfig {
    type @0 :MemoryType;
    maxTokens @1 :UInt32;
    retentionPolicy @2 :T.DataHandle;
    custom @3 :Data;
}

enum MemoryType {
    conversation @0;  # Full history
    semantic @1;      # Vector embeddings
    episodic @2;      # Event-based
    hybrid @3;        # Combined
    reserved @4;      # Reserved for future use
    custom @5;
}

struct HandoffConfig {
    enabled @0 :Bool;
    targetAgents @1 :List(AgentId);
    triggerConditions @2 :List(Text);
    custom @3 :Data;
}

struct AgentState {
    id @0 :AgentId;
    spec @1 :AgentSpec;
    status @2 :AgentStatus;
    currentTask @3 :Text;
    memoryUsage @4 :UInt64;
    createdAt @5 :T.Timestamp;
    lastActive @6 :T.Timestamp;
}

enum AgentStatus {
    idle @0; running @1; waiting @2; paused @3; error @4; terminated @5; custom @6;
}

struct AgentMessage {
    from @0 :AgentId;
    to @1 :AgentId;
    content @2 :T.DataHandle;  # JSON or custom
    messageType @3 :MessageType;
    replyTo @4 :RequestId;
    custom @5 :Data;
}

enum MessageType {
    task @0; result @1; handoff @2; query @3; event @4; custom @5;
}

interface AgentService {
    spawn @0 (spec :AgentSpec) -> (agent :AgentId);
    terminate @1 (agent :AgentId, graceful :Bool) -> T.VoidResult;
    sendMessage @2 (msg :AgentMessage) -> (reply :AgentMessage);
    getState @3 (agent :AgentId) -> (state :AgentState);
    list @4 (filter :AgentFilter, page :T.Pagination) -> (agents :List(AgentState), total :UInt64);
    
    # Multi-agent coordination
    createSwarm @5 (spec :SwarmSpec) -> (swarm :SwarmId);
    broadcast @6 (swarm :SwarmId, msg :AgentMessage) -> T.VoidResult;
    getSwarmState @7 (swarm :SwarmId) -> (state :SwarmState);
}

struct SwarmSpec {
    name @0 :Text;
    agents @1 :List(AgentId);
    topology @2 :SwarmTopology;
    coordinator @3 :AgentId;  # Optional central coordinator
    custom @4 :Data;
}

enum SwarmTopology {
    star @0; mesh @1; ring @2; hierarchical @3; custom @4;
}

struct SwarmState {
    id @0 :SwarmId;
    spec @1 :SwarmSpec;
    agents @2 :List(AgentState);
    status @3 :SwarmStatus;
}

enum SwarmStatus {
    forming @0; active @1; converging @2; completed @3; failed @4; custom @5;
}

struct SwarmId { id @0 :UInt64; }

struct AgentFilter {
    status @0 :AgentStatus;
    namePattern @1 :Text;
    model @2 :ModelId;
}

# ── RAG & Knowledge (Abstract - Backend Decides Implementation) ───
struct KnowledgeBaseSpec {
    name @0 :Text;
    embeddingModel @1 :ModelId;
    chunkingStrategy @2 :ChunkingStrategy;
    custom @3 :Data;
}

struct ChunkingStrategy {
    type @0 :ChunkingType;
    chunkSize @1 :UInt32;
    overlap @2 :UInt32;
    custom @3 :Data;
}

enum ChunkingType {
    fixed @0; semantic @1; recursive @2; agentic @3; custom @4;
}

interface KnowledgeBase {
    create @0 (spec :KnowledgeBaseSpec) -> (kb :KnowledgeBaseId);
    delete @1 (kb :KnowledgeBaseId) -> T.VoidResult;
    addDocuments @2 (kb :KnowledgeBaseId, docs :List(Document)) -> (ids :List(DocumentId));
    deleteDocuments @3 (kb :KnowledgeBaseId, ids :List(DocumentId)) -> T.VoidResult;
    query @4 (kb :KnowledgeBaseId, query :Query) -> (results :List(QueryResult));
    hybridQuery @5 (kb :KnowledgeBaseId, query :HybridQuery) -> (results :List(QueryResult));
}

struct Document {
    id @0 :DocumentId;
    content @1 :Text;
    metadata @2 :T.StringMap;
    embeddings @3 :List(Float32);  # Pre-computed optional
}

struct DocumentId { id @0 :UInt64; }
struct KnowledgeBaseId { id @0 :UInt64; }

struct Query {
    text @0 :Text;
    topK @1 :UInt32;
    filter @2 :T.StringMap;
    scoreThreshold @3 :Float32;
}

struct HybridQuery {
    textQuery @0 :Text;
    vectorQuery @1 :List(Float32);
    alpha @2 :Float32;  # Weight for vector vs keyword
    topK @3 :UInt32;
    filter @4 :T.StringMap;
}

struct QueryResult {
    document @0 :Document;
    score @1 :Float32;
    rank @2 :UInt32;
}

# ── Conversations & Context ───────────────────────────────────────
struct ConversationSpec {
    model @0 :ModelId;
    systemPrompt @1 :Text;
    tools @2 :List(ToolId);
    memoryConfig @3 :MemoryConfig;
    metadata @4 :T.StringMap;
}

struct Conversation {
    id @0 :ConversationId;
    spec @1 :ConversationSpec;
    messages @2 :List(ChatMessage);
    createdAt @3 :T.Timestamp;
    updatedAt @4 :T.Timestamp;
    tokenCount @5 :UInt32;
    metadata @6 :T.StringMap;
}

interface ConversationService {
    create @0 (spec :ConversationSpec) -> (conv :ConversationId);
    get @1 (conv :ConversationId) -> (conversation :Conversation);
    addMessage @2 (conv :ConversationId, msg :ChatMessage) -> T.VoidResult;
    fork @3 (conv :ConversationId, fromMessage :UInt32) -> (newConv :ConversationId);
    delete @4 (conv :ConversationId) -> T.VoidResult;
    list @5 (filter :ConversationFilter, page :T.Pagination) -> (convs :List(Conversation), total :UInt64);
    compress @6 (conv :ConversationId, strategy :CompressionStrategy) -> T.VoidResult;
}

enum CompressionStrategy {
    summarize @0; truncate @1; slidingWindow @2; custom @3;
}

struct ConversationFilter {
    model @0 :ModelId;
    since @1 :T.Timestamp;
    metadataFilter @2 :T.StringMap;
}

# ── Events & Subscriptions (Standard Pull-based UInt64) ───────────
struct AIEvent {
    union {
        tokenGenerated @0 :TokenEvent;
        toolInvoked @1 :ToolEvent;
        modelLoaded @2 :ModelEvent;
        agentSpawned @3 :AgentEvent;
        conversationUpdated @4 :ConversationEvent;
        errorOccurred @5 :T.Error;
        unknown @6 :UnknownAIEvent;  # Forward compatibility
    }
}

struct UnknownAIEvent {
    typeId @0 :UInt64;
    payload @1 :Data;
}

struct TokenEvent {
    requestId @0 :RequestId;
    token @1 :Text;
    index @2 :UInt32;
}
struct ToolEvent {
    requestId @0 :RequestId;
    tool @1 :ToolId;
    success @2 :Bool;
}
struct ModelEvent {
    model @0 :ModelId;
    eventType @1 :ModelEventType;
}
enum ModelEventType {
    loaded @0;
    unloaded @1;
    error @2;
}
struct AgentEvent {
    agent @0 :AgentId;
    eventType @1 :AgentEventType;
}
enum AgentEventType {
    spawned @0;
    terminated @1;
    handoff @2;
    error @3;
}
struct ConversationEvent {
    conversation @0 :ConversationId;
    eventType @1 :ConversationEventType;
}
enum ConversationEventType {
    created @0;
    messageAdded @1;
    compressed @2;
    deleted @3;
}

interface AISubscription {
    pull @0 () -> (events :List(AIEvent));
    cancel @1 () -> T.VoidResult;
}

# ── Capability-Gated Methods (All privileged ops require Capability) ─
# Pattern from capability.capnp:
# loadModel @0 (cap :Capability, spec :ModelSpec) -> (model :ModelId);
# spawnAgent @0 (cap :Capability, spec :AgentSpec) -> (agent :AgentId);