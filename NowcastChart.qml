import "Model.js" as Model
import QtQuick
import qs.Commons

// The radar nowcast as a Yr-style bar chart: one bar per five-minute radar
// step over the next 90 minutes, on a fixed intensity scale, with a readout
// for the bar under the pointer. `series` is [{ date, rate }], rate in mm/h.
Column {
    id: root

    property var series: []
    property color foreground: Color.foreground
    property color accent: Color.accent
    property string fontFamily: Style.font.family
    // Fixed scale, like Yr's chart: 1.5 mm/h fills the height, so drizzle
    // reads as a low bar instead of a dramatic spike.
    readonly property real scaleRate: 1.5
    property int hoverIndex: -1
    readonly property real step: chart.width / Math.max(1, series.length)
    readonly property color dim: Qt.darker(foreground, 1.55)

    spacing: Style.space(2)
    Accessible.role: Accessible.Graphic
    Accessible.name: "Radar for the next 90 minutes"

    Item {
        id: chart

        width: parent.width
        height: Style.space(36)

        Repeater {
            model: root.series

            Rectangle {
                required property var modelData
                required property int index
                readonly property real rate: Math.max(0, Number(modelData.rate) || 0)

                objectName: "nowcastBar-" + index
                x: index * root.step
                width: Math.max(1, root.step - 1)
                anchors.bottom: parent.bottom
                // Wet steps keep a small visible baseline so a trace of rain
                // does not vanish; intensity scales from there.
                height: rate > 0.05 ? Math.max(2, chart.height * Math.min(1, rate / root.scaleRate)) : 0
                radius: Math.min(2, width / 2)
                // CONVENTION-EXCEPTION: rain intensity color, echoing Yr's chart
                color: root.accent
                opacity: root.hoverIndex === index ? 1 : 0.4 + 0.6 * Math.min(1, rate / root.scaleRate)
            }

        }

        // Baseline, so a dry radar still reads as a chart.
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Util.alpha(root.foreground, 0.12)
        }

        // Time and intensity of the bar under the pointer.
        Rectangle {
            visible: root.hoverIndex >= 0 && root.hoverIndex < root.series.length
            height: Style.space(16)
            width: hoverLabel.implicitWidth + Style.space(10)
            x: Math.max(0, Math.min(root.hoverIndex * root.step + root.step / 2 - width / 2, chart.width - width))
            y: 0
            radius: Math.min(3, Style.cornerRadius)
            color: Color.popups.background
            border.width: Math.max(1, Style.space(0.5))
            border.color: Qt.darker(root.foreground, 1.8)

            Text {
                id: hoverLabel

                objectName: "nowcastReadout"
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: {
                    if (root.hoverIndex < 0 || root.hoverIndex >= root.series.length)
                        return "";

                    var step = root.series[root.hoverIndex];
                    if (step.rate <= Model.NOWCAST_THRESHOLD)
                        return Qt.formatTime(step.date, "HH:mm") + " · dry";

                    return Qt.formatTime(step.date, "HH:mm") + " · " + Model.describeRate(step.rate) + " · " + (Math.round(step.rate * 10) / 10) + " mm/h";
                }
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
            }

        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            hoverEnabled: true
            cursorShape: Qt.ArrowCursor
            onPositionChanged: function(mouse) {
                root.hoverIndex = Math.floor(mouse.x / root.step);
            }
            onExited: root.hoverIndex = -1
        }

    }

    Item {
        width: parent.width
        height: Style.font.caption * 1.4

        Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            text: "Now"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
        }

        Text {
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
            text: "45"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
        }

        Text {
            textFormat: Text.PlainText
            anchors.right: parent.right
            text: "90 min"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
        }

    }

}
