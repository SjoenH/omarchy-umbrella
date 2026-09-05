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
    // peak rate (floor 0.5 mm/h) so light drizzle stays visible.
    Item {
        id: radarChart

        readonly property var series: panelLoader.item ? panelLoader.item.nowcastSeries : []
        readonly property real maxRate: {
            var max = 0.5;
            for (var i = 0; i < series.length; i++) max = Math.max(max, Number(series[i].rate) || 0)
            return max;
        }

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
                    height: parent.height * (rate / radarChart.maxRate)
                    anchors.bottom: parent.bottom
                    color: root.bar ? root.bar.foreground : Color.foreground
                    opacity: 0.45 + 0.55 * (rate / radarChart.maxRate)
                }

            }

        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            onPressed: function(mouse) {
                root.handlePress(mouse.button);
            }
        }

    }

}
