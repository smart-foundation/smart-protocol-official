@0xa1b2c3d4e5f6000c;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Accessibility - tree traversal, node inspection, action execution,
# and event streaming for assistive technologies.
#
# This schema is the contract between UI toolkits and assistive tech
# (screen readers, switch control, voice control, magnifiers). It is
# backend-agnostic: the same schema works on Linux (AT-SPI), macOS
# (NSAccessibility), Windows (UIA), and custom compositors.
#
# The tree is lazy: children are IDs, not inline objects. Assistive
# tech fetches only what it needs.
#
# Audit-7 enhancements (zero-cost, info-density):
#   - Additional roles: grid, statusBar, tooltip, spinButton, tabList, etc.
#   - Additional actions: scrollToPoint, showOnScreen, drag, accessibilityFocus
#   - Additional state fields: highlighted, collapsedByUser, autoplay, etc.
#   - TextAttribute: inline formatting for rich text nodes
#   - AccessibilityPreferences additions: magnifier, switch control, etc.
#   - TextRange for selection operations with character/word/line granularity
#   - NodeRelationship: typed parent/child/flow relationships
# ═══════════════════════════════════════════════════════════════════════

interface AccessibilityService {
    # Fetch the full subtree rooted at a node.
    getTree @0 (rootId :T.AccessNodeId) -> (tree :AccessibilityNode);

    # Subscribe to tree structure changes (child added/removed, node destroyed).
    subscribeTree @1 (rootId :T.AccessNodeId) -> (subscription :TreeSubscription);
    pullTree @2 (subscription :TreeSubscription) -> (delta :TreeDelta);
    cancelTree @3 (subscription :TreeSubscription) -> T.VoidResult;

    # Subscribe to accessibility events (focus, announcement, alert, value).
    subscribeEvents @4 () -> (subscription :EventSubscription);
    pullEvents @5 (subscription :EventSubscription) -> (events :List(AccessibilityEvent));
    cancelEvents @6 (subscription :EventSubscription) -> T.VoidResult;

    # Execute an action on a node.
    performAction @7 (nodeId :T.AccessNodeId, action :AccessibilityAction) -> T.VoidResult;

    # Get the currently focused node.
    getFocusedNode @8 () -> (node :AccessibilityNode);

    # Set focus to a specific node.
    setFocus @9 (nodeId :T.AccessNodeId) -> T.VoidResult;

    # Get selected text within a node (for text-input, staticText, etc).
    getSelectedText @10 (nodeId :T.AccessNodeId) -> (text :Text, range :TextRange);

    # Set text selection range within a node.
    setSelection @11 (nodeId :T.AccessNodeId, range :TextRange) -> T.VoidResult;

    # Query user accessibility preferences.
    getPreferences @12 () -> (preferences :AccessibilityPreferences);

    # Audit-7: get node relationships (parent, siblings, flows).
    getRelationships @13 (nodeId :T.AccessNodeId) -> (relationships :NodeRelationships);

    # Audit-7: get text attributes (inline formatting) for a text node.
    getTextAttributes @14 (nodeId :T.AccessNodeId, range :TextRange)
                      -> (attributes :List(TextAttribute));

    # Audit-7: get the accessibility tree as a flat list (for linear navigation).
    getFlatTree @15 (rootId :T.AccessNodeId, pagination :T.Pagination)
                -> (nodes :List(AccessibilityNode), totalCount :UInt32);

    # Audit-9: export accessibility tree as JSON for debugging.
    exportTreeJson @16 (rootId :T.AccessNodeId) -> (json :Text);

    # Audit-9: batch update multiple nodes atomically.
    batchUpdate @17 (updates :List(NodeUpdate)) -> T.VoidResult;

    # Audit-9: simulate accessibility events for testing.
    simulateEvent @18 (nodeId :T.AccessNodeId, eventType :AccessibilityActionType) -> T.VoidResult;

    # Audit-10: get ARIA properties for a node.
    getAriaProperties @19 (nodeId :T.AccessNodeId) -> (properties :AriaProperties);

    # Audit-10: set ARIA properties on a node.
    setAriaProperties @20 (nodeId :T.AccessNodeId, properties :AriaProperties) -> T.VoidResult;

    # Audit-10: resolve aria-labelledby reference chain.
    resolveLabelledBy @21 (nodeId :T.AccessNodeId) -> (label :Text, sourceNodes :List(T.AccessNodeId));

    # Audit-10: resolve aria-describedby reference chain.
    resolveDescribedBy @22 (nodeId :T.AccessNodeId) -> (description :Text, sourceNodes :List(T.AccessNodeId));
}

# Audit-9: batch node update for atomic multi-change updates.
struct NodeUpdate {
    nodeId @0 :T.AccessNodeId;
    changes @1 :List(NodePropertyChange);
}

struct NodePropertyChange {
    field @0 :Text;
    value @1 :Text;
}

interface TreeSubscription {
    pull @0 () -> (delta :TreeDelta);
    cancel @1 () -> T.VoidResult;
}

interface EventSubscription {
    pull @0 () -> (events :List(AccessibilityEvent));
    cancel @1 () -> T.VoidResult;
}

# ── Text Range ────────────────────────────────────────────────────────
# Audit-7 addition: typed text range for selection operations. Replaces
# raw start/end UInt32 pairs with a structured range that supports
# character, word, and line granularity.
struct TextRange {
    start @0 :UInt32;
    end @1 :UInt32;
    # Granularity of the range (for granular selection operations).
    granularity @2 :TextGranularity;
}

enum TextGranularity {
    character @0;
    word @1;
    line @2;
    sentence @3;
    paragraph @4;
    all @5;
    custom @6;
}

# ── Text Attribute ────────────────────────────────────────────────────
# Audit-7 addition: inline formatting for rich text nodes. Screen
# readers need to know that a word is bold, italic, or a link — not
# just the plain text. TextAttribute provides that without duplicating
# the entire text tree.
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
        custom @3 :Data;
    }
}

# ── Node Relationships ────────────────────────────────────────────────
# Audit-7 addition: typed parent/child/flow relationships. Assistive
# tech needs to navigate the tree in ways that differ from the visual
# layout (e.g. reading order, logical grouping). NodeRelationships
# provides that without requiring the entire tree.
struct NodeRelationships {
    nodeId @0 :T.AccessNodeId;
    parent @1 :T.AccessNodeId;
    siblings @2 :List(T.AccessNodeId);
    # Logical flow: what comes next/previous in reading order.
    nextInFlow @3 :T.AccessNodeId;
    previousInFlow @4 :T.AccessNodeId;
    # Controlled elements (for combobox -> listbox relationships).
    controlledElements @5 :List(T.AccessNodeId);
    # Details element (for aria-details).
    detailsElement @6 :T.AccessNodeId;
    # Error message element (for aria-errormessage).
    errorMessage @7 :T.AccessNodeId;
}

# ── Tree Model ────────────────────────────────────────────────────────

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
    # Explicit reading/ traversal order (differs from visual order in multi-column layouts).
    readingOrder @9 :List(T.AccessNodeId);
    attributes @10 :T.StringMap;
    # Live region mode for dynamic content (chat messages, timers, status bars).
    liveRegion @11 :LiveRegionMode;
    # Audit-7: text value (for input fields, text nodes).
    value @12 :Text;
    # Audit-7: minimum value (for sliders, progress bars).
    minValue @13 :Float32;
    # Audit-7: maximum value (for sliders, progress bars).
    maxValue @14 :Float32;
    # Audit-7: current value as float (for numeric controls).
    numericValue @15 :Float32;
    # Audit-7: placeholder text (for input fields).
    placeholder @16 :Text;
    # Audit-7: error message node ID.
    errorNodeId @17 :T.AccessNodeId;
    # Audit-7: keyboard shortcut (e.g. "Ctrl+S").
    keyboardShortcut @18 :Text;
}

enum CoordinateSpace {
    screen @0;
    window @1;
    parent @2;
    content @3;
    custom @4;
}

enum LiveRegionMode {
    off @0;
    polite @1;
    assertive @2;
    custom @3;
}

# ── Tree Deltas (incremental updates) ────────────────────────────────

struct TreeDelta {
    nodeId @0 :T.AccessNodeId;
    changes @1 :List(TreeChange);
}

struct TreeChange {
    union {
        childAdded @0 :ChildAddedChange;
        childRemoved @1 :ChildRemovedChange;
        stateChanged @2 :StateChange;
        boundsChanged @3 :BoundsChange;
        nameChanged @4 :NameChange;
        descriptionChanged @5 :DescriptionChange;
        destroyed @6 :Void;
        # Audit-7: value changed (for live input fields).
        valueChanged @7 :ValueChange;
        custom @8 :Data;
    }
}

struct ChildAddedChange {
    childId @0 :T.AccessNodeId;
    index @1 :UInt32;
}

struct ChildRemovedChange {
    childId @0 :T.AccessNodeId;
}

struct StateChange {
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

# Audit-7 addition: value change for live input fields.
struct ValueChange {
    previous @0 :Text;
    current @1 :Text;
}

# ── Accessibility Events ──────────────────────────────────────────────

struct AccessibilityEvent {
    union {
        focusChanged @0 :FocusChangedEvent;
        stateChanged @1 :StateChangedEvent;
        announcement @2 :AnnouncementEvent;
        alert @3 :AlertEvent;
        treeChanged @4 :TreeChangedEvent;
        valueChanged @5 :ValueChangedEvent;
        # Audit-7: text selection changed (for text-input, staticText).
        selectionChanged @6 :SelectionChangedEvent;
        # Audit-7: scroll position changed.
        scrolled @7 :ScrolledEvent;
        custom @8 :Data;
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

# Audit-7 addition: text selection changed.
struct SelectionChangedEvent {
    nodeId @0 :T.AccessNodeId;
    range @1 :TextRange;
    timestamp @2 :T.Timestamp;
}

# Audit-7 addition: scroll position changed.
struct ScrolledEvent {
    nodeId @0 :T.AccessNodeId;
    position @1 :T.Rect;
    timestamp @2 :T.Timestamp;
}

# ── Roles ─────────────────────────────────────────────────────────────

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
    # Audit-7 additions: grid, tooltip, spinButton, tabList, tabPanel,
    # menuBar, figure, caption, term, definition, feed, note, suggestion,
    # contentDeletion, contentInsertion, emphasized, strong, mark, s,
    # subscript, superscript, time, status, timer, marquee, math,
    # searchBox, meter, option, fontViewer, document, log, liveRegion,
    # alertdialog, buttonGroup, rowHeader, columnHeader, row @45-78
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

# ── State ─────────────────────────────────────────────────────────────

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
    # Audit-7 additions:
    highlighted @17 :Bool;        # Node is visually highlighted
    collapsedByUser @18 :Bool;    # User explicitly collapsed this node
    autoplay @19 :Bool;           # Media is autoplaying
    expandedByUser @20 :Bool;     # User explicitly expanded this node
    selectedFromFocus @21 :Bool;  # Selection follows focus
    hovered @22 :Bool;            # Pointer is hovering over this node
    active @23 :Bool;             # Node is currently active (pressed button)
    enlarged @24 :Bool;           # Magnifier is enlarging this node
    dimmed @25 :Bool;             # Node is visually dimmed (off-screen content)
}

# ── Actions ───────────────────────────────────────────────────────────

struct AccessibilityAction {
    type @0 :AccessibilityActionType;
    name @1 :Text;
    description @2 :Text;
    # Parameters for parameterized actions (scroll-to-position, set-value, select-range).
    parameters @3 :T.StringMap;
    # Audit-9: typed action parameters replacing StringMap.
    typedParams @4 :TypedActionParams;
}

# Audit-9: typed parameters for parameterized actions.
struct TypedActionParams {
    union {
        scrollToPoint @0 :ScrollToPointParams;
        setValue @1 :SetValueParams;
        selectRange @2 :SelectRangeParams;
        custom @3 :Data;
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
    # Audit-7 additions:
    scrollToPoint @18;       # Scroll to specific coordinates
    showOnScreen @19;        # Ensure node is visible on screen
    accessibilityFocus @20;  # Set accessibility-specific focus
    dismiss @21;             # Dismiss popup/dialog/notification
    drag @22;                # Initiate drag operation
    expand @23;              # Expand collapsed node
    collapse @24;            # Collapse expanded node
    custom @25;
}

# ── Preferences ───────────────────────────────────────────────────────

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
    # Audit-7 additions:
    screenMagnifierEnabled @10 :Bool;   # Screen magnifier is active
    magnifierScale @11 :Float32;        # Magnifier zoom level
    switchControlEnabled @12 :Bool;     # Switch control is active
    voiceControlEnabled @13 :Bool;      # Voice control is active
    reduceWhitePoint @14 :Bool;         # Reduce white point for light sensitivity
    pointerControlEnabled @15 :Bool;    # Alternative pointer control
    stickyKeys @16 :Bool;               # Sticky keys for motor impairments
    slowKeys @17 :Bool;                 # Slow keys (delay before keypress registers)
    bounceKeys @18 :Bool;               # Bounce keys (reject rapid repeated presses)
    caretBlinkRate @19 :UInt32;         # Cursor blink rate in ms (0 = no blink)
    doubleClickDelay @20 :UInt32;       # Double-click detection window in ms
}

enum CaptionStyle {
    default @0;
    whiteOnBlack @1;
    yellowOnBlack @2;
    yellowOnBlue @3;
    custom @4;
}

# ── Audit-10: ARIA Properties ────────────────────────────────────────
# Explicit ARIA property mapping for WAI-ARIA compatibility.
# Provides label, labelledby, describedby, and role mapping.

struct AriaProperties {
    # Explicit accessible name (replaces aria-label).
    label @0 :Text;
    # Node IDs that provide the accessible name (replaces aria-labelledby).
    labelledBy @1 :List(T.AccessNodeId);
    # Node IDs that provide the description (replaces aria-describedby).
    describedBy @2 :List(T.AccessNodeId);
    # Additional description from extended descriptions.
    describedByExtended @3 :List(T.AccessNodeId);
    # Live region politeness level.
    live @4 :AriaLive;
    # Whether the element is atomic (all or nothing for screen readers).
    atomic @5 :Bool;
    # Whether the element is busy (still loading).
    busy @6 :Bool;
    # Current state of a toggle (pressed, checked).
    current @7 :AriaCurrent;
    # Error message reference.
    errorMessage @8 :T.AccessNodeId;
    # Whether the element has a popup.
    hasPopup @9 :AriaHasPopup;
    # Whether the element is hidden.
    hidden @10 :Bool;
    # Invalid state.
    invalid @11 :AriaInvalid;
    # Label for the element's controls (replaces aria-controls).
    controls @12 :List(T.AccessNodeId);
    # Elements owned by this element (replaces aria-owns).
    owns @13 :List(T.AccessNodeId);
    # Relationship type for related elements.
    relatedElements @14 :List(AriaRelationship);
}

enum AriaLive {
    off @0;
    polite @1;
    assertive @2;
    rude @3;
}

enum AriaCurrent {
    page @0;
    step @1;
    location @2;
    date @3;
    time @4;
    timer @5;
    true @6;
}

enum AriaHasPopup {
    false @0;
    true @1;
    menu @2;
    listbox @3;
    tree @4;
    grid @5;
    dialog @6;
}

enum AriaInvalid {
    false @0;
    true @1;
    grammar @2;
    spelling @3;
}

struct AriaRelationship {
    # Relationship type (e.g., "related", "group", "flow").
    type @0 :Text;
    # Target node IDs for this relationship.
    targets @1 :List(T.AccessNodeId);
}
