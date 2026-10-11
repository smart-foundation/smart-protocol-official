@0xa1b2c3d4e5f6001f;

# ══════════════════════════════════════════════════════════════════════
# CLI — command execution and command introspection for the `smart` shell.
#
# WHAT THIS IS
#   The execution service and the registry a command-line client reads. It
#   executes synchronously, in the background, as a stream, as a pipeline, or
#   interactively; and it tells a client WHICH commands exist, which of them
#   cannot currently run and why, and where the grammar lives.
#
# THE COMMAND MODEL — derived from the schema tree, not a parallel table
#   A command is a thin surface over an EXISTING SERVICE CONTRACT. A
#   registration therefore records which schema it routes through
#   (`T.SchemaId`) and which interface and method on it — never a hand-written
#   permission string and never an opaque method number. Because the binding
#   is schema identity, a command line is generatable from the schemas:
#   adding a service adds its commands by declaring a schema.
#
#   Authority follows the same rule. Holding the capability for the service a
#   command routes to IS the authority to run it; nothing here interrogates a
#   permission per call, and no registration carries a capability token.
#   `checkPermission @11` was deleted for exactly that reason.
#
# WHAT WAS DELETED, AND WHAT REPLACED IT
#   - `checkPermission` (per-call authority by command name) — deleted.
#     Authority is the reference held at acquisition.
#   - `getJobStatus @2` and `pollPrompt @16` (polling loops) — deleted.
#     Replaced by `subscribeJob` and by `InteractiveSession.pull`, which
#     deliver events with a structural terminator instead of being asked.
#   - `createScript` and the `CommandScript`/`CommandScriptStep` mini shell
#     language — deleted. `executePipeline` is the one composition model in
#     this file; running a script file is the interpreter surface's job
#     (shell.capnp `ShellService.runScript`).
#   - `getHistoryAnalytics` and `CommandHistoryAnalytics` — deleted, which
#     also ends the name collision with shell.capnp. Per-invocation history
#     (`getHistory`) is the honest record; usage analytics is a diagnostics
#     concern.
#   - `sendInput @15` — moved onto `InteractiveSession`. The session
#     reference is the handle, so there is no `sessionId :Text` to collide.
#   - `PipeMode.redirect`/`append` — deleted. They named a redirection target
#     no field anywhere could carry, so a backend had to invent one.
#   - `CommandOutputFormat` (raw/utf8/json/yaml/xml) — replaced by
#     `T.MimeType`. A closed list of serialization formats is the doctrine's
#     `logging.capnp LogFormat` anti-pattern; an open content type lets a
#     2046 format be requested with no schema change.
#   - The local `ResourceLimits` — replaced by `T.Quota`, the protocol's one
#     quota primitive (it was a third rival beside types.capnp's Quota and
#     compositor.capnp's ResourceLimits).
#   - `InteractiveInputType` (closed enum) — replaced by an open token, so a
#     prompt kind invented later is routable and matches ime.capnp's fix.
#
# WHAT WAS KEPT EXACTLY
#   `execute`, `spawnBackground`, `killJob`, history, `executeStreaming`,
#   aliases, `executePipeline`, `executeInteractive`, and every
#   `T.DataHandle` on stdin/stdout/stderr. The execution discipline in this
#   file was already right.
#
# The registry enumeration methods (`listCommands`, `listUnavailable`,
# `getSyntax`) are imported from the working tree's live design, with the
# binding re-specced as schema identity and the per-command capability
# string removed.
# ══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

interface CliService {
    # Execute a command synchronously and return the result.
    execute @0 (request :CommandRequest) -> (result :CommandResult);

    # Execute a command in the background, returning a job handle.
    spawnBackground @1 (request :CommandRequest) -> (jobId :T.JobId);

    # Terminate a background job.
    killJob @2 (jobId :T.JobId) -> T.VoidResult;

    # Observe a background job. This replaces `getJobStatus`, which every
    # shell polled in a loop.
    subscribeJob @3 (jobId :T.JobId) -> (subscription :JobSubscription);

    # Command history with pagination.
    getHistory @4 (pagination :T.Pagination)
                -> (entries :List(CommandHistoryEntry), total :UInt64);
    clearHistory @5 () -> T.VoidResult;

    # Tab-completion suggestions for a partial input. Completions are the
    # strings a user types; the schema-derived detail behind them comes from
    # `listCommands` and `getSyntax`.
    getCompletions @6 (partial :Text) -> (completions :List(Text));

    # Descriptive metadata for a command (help text, arguments, options) and
    # the schema contract it routes through.
    getCommandInfo @7 (commandPath :Text) -> (result :CommandInfoResult);

    # Execute with streaming stdout/stderr.
    executeStreaming @8 (request :CommandRequest) -> (stream :StreamingOutput);

    # List command aliases.
    listAliases @9 () -> (aliases :List(CommandAlias));

    # Execute a command pipeline (stdout -> stdin). The ONE composition
    # model in this file.
    executePipeline @10 (steps :List(CommandPipelineStep)) -> (result :CommandResult);

    # Execute a command interactively. Returns the session reference, which
    # is both the handle and the authority to send input.
    executeInteractive @11 (request :CommandRequest) -> (session :InteractiveSession);

    # ─── Command registry ─────────────────────────────────────────
    # The registry is the authority on what commands exist and what each one
    # needs. A client that guesses is a client that lies: "help" must not
    # list a command that cannot run, and the reason it cannot run must be
    # nameable, not "unknown".
    #
    # These take no `command` string and return a whole list. A per-command
    # accessor already exists (`getCommandInfo @7`); these are the
    # registry-wide views.

    # Every registered command, with what it takes to run.
    listCommands @12 (pagination :T.Pagination)
                 -> (commands :List(CommandRegistration), total :UInt64);

    # Registered commands that cannot currently run, and why.
    listUnavailable @13 (pagination :T.Pagination)
                    -> (commands :List(CommandRegistration), total :UInt64);

    # The grammar a client parses user input against.
    getSyntax @14 () -> (syntax :SyntaxReference);
}

# ══════════════════════════════════════════════════════════════════════
# COMMAND REGISTRY
# ══════════════════════════════════════════════════════════════════════

# One registered command, and what it takes to run it.
#
# This is a REGISTRATION, not an invocation result: it is answerable without
# running anything.
struct CommandRegistration {
    # The path the user types, e.g. "system info" or "ps -a". The full
    # command line including its subcommand — `command` alone would be
    # ambiguous the moment a command has subcommands.
    commandPath @0 :Text;

    # The schema this command routes through. The shell is generated FROM the
    # schemas, so the binding is schema identity: a new service gains its
    # commands by declaring a schema, not by editing a table here.
    schemaId @1 :T.SchemaId;

    # Interface and method within that schema, as the schema spells them
    # (e.g. "Audio", "setVolume"). Text, because the schema tree is the
    # naming authority; a numeric method id would be an enum by another name
    # with no published domain.
    interfaceName @2 :Text;
    methodName @3 :Text;

    # How this command should be presented — grouping, ordering, one-line
    # summary. Kept out of `CommandInfo` because presentation is a property
    # of the command's place in the registry, not of its arguments.
    presentation @4 :CommandPresentation;

    # Why this command is not currently runnable, when it is not. Empty when
    # it is runnable — never a placeholder string standing in for an answer.
    unavailableReason @5 :AvailabilityReason;
    metadata @6 :T.StringMap;
}

# Authority note: a registration carries NO capability string. The authority
# to run a command is the capability held for the service it routes to, which
# is checked once at acquisition of that service — not per command, and not
# by name. `capabilityDenied` below reports the outcome of that check.

struct CommandPresentation {
    # Domain this command belongs to ("system", "process", "storage").
    domain @0 :Text;
    # Human one-line summary for help listings.
    summary @1 :Text;
    # Sort key within the domain. Lower sorts first.
    order @2 :UInt32;
    # Whether a bare invocation (no arguments) is meaningful, so a client can
    # decide whether to run it to see usage or refuse and ask for help.
    noArgsValid @3 :Bool;
    metadata @4 :T.StringMap;
}

# Why a command is not available. An enum, not a string, so a client can
# branch on it and so "we do not know" is a distinguishable state.
enum AvailabilityReason {
    # The command is available.
    available @0;
    # The caller lacks the capability the routing service requires.
    capabilityDenied @1;
    # A required backing service is not registered or not healthy. `detail`
    # names it.
    serviceUnavailable @2;
    # The command exists only on this platform or architecture.
    unsupportedPlatform @3;
    # The registry has no answer — explicitly distinct from every other case,
    # so a gap is visible rather than disguised as one of the above.
    unknown @4;
    # Held back deliberately by configuration.
    disabledByPolicy @5;
    custom @6;
}

# Where a client should look to learn the command grammar.
#
# The grammar is not inlined into this schema on purpose: the syntax is a
# property of the running system's command set, and duplicating it here would
# create a second authority that drifts. This points at the authority.
struct SyntaxReference {
    # Machine-readable grammar document (the CLI's own parser spec). Empty
    # only when the registry has no grammar to publish, which a client must
    # treat as "cannot validate input" rather than "anything is valid".
    grammar @0 :Text;

    # Version of the grammar document, so a client can tell whether its
    # cached copy is stale.
    version @1 :T.Version;

    # Domains the grammar covers. A client that knows a domain is missing can
    # say so instead of silently offering no completions for it.
    domains @2 :List(DomainInfo);
    metadata @3 :T.StringMap;
}

# One command domain ("system", "process", "storage", …).
struct DomainInfo {
    # Stable domain identifier, matching CommandPresentation.domain.
    id @0 :Text;
    # Human label for menus.
    label @1 :Text;
    # One-line description.
    description @2 :Text;
    # Registered commands in this domain.
    commandCount @3 :UInt32;
    # How many of those are currently unavailable.
    unavailableCount @4 :UInt32;
    metadata @5 :T.StringMap;
}

# ══════════════════════════════════════════════════════════════════════
# COMMANDS
# ══════════════════════════════════════════════════════════════════════

struct CommandRequest {
    # The command name or path. Backend resolves via its own search rules
    # (PATH-like resolution, alias tables, built-in commands).
    command @0 :Text;
    # Positional arguments.
    args @1 :List(Text);
    # Environment variables (key-value pairs).
    env @2 :T.StringMap;
    # Working directory. Backend interprets according to its filesystem model.
    cwd @3 :T.FilePath;
    # Standard input data. Use T.DataHandle for large payloads.
    stdin @4 :T.DataHandle;
    # Command timeout (zero = no timeout).
    timeout @5 :T.Duration;
    # How environment variables are handled.
    environmentMode @6 :EnvironmentMode;
    # Resource limits. T.Quota is the protocol's one quota primitive.
    resourceLimits @7 :T.Quota;
    # Requested output content type. Open, so a 2046 format needs no ordinal.
    outputFormat @8 :T.MimeType;
    # Workspace/directory context for the command.
    workspace @9 :CommandWorkspace;
}

struct CommandWorkspace {
    # Workspace name/identifier.
    name @0 :Text;
    # Workspace root path.
    root @1 :T.FilePath;
    # Workspace-specific environment overlay.
    env @2 :T.StringMap;
}

# How environment variables are handled. `inherit` is the zero member: an
# absent field must not silently REPLACE the caller's environment.
enum EnvironmentMode {
    inherit @0;
    replace @1;
    merge @2;
    clean @3;
}

# A step in a command pipeline.
struct CommandPipelineStep {
    # The command to execute.
    command @0 :Text;
    # Arguments for this step.
    args @1 :List(Text);
    # How stdout connects to the next step's stdin.
    pipeMode @2 :PipeMode;
}

# `redirect` and `append` were deleted: they named a redirection target that
# no field in the pipeline step could carry, so every backend invented one.
struct PipeMode {
    union {
        pipe @0 :Void;
        none @1 :Void;
        custom @2 :T.StringMap;
        unknown @3 :Void;
    }
}

struct CommandResult {
    # Structured exit status — no raw exit codes.
    exitStatus @0 :T.ExitStatus;
    # Standard output. Use T.DataHandle for potentially large output.
    output @1 :T.DataHandle;
    # Standard error. Use T.DataHandle for potentially large output.
    errorOutput @2 :T.DataHandle;
    # Wall-clock duration of command execution.
    duration @3 :T.Duration;
}

struct CommandHistoryEntry {
    command @0 :Text;
    timestamp @1 :T.Timestamp;
    exitStatus @2 :T.ExitStatus;
    duration @3 :T.Duration;
}

# ── Command metadata ──────────────────────────────────────────

struct CommandInfoResult {
    union {
        info @0 :CommandInfo;
        error @1 :T.Error;
        unknown @2 :Void;
    }
}

struct CommandInfo {
    # The registry entry: schema binding, presentation, availability.
    registration @0 :CommandRegistration;
    description @1 :Text;
    args @2 :List(CommandArg);
    options @3 :List(CommandOption);
}

struct CommandArg {
    name @0 :Text;
    description @1 :Text;
    required @2 :Bool;
    variadic @3 :Bool;
}

struct CommandOption {
    short @0 :Text;
    long @1 :Text;
    description @2 :Text;
    value @3 :Text;
    typedValue @4 :TypedOptionValue;
}

struct TypedOptionValue {
    union {
        bool @0 :Bool;
        int @1 :Int64;
        float @2 :Float64;
        text @3 :Text;
        list @4 :List(Text);
        custom @5 :T.StringMap;
        unknown @6 :Void;
    }
}

# A command alias mapping.
struct CommandAlias {
    # The alias name (e.g., "ll").
    name @0 :Text;
    # The target command and arguments.
    target @1 :Text;
    # Human-readable description.
    description @2 :Text;
}

# ── Streaming output ──────────────────────────────────────────

interface StreamingOutput {
    # Pull the next output chunk. `maxBytes` is caller-driven backpressure:
    # the producer may never send faster than the consumer pulls.
    pull @0 (maxBytes :UInt32) -> (chunk :OutputChunk);

    # Cancel the streaming output and terminate the command.
    cancel @1 () -> T.VoidResult;
}

# Output chunk from streaming execution.
struct OutputChunk {
    # The output data.
    data @0 :T.DataHandle;
    # Whether this chunk carries standard error (true) or standard output.
    isErrorOutput @1 :Bool;
    # Whether the command has finished.
    finished @2 :Bool;
    # Exit status (only present when finished = true).
    exitStatus @3 :T.ExitStatus;
}

# ── Jobs ──────────────────────────────────────────────────────

interface JobSubscription {
    pull @0 (maxEvents :UInt32) -> (events :List(JobEvent));
    cancel @1 () -> T.VoidResult;
}

# A job reports state changes instead of being asked for its status.
struct JobEvent {
    jobId @0 :T.JobId;
    union {
        started @1 :Void;
        completed @2 :CommandResult;
        failed @3 :T.Error;
        killed @4 :Void;
        unknown @5 :Void;
    }
    at @6 :T.MonotonicTimestamp;
    # Monotonic; detects dropped events.
    sequence @7 :UInt64;
}

# ── Interactive sessions ──────────────────────────────────────

# The session reference IS the handle and the authority. There is no
# `sessionId` to pass around, collide, or guess.
interface InteractiveSession {
    # Pull the next batch of session events: output, a prompt, or a
    # structural terminator. This replaces `pollPrompt`, which asked the same
    # question in a loop and woke the CPU to do it.
    pull @0 (maxEvents :UInt32) -> (events :List(InteractiveEvent));

    # Send user input to the session.
    sendInput @1 (input :InteractiveInput) -> T.VoidResult;

    # Terminate the session.
    cancel @2 () -> T.VoidResult;
}

struct InteractiveEvent {
    union {
        output @0 :OutputChunk;
        prompt @1 :InteractivePrompt;
        exited @2 :T.ExitStatus;
        unknown @3 :T.UnknownEvent;
    }
    at @4 :T.MonotonicTimestamp;
    # Monotonic; detects dropped events.
    sequence @5 :UInt64;
}

struct InteractiveInput {
    union {
        text @0 :Text;
        line @1 :Text;
        key @2 :InteractiveKey;
        custom @3 :T.StringMap;
        unknown @4 :Void;
    }
}

struct InteractiveKey {
    # Key name (e.g., "enter", "tab", "ctrl-c").
    name @0 :Text;
    # Whether a modifier key is held.
    ctrl @1 :Bool;
    alt @2 :Bool;
    shift @3 :Bool;
}

struct InteractivePrompt {
    # Prompt message (e.g., "Enter password: ").
    message @0 :Text;
    # Expected input kind — an OPEN token, so a prompt kind invented later is
    # expressible and routable. Matches ime.capnp's `ImeInputRequest.type`.
    # Conformance tokens are published at the end of this file.
    inputType @1 :Text;
    # Whether input is required (false = optional).
    required @2 :Bool;
}

# ══════════════════════════════════════════════════════════════════════
# CONFORMANCE TOKENS — conventions, NOT contract
#
# Nothing above depends on any value in this section. An unrecognised value
# MUST be ignored, never rejected. They are Text and deliberately NOT enums:
# an enum here would be an eternal commitment to today's spelling.
# ══════════════════════════════════════════════════════════════════════

const promptText     :Text = "text";
const promptPassword :Text = "password";
const promptConfirm  :Text = "confirm";
const promptChoice   :Text = "choice";
const promptPath     :Text = "path";
const promptNumber   :Text = "number";

const mimeJson    :T.MimeType = (type = "application", subtype = "json");
const mimeYaml    :T.MimeType = (type = "application", subtype = "yaml");
const mimeXml     :T.MimeType = (type = "application", subtype = "xml");
const mimeText    :T.MimeType = (type = "text", subtype = "plain");
const mimeBinary  :T.MimeType = (type = "application", subtype = "octet-stream");
const mimeCapnp   :T.MimeType = (type = "application", subtype = "capnp");
