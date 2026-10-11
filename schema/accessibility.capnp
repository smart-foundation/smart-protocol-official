@0xa1b2c3d4e5f6000c;

# ═══════════════════════════════════════════════════════════════════════
# Accessibility - tree traversal, node inspection, action execution,
# and event streaming for assistive technologies.
#
# 2026-10-10 integration pass — three names disambiguated (a tree-state
# change, an event subscription and a tree export all shared names with
# discovery, usb and vcard):
#   - StateChange -> AccessibilityStateChange (discovery owns
#     ServiceStateChange).
#   - EventSubscription -> AccessibilityEventSubscription (usb owns
#     UsbEventSubscription).
#   - ExportResult -> AccessibilityExportResult (vcard owns
#     VcardExportResult).
# WHAT THIS IS
#   The contract between UI toolkits and assistive tech (screen readers,
#   switch control, voice control, magnifiers). It is backend-agnostic: the
#   same schema works on Linux (AT-SPI), macOS (NSAccessibility), Windows
#   (UIA), and custom compositors.
#
# The tree is lazy: children are IDs, not inline objects. Assistive tech
# fetches only what it needs. Deltas are incremental. Traversal is paginated.
# This is the model the rest of the protocol should copy, and it is unchanged
# here apart from the fixes below.
#
# WAI-ARIA IS GONE FROM THE REQUIRED POSITION
#   `AriaProperties` and the four methods that read and wrote it made a W3C
#   WEB DOCUMENT mechanism a required vocabulary of the universal contract.
#   The Swap Test fails on it: swapping a webview backend for an AR/VR HMI
#   backend requires EMULATING ARIA semantics the backend does not possess
#   (`current: step`, `owns`, `hasPopup: listbox`), and a non-web AT (voice
#   control on a car cluster) must map its model onto web roles. This file's
#   own header promises AT-SPI/NSAccessibility/UIA neutrality and then bolted
#   on ARIA. All of it is deleted; only `NodeRelationship` survives, as the
#   neutral relationship form with an open type token. Web-backed UIs map
#   ARIA onto the neutral node model — which they must do to serve any other
#   AT anyway.
#
# WHAT ELSE WAS FIXED
#   - `exportTreeJson` returned the whole tree as inline `Text` — the file's
#     own lazy design undone for the one call where trees are largest. A
#     50k-node spreadsheet returned megabytes of JSON allocated whole on both
#     ends. It is now a buffer reference.
#   - `getSelectedText` returned the whole selection inline. A "select all" in
#     a large document copied the entire document. It is now a handle plus the
#     range, so the caller reads what it needs.
#   - `NodePropertyChange` set node fields as TEXT PAIRS: a boolean became
#     "true"/"false" by convention, a number became "42", and every backend
#     and every client agreed on nothing. It is now `T.MetaValue`, and
#     `batchUpdate` reports a per-update result, so "node 4 failed" is
#     answerable instead of "the batch failed".
#   - There were TWO politeness scales: `LiveRegionMode {off, polite,
#     assertive}` and `AriaLive {off, polite, assertive, rude}`. One scale,
#     one home — `rude` folded in.
#   - ROOT DISCOVERY, previously a fork with every new backend: nothing said
#     how a consumer found the root of an app's tree. `getRoot` now does, and
#     node-id issuance is stated: ids are APP-issued and stable for the life
#     of the node; the compositor binds a surface to a root through
#     `Compositor.Session.updateAccessibilityTree`.
#   - `simulateEvent` took an `AccessibilityActionType`, which is an action
#     vocabulary, not an event one. It now takes an open event-kind token.
#
# ON `AccessibilityRole` (70 values)
#   Kept deliberately. Cross-platform AT interop genuinely needs a shared
#   vocabulary — that IS its interop purpose — and it has `custom @69`. A
#   parallel open token would create two naming systems, which is the defect
#   this rewrite removes elsewhere. Recorded in the batch report as a
#   considered decision rather than an oversight.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

interface AccessibilityService {
    # Fetch the subtree rooted at a node.
    getTree @0 (rootId :T.AccessNodeId) -> (result :TreeResult);

    # Subscribe to tree structure changes (child added/removed, node destroyed).
    subscribeTree @1 (rootId :T.AccessNodeId) -> (subscription :TreeSubscription);
    pullTree @2 (subscription :TreeSubscription) -> (delta :TreeDelta);
    cancelTree @3 (subscription :TreeSubscription) -> T.VoidResult;

    # Subscribe to accessibility events (focus, announcement, alert, value).
    subscribeEvents @4 () -> (subscription :AccessibilityEventSubscription);
    pullEvents @5 (maxEvents :UInt32) -> (events :List(AccessibilityEvent));
    cancelEvents @6 (subscription :AccessibilityEventSubscription) -> T.VoidResult;

    # Execute an action on a node. An unsupported action returns
    # `T.ErrorCode.notSupported`, so a consumer can degrade instead of retry.
    performAction @7 (nodeId :T.AccessNodeId, action :AccessibilityAction)
                  -> T.VoidResult;

    # Get the currently focused node.
    getFocusedNode @8 () -> (result :TreeResult);

    # Set focus to a specific node.
    setFocus @9 (nodeId :T.AccessNodeId) -> T.VoidResult;

    # Get selected text within a node (for text-input, staticText, etc).
    # A buffer reference plus the range, so a "select all" in a large
    # document does not copy the document.
    getSelectedText @10 (nodeId :T.AccessNodeId)
                     -> (result :SelectedTextResult);

    # Set text selection range within a node.
    setSelection @11 (nodeId :T.AccessNodeId, range :TextRange) -> T.VoidResult;

    # Query user accessibility preferences. This is THE preference contract;
    # theme.capnp reports the active theme, not the user's preferences.
    getPreferences @12 () -> (preferences :AccessibilityPreferences);

    # Get node relationships (parent, siblings, flows).
    getRelationships @13 (nodeId :T.AccessNodeId)
                      -> (relationships :NodeRelationships);

    # Get text attributes (inline formatting) for a text node.
    getTextAttributes @14 (nodeId :T.AccessNodeId, range :TextRange)
                      -> (attributes :List(TextAttribute));

    # Get the accessibility tree as a flat list (for linear navigation).
    getFlatTree @15 (rootId :T.AccessNodeId, pagination :T.Pagination)
                -> (nodes :List(AccessibilityNode), total :UInt64);

    # Export accessibility tree as a buffer for debugging. The content type
    # is declared by the caller, so the export is not frozen to JSON.
    exportTreeJson @16 (rootId :T.AccessNodeId, format :T.MimeType)
                    -> (result :AccessibilityExportResult);

    # Batch update multiple nodes. Per-update results, so partial success is
    # visible instead of "the batch failed, re-fetch the world".
    batchUpdate @17 (updates :List(NodeUpdate)) -> (result :BatchUpdateResult);

    # Simulate accessibility events for testing. `eventKind` is an open
    # token — it is an event kind, not an action.
    simulateEvent @18 (nodeId :T.AccessNodeId, eventKind :Text) -> T.VoidResult;

    # Discover the root of a surface's tree. Node ids are app-issued and
    # stable for the life of the node; this returns the binding the compositor
    # recorded for the surface.
    getRoot @19 (surface :T.SurfaceId) -> (result :RootResult);
}

# ── Results ───────────────────────────────────────────────────

struct TreeResult {
    union {
        node    @0 :AccessibilityNode;
        # No tree is published for this node/surface. An answer, not a fault.
        none    @1 :Void;
        error   @2 :T.Error;
        unknown @3 :Void;
    }
}

struct RootResult {
    union {
        root    @0 :T.AccessNodeId;
        none    @1 :Void;
        error   @2 :T.Error;
        unknown @3 :Void;
    }
}

struct SelectedTextResult {
    union {
        selection @0 :SelectedText;
        none      @1 :Void;
        error     @2 :T.Error;
        unknown   @3 :Void;
    }
}

struct SelectedText {
    # The selection itself: a buffer reference, because a "select all" in a
    # large document must not copy the document.
    text  @0 :T.DataHandle;
    # The range the text was read from.
    range @1 :TextRange;
    metadata @2 :T.StringMap;
}

struct AccessibilityExportResult {
    union {
        export  @0 :TreeExport;
        error   @1 :T.Error;
        unknown @2 :Void;
    }
}

struct TreeExport {
    # The exported tree, in the requested content type. A buffer reference:
    # the file's lazy design does not end at the largest structure.
    data      @0 :T.DataHandle;
    format    @1 :T.MimeType;
    nodeCount @2 :UInt64;
    metadata @3 :T.StringMap;
}

struct BatchUpdateResult {
    # One entry per submitted update, in the submitted order.
    results @0 :List(NodeUpdateResult);
    metadata @1 :T.StringMap;
}

struct NodeUpdateResult {
    union {
        ok      @0 :Void;
        error   @1 :T.Error;
        unknown @2 :Void;
    }
}

# Audit-9: batch node update for multi-change updates.
struct NodeUpdate {
    nodeId @0 :T.AccessNodeId;
    changes @1 :List(NodePropertyChange);
}

# Typed, not text: a boolean is a boolean and a number is a number, so no
# backend has to agree on how "true" is spelled.
struct NodePropertyChange {
    field @0 :Text;
    value @1 :T.MetaValue;
}

interface TreeSubscription {
    pull @0 () -> (delta :TreeDelta);
    cancel @1 () -> T.VoidResult;
}

interface AccessibilityEventSubscription {
    pull @0 (maxEvents :UInt32) -> (events :List(AccessibilityEvent));
    cancel @1 () -> T.VoidResult;
}

# ── Text Range ────────────────────────────────────────────────

struct TextRange {
    start @0 :UInt32;
    end @1 :UInt32;
    # Granularity of the range (for granular selection operations).
    granularity @2 :TextGranularity;
}

enum TextGranularity {
    # Absent means the backend decides; it must never mean a
    # specific paradigm value.
    unspecified @0;
    character @1;
    word @2;
    line @3;
    sentence @4;
    paragraph @5;
    all @6;
    custom @7;
}

# ── Text Attribute ───────────────────────────────────────────

struct TextAttribute {
    # Character offset where this attribute starts.
    offset @0 :UInt32;
    # Length of the attribute run.
    length @1 :UInt32;
    # The attribute kind.
    kind @2 :TextAttributeKind;
    # Attribute value (bool for flags, text for links, int for size).
    value @3 :TextAttributeValue;
}

enum TextAttributeKind {
    bold @0;
    italic @1;
    underline @2;
    strikethrough @3;
    link @4;
    fontSize @5;
    fontFamily @6;
    foregroundColor @7;
    backgroundColor @8;
    role @9;
    custom @10;
}

struct TextAttributeValue {
    union {
        bool @0 :Bool;
        text @1 :Text;
        integer @2 :UInt32;
        custom @3 :T.StringMap;
        unknown @4 :Void;
    }
}

# ── Node Relationships ───────────────────────────────────────

# The neutral relationship form. `type` is an open token, which is what lets a
# relationship kind invented later be expressed — and it is why the ARIA
# property model was removable rather than merely moved.
struct NodeRelationships {
    nodeId @0 :T.AccessNodeId;
    parent @1 :T.AccessNodeId;
    siblings @2 :List(T.AccessNodeId);
    # Logical flow: what comes next/previous in reading order.
    nextInFlow @3 :T.AccessNodeId;
    previousInFlow @4 :T.AccessNodeId;
    # Controlled elements (for combobox -> listbox relationships).
    controlledElements @5 :List(T.AccessNodeId);
    # Details element.
    detailsElement @6 :T.AccessNodeId;
    # Error message element.
    errorMessage @7 :T.AccessNodeId;
    # Additional relationships, keyed by an open type token.
    others @8 :List(NodeRelationship);
}

struct NodeRelationship {
    # Relationship type, e.g. "related", "group", "flow".
    type @0 :Text;
    # Target node IDs for this relationship.
    targets @1 :List(T.AccessNodeId);
    metadata @2 :T.StringMap;
}

# ── Tree Model ───────────────────────────────────────────────

struct AccessibilityNode {
    id @0 :T.AccessNodeId;
    role @1 :AccessibilityRole;
    name @2 :Text;
    description @3 :Text;
    state @4 :AccessibilityState;
    bounds @5 :T.Rect;
    coordinateSpace @6 :CoordinateSpace;
    actions @7 :List(AccessibilityAction);
    children @8 :List(T.AccessNodeId);
    # Explicit reading/traversal order (differs from visual order in
    # multi-column layouts).
    readingOrder @9 :List(T.AccessNodeId);
    attributes @10 :T.StringMap;
    # Live region mode for dynamic content (chat messages, timers, status bars).
    liveRegion @11 :LiveRegionMode;
    # Text value (for input fields, text nodes).
    value @12 :Text;
    # Minimum value (for sliders, progress bars).
    minValue @13 :Float32;
    # Maximum value (for sliders, progress bars).
    maxValue @14 :Float32;
    # Current value as float (for numeric controls).
    numericValue @15 :Float32;
    # Placeholder text (for input fields).
    placeholder @16 :Text;
    # Error message node ID.
    errorNodeId @17 :T.AccessNodeId;
    # Keyboard shortcut (e.g. "Ctrl+S").
    keyboardShortcut @18 :Text;
}

enum CoordinateSpace {
    screen @0;
    window @1;
    parent @2;
    content @3;
    custom @4;
}

# ONE politeness scale. `rude` was folded in from the deleted ARIA live
# model, so a live region can be announced at full severity.
enum LiveRegionMode {
    off @0;
    polite @1;
    assertive @2;
    rude @3;
    custom @4;
}

# ── Tree Deltas (incremental updates) ────────────────────────

struct TreeDelta {
    nodeId @0 :T.AccessNodeId;
    changes @1 :List(TreeChange);
}

struct TreeChange {
    union {
        childAdded @0 :ChildAddedChange;
        childRemoved @1 :ChildRemovedChange;
        stateChanged @2 :AccessibilityStateChange;
        boundsChanged @3 :BoundsChange;
        nameChanged @4 :NameChange;
        descriptionChanged @5 :DescriptionChange;
        destroyed @6 :Void;
        valueChanged @7 :ValueChange;
        custom @8 :T.StringMap;
        unknown @9 :Void;
    }
}

struct ChildAddedChange {
    childId @0 :T.AccessNodeId;
    index @1 :UInt32;
}

struct ChildRemovedChange {
    childId @0 :T.AccessNodeId;
}

struct AccessibilityStateChange {
    previous @0 :AccessibilityState;
    current @1 :AccessibilityState;
}

struct BoundsChange {
    previous @0 :T.Rect;
    current @1 :T.Rect;
}

struct NameChange {
    previous @0 :Text;
    current @1 :Text;
}

struct DescriptionChange {
    previous @0 :Text;
    current @1 :Text;
}

struct ValueChange {
    previous @0 :Text;
    current @1 :Text;
}

# ── Accessibility Events ─────────────────────────────────────

struct AccessibilityEvent {
    union {
        focusChanged @0 :FocusChangedEvent;
        stateChanged @1 :StateChangedEvent;
        announcement @2 :AnnouncementEvent;
        alert @3 :AlertEvent;
        treeChanged @4 :TreeChangedEvent;
        valueChanged @5 :ValueChangedEvent;
        selectionChanged @6 :SelectionChangedEvent;
        scrolled @7 :ScrolledEvent;
        unknown @8 :T.UnknownEvent;
    }
}

struct FocusChangedEvent {
    previous @0 :T.AccessNodeId;
    current @1 :T.AccessNodeId;
    timestamp @2 :T.Timestamp;
}

struct StateChangedEvent {
    nodeId @0 :T.AccessNodeId;
    state @1 :AccessibilityState;
    timestamp @2 :T.Timestamp;
}

struct AnnouncementEvent {
    nodeId @0 :T.AccessNodeId;
    message @1 :Text;
    politeness @2 :LiveRegionMode;
    timestamp @3 :T.Timestamp;
}

struct AlertEvent {
    nodeId @0 :T.AccessNodeId;
    message @1 :Text;
    timestamp @2 :T.Timestamp;
}

struct TreeChangedEvent {
    rootId @0 :T.AccessNodeId;
    timestamp @1 :T.Timestamp;
}

struct ValueChangedEvent {
    nodeId @0 :T.AccessNodeId;
    previousValue @1 :Text;
    currentValue @2 :Text;
    timestamp @3 :T.Timestamp;
}

struct SelectionChangedEvent {
    nodeId @0 :T.AccessNodeId;
    range @1 :TextRange;
    timestamp @2 :T.Timestamp;
}

struct ScrolledEvent {
    nodeId @0 :T.AccessNodeId;
    position @1 :T.Rect;
    timestamp @2 :T.Timestamp;
}

# ── Roles ─────────────────────────────────────────────────────

enum AccessibilityRole {
    unknown @0;
    window @1;
    dialog @2;
    menuBar @3;
    popupMenu @4;
    menuItem @5;
    button @6;
    checkBox @7;
    radioButton @8;
    slider @9;
    table @10;
    tableRow @11;
    tableCell @12;
    link @13;
    list @14;
    listItem @15;
    paragraph @16;
    staticText @17;
    image @18;
    video @19;
    audio @20;
    scrollView @21;
    tabGroup @22;
    tab @23;
    input @24;
    textInput @25;
    toggle @26;
    switch @27;
    progressBar @28;
    busyIndicator @29;
    colorChooser @30;
    dateEditor @31;
    tree @32;
    treeItem @33;
    webView @34;
    application @35;
    alert @36;
    header @37;
    footer @38;
    combobox @39;
    menu @40;
    toolbar @41;
    statusBar @42;
    separator @43;
    group @44;
    grid @45;
    gridCell @46;
    tooltip @47;
    spinButton @48;
    tabList @49;
    tabPanel @50;
    figure @51;
    caption @52;
    term @53;
    definition @54;
    feed @55;
    note @56;
    suggestion @57;
    contentDeletion @58;
    contentInsertion @59;
    searchBox @60;
    meter @61;
    option @62;
    document @63;
    log @64;
    alertdialog @65;
    buttonGroup @66;
    columnHeader @67;
    rowHeader @68;
    custom @69;
}

# ── State ─────────────────────────────────────────────────────

struct AccessibilityState {
    focused @0 :Bool;
    selected @1 :Bool;
    checked @2 :Bool;
    indeterminate @3 :Bool;
    expanded @4 :Bool;
    collapsed @5 :Bool;
    busy @6 :Bool;
    readOnly @7 :Bool;
    password @8 :Bool;
    multiLine @9 :Bool;
    dismissable @10 :Bool;
    editable @11 :Bool;
    visible @12 :Bool;
    visited @13 :Bool;
    modal @14 :Bool;
    required @15 :Bool;
    invalid @16 :Bool;
    highlighted @17 :Bool;
    collapsedByUser @18 :Bool;
    autoplay @19 :Bool;
    expandedByUser @20 :Bool;
    selectedFromFocus @21 :Bool;
    hovered @22 :Bool;
    active @23 :Bool;
    enlarged @24 :Bool;
    dimmed @25 :Bool;
}

# ── Actions ───────────────────────────────────────────────────

struct AccessibilityAction {
    type @0 :AccessibilityActionType;
    name @1 :Text;
    description @2 :Text;
    # Parameters for parameterized actions (scroll-to-position, set-value,
    # select-range).
    parameters @3 :T.StringMap;
    typedParams @4 :TypedActionParams;
}

struct TypedActionParams {
    union {
        scrollToPoint @0 :ScrollToPointParams;
        setValue @1 :SetValueParams;
        selectRange @2 :SelectRangeParams;
        custom @3 :T.StringMap;
        unknown @4 :Void;
    }
}

struct ScrollToPointParams {
    x @0 :Int32;
    y @1 :Int32;
}

struct SetValueParams {
    value @0 :Text;
}

struct SelectRangeParams {
    start @0 :UInt32;
    end @1 :UInt32;
}

enum AccessibilityActionType {
    press @0;
    longPress @1;
    scrollUp @2;
    scrollDown @3;
    scrollLeft @4;
    scrollRight @5;
    select @6;
    clearSelection @7;
    addToSelection @8;
    removeFromSelection @9;
    setValue @10;
    increment @11;
    decrement @12;
    showContextMenu @13;
    focus @14;
    activate @15;
    showTooltip @16;
    hideTooltip @17;
    scrollToPoint @18;
    showOnScreen @19;
    accessibilityFocus @20;
    dismiss @21;
    drag @22;
    expand @23;
    collapse @24;
    custom @25;
}

# ── Preferences ──────────────────────────────────────────────

struct AccessibilityPreferences {
    textScale @0 :Float32;
    reducedMotion @1 :Bool;
    highContrast @2 :Bool;
    screenReaderActive @3 :Bool;
    invertColors @4 :Bool;
    reduceTransparency @5 :Bool;
    boldText @6 :Bool;
    monoAudio @7 :Bool;
    captionsEnabled @8 :Bool;
    captionStyle @9 :CaptionStyle;
    screenMagnifierEnabled @10 :Bool;
    magnifierScale @11 :Float32;
    switchControlEnabled @12 :Bool;
    voiceControlEnabled @13 :Bool;
    reduceWhitePoint @14 :Bool;
    pointerControlEnabled @15 :Bool;
    stickyKeys @16 :Bool;
    slowKeys @17 :Bool;
    bounceKeys @18 :Bool;
    caretBlinkRate @19 :UInt32;
    doubleClickDelay @20 :UInt32;
}

enum CaptionStyle {
    default @0;
    whiteOnBlack @1;
    yellowOnBlack @2;
    yellowOnBlue @3;
    custom @4;
}
