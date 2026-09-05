import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
    id: root

    // Radar mode renders its own wide chart item; the icon button only handles
    // the umbrella/radar-label modes.
    readonly property bool radarInBar: panelLoader.item ? panelLoader.item.radarInBar : false
    readonly property int radarBarWidth: Style.space(110)
    // Shape contract for shell.summon/hide/toggle routing (Bar.findPanelWidget
    // requires open/close/opened on the bar-widget root). Open maps to the
    // panel's hotkey path so summoning suppresses the center hover reveal.
    readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
    // Forwarded so this widget can stand in for the panel as the bar's popout
    // identity: Bar.requestPopout prefers closeForPopoutSwitch over close, and
    // KeyboardPanel reads popoutSwitchClosing back off its owner.
    readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

    function injectPanel() {
        var target = panelLoader.item;
        if (!target)
            return ;

        if ("bar" in target)
            target.bar = root.bar;

        if ("settings" in target)
            target.settings = root.settings;

        if ("anchorItem" in target)
            target.anchorItem = button;

        if ("hostWidget" in target)
            target.hostWidget = root;

    }

    function refresh() {
        if (panelLoader.item && panelLoader.item.refresh)
            panelLoader.item.refresh();

    }

    function togglePanel() {
        if (panelLoader.item && panelLoader.item.toggle)
            panelLoader.item.toggle();

    }

    function open() {
        if (panelLoader.item && panelLoader.item.openFromHotkey)
            panelLoader.item.openFromHotkey();

    }

    function close() {
        if (panelLoader.item && panelLoader.item.close)
            panelLoader.item.close();

    }

    function closeForPopoutSwitch() {
        if (panelLoader.item)
            panelLoader.item.closeForPopoutSwitch();

    }

    function handlePress(b) {
        if (!root.bar)
            return ;

        if (b === Qt.RightButton) {
            if (panelLoader.item && panelLoader.item.notifyUmbrella)
                panelLoader.item.notifyUmbrella();

        } else if (b === Qt.MiddleButton) {
            root.refresh();
        } else {
            root.togglePanel();
        }
    }

    moduleName: "koka.umbrella"
    // Always visible: a dry bar shows the quiet sun glyph, incoming rain swaps
    // it for the countdown.
    implicitWidth: radarInBar ? radarBarWidth : button.implicitWidth
    implicitHeight: button.implicitHeight
    onBarChanged: injectPanel()
    onSettingsChanged: injectPanel()

    Loader {
        id: panelLoader

        active: true
        source: Qt.resolvedUrl("Panel.qml")
        visible: false
        onLoaded: {
            root.injectPanel();
            Qt.callLater(root.injectPanel);
        }
    }

    BarIconButton {
        id: button

        anchors.fill: parent
        visible: !root.radarInBar
        bar: root.bar
        text: panelLoader.item ? panelLoader.item.barText : ""
        // Auto-size to the label instead of a fixed slot: the countdown text
        // ("☔ 45m") is wider than any square slot and would overlap neighbors.
        slotSize: -1
        // Tooltip suppressed because the panel is the detail view.
        tooltipText: ""
        onPressed: function(b) {
            root.handlePress(b);
        }
    }

    // Yr-style mini radar chart, Yr-scaled: bars are sized against the window's
    // peak rate (floor 0.5 mm/h) so light drizzle stays visible. Registered as
    // a bar click target — the bar's slot-wide pointer area forwards presses
    // only to registered targets, so a plain MouseArea would never fire.
    Item {
        id: radarChart

        readonly property var series: panelLoader.item ? panelLoader.item.nowcastSeries : []
        // Fixed intensity scale (like Yr's nowcast chart): 1.5 mm/h fills the
        // height, so drizzle reads as a low bar instead of a dramatic spike.
        readonly property real scaleRate: 1.5
        // Bar tooltip plumbing — the bar checks tooltipHovered on the target.
        readonly property string tooltipText: panelLoader.item ? panelLoader.item.radarTooltip : ""
        readonly property bool tooltipHovered: chartHover.containsMouse
        property var registeredBar: null

        function triggerPress(b) {
            root.handlePress(b);
        }

        function syncClickRegistration() {
            if (registeredBar && registeredBar.unregisterClickTarget)
                registeredBar.unregisterClickTarget(this);

            registeredBar = root.bar;
            if (registeredBar && registeredBar.registerClickTarget)
                registeredBar.registerClickTarget(this);

        }

        Component.onCompleted: syncClickRegistration()
        Component.onDestruction: {
            if (registeredBar && registeredBar.unregisterClickTarget)
                registeredBar.unregisterClickTarget(this);

        }
        onVisibleChanged: syncClickRegistration()
        anchors.fill: parent
        visible: root.radarInBar

        Row {
            anchors.fill: parent

            Repeater {
                model: radarChart.series

                Rectangle {
                    required property var modelData
                    readonly property real rate: Math.max(0, Number(modelData.rate) || 0)

                    width: parent.width / radarChart.series.length
                    // Wet steps get a small visible baseline so a trace of
                    // rain doesn't vanish; intensity scales from there.
                    height: rate > 0.05 ? Math.max(2, parent.height * Math.min(1, rate / radarChart.scaleRate)) : 0
                    anchors.bottom: parent.bottom
                    color: root.bar ? root.bar.foreground : Color.foreground
                    opacity: 0.45 + 0.55 * Math.min(1, rate / radarChart.scaleRate)
                }

            }

        }

        MouseArea {
            id: chartHover

            anchors.fill: parent
            // Hover-only: presses are forwarded to the registered target by
            // the bar's slot-wide pointer area.
            acceptedButtons: Qt.NoButton
            hoverEnabled: true
            onEntered: {
                if (root.bar)
                    root.bar.showTooltip(radarChart, radarChart.tooltipText);

            }
            onExited: {
                if (root.bar)
                    root.bar.hideTooltip(radarChart);

            }
        }

    }

}
