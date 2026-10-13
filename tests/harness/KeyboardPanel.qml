import QtQuick
import qs.Commons
import qs.Commons as Commons

// Test stand-in for the host's KeyboardPanel. The real one is a layer-shell
// window, which cannot map in a headless run, so this draws the same card
// (surface, border, padding, sizing helpers) as a plain item in the test
// window. Everything inside the panel is still the real UI kit.
BorderSurface {
    id: root

    property Item anchorItem: null
    property QtObject bar: null
    property var owner: null
    property bool open: false
    property Item focusTarget: null
    property int contentWidth: Style.space(280)
    property int contentHeight: Style.space(200)
    property int gap: Style.gapsOut
    // Accepted for parity with the real panel; the stand-in always sits under its anchor.
    property bool centerOnBar: false
    default property alias contentItem: contentHolder.children
    readonly property real verticalContentInset: padding * 2 + Border.top(borderSpec) + Border.bottom(borderSpec)

    function fittedContentWidth(width) {
        return Math.round(Math.max(1, Number(width) || 1));
    }

    function fittedContentHeight(implicitHeight) {
        return Math.round(Math.max(verticalContentInset, (Number(implicitHeight) || 0) + verticalContentInset));
    }

    function close() {
        if (owner && "close" in owner)
            owner.close();
        else
            open = false;
    }

    parent: anchorItem ? anchorItem.parent : null
    x: anchorItem ? Math.max(gap, Math.round(anchorItem.x + anchorItem.width / 2 - width / 2)) : gap
    y: anchorItem ? anchorItem.y + anchorItem.height + gap : gap
    width: contentWidth
    height: contentHeight
    visible: open
    color: Commons.Color.popups.background
    borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
    padding: Style.spacing.popupPadding
    radius: Style.cornerRadius
    onOpenChanged: {
        if (open && focusTarget)
            focusTarget.forceActiveFocus();

    }

    Item {
        id: contentHolder

        anchors.fill: parent
        anchors.topMargin: root.contentTopInset
        anchors.rightMargin: root.contentRightInset
        anchors.bottomMargin: root.contentBottomInset
        anchors.leftMargin: root.contentLeftInset
    }

}
