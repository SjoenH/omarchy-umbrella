import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
    id: root

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

    moduleName: "koka.umbrella"
    // Always visible: a dry bar shows the quiet sun glyph, incoming rain swaps
    // it for the countdown.
    implicitWidth: button.implicitWidth
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
        bar: root.bar
        text: panelLoader.item ? panelLoader.item.barText : ""
        // Auto-size to the label instead of a fixed slot: the countdown text
        // ("☔ 45m") is wider than any square slot and would overlap neighbors.
        // Radar mode uses the square slot for its mini chart.
        slotSize: panelLoader.item && panelLoader.item.radarInBar ? Style.bar.statusSlot : -1
        // Radar mode: a Yr-style mini bar chart of the next 90 minutes replaces
        // the umbrella glyph. Inline component so its bindings resolve here and
        // can reach the panel's nowcast series.
        iconComponent: panelLoader.item && panelLoader.item.radarInBar ? radarIcon : null
        // Tooltip suppressed because the panel is the detail view.
        tooltipText: ""
        onPressed: function(b) {
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

        Component {
            id: radarIcon

            Item {
                id: radarBar

                readonly property var series: panelLoader.item ? panelLoader.item.nowcastSeries : []

                anchors.fill: parent

                Repeater {
                    model: radarBar.series

                    Rectangle {
                        required property var modelData
                        required property int index
                        readonly property real rate: Math.max(0, Number(modelData.rate) || 0)

                        x: index * (radarBar.width / radarBar.series.length)
                        width: Math.max(1, radarBar.width / radarBar.series.length - 0.5)
                        anchors.bottom: parent.bottom
                        height: Math.max(1, Math.min(1, rate / 2.5) * (radarBar.height - 1))
                        radius: Math.min(1, width / 2)
                        color: root.bar ? root.bar.foreground : Color.foreground
                        opacity: 0.45 + 0.55 * Math.min(1, rate / 2.5)
                    }

                }

            }

        }

    }

}
