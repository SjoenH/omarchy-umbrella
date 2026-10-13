import QtQuick
import qs.Commons

// One reading as a card, after the city rows in Omarchy's world clock: a
// name and a line of detail on the left, the value large on the right, and
// an optional track along the bottom with a marker at `progress`. Anything
// declared inside the card is laid out along its bottom edge instead.
Rectangle {
    id: root

    property string name: ""
    property string detail: ""
    property string value: ""
    property string unit: ""
    property string note: ""
    // 0 to 1 along the track; anything below 0 hides the track.
    property real progress: -1
    property color foreground: Color.foreground
    property color valueColor: foreground
    property color markerColor: foreground
    property string fontFamily: Style.font.family
    readonly property color dim: Qt.darker(foreground, 1.55)
    readonly property bool tracked: progress >= 0
    readonly property real fraction: Math.max(0, Math.min(1, progress))
    readonly property int pad: Style.space(15)
    readonly property int trackHeight: Math.max(2, Style.space(3))
    readonly property int markerSize: Math.max(8, Style.space(10))
    readonly property int gap: Style.space(9)
    default property alias footer: footerSlot.data

    function tint(amount) {
        var from = Color.popups.background;
        return Qt.rgba(from.r + (foreground.r - from.r) * amount, from.g + (foreground.g - from.g) * amount, from.b + (foreground.b - from.b) * amount, 1);
    }

    implicitHeight: pad + Math.max(labels.implicitHeight, reading.implicitHeight) + (tracked ? gap + markerSize : 0) + (footerSlot.height > 0 ? gap + footerSlot.height : 0) + pad
    radius: Style.cornerRadius
    color: root.tint(0.1)
    Accessible.role: Accessible.StaticText
    Accessible.name: root.name + ": " + root.value + root.unit

    Column {
        id: labels

        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.rowPaddingX
        anchors.right: reading.left
        anchors.rightMargin: Style.spacing.xl
        anchors.top: parent.top
        anchors.topMargin: root.pad
        spacing: Style.space(2)

        Text {
            objectName: "cardName"
            width: parent.width
            textFormat: Text.PlainText
            text: root.name
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        Text {
            objectName: "cardDetail"
            width: parent.width
            textFormat: Text.PlainText
            text: root.detail
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
        }

    }

    Column {
        id: reading

        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.rowPaddingX
        anchors.verticalCenter: labels.verticalCenter
        spacing: Style.space(1)

        Row {
            anchors.right: parent.right
            spacing: Style.spacing.xs

            Text {
                id: bigValue

                objectName: "cardValue"
                textFormat: Text.PlainText
                text: root.value
                color: root.valueColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                font.weight: Font.DemiBold
            }

            Text {
                anchors.baseline: bigValue.baseline
                visible: text !== ""
                textFormat: Text.PlainText
                text: root.unit
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
            }

        }

        Text {
            objectName: "cardNote"
            anchors.right: parent.right
            visible: text !== ""
            textFormat: Text.PlainText
            text: root.note
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
        }

    }

    Rectangle {
        id: track

        visible: root.tracked
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Style.spacing.rowPaddingX
        anchors.rightMargin: Style.spacing.rowPaddingX
        anchors.verticalCenter: parent.bottom
        anchors.verticalCenterOffset: -(root.pad + root.markerSize / 2)
        height: root.trackHeight
        radius: height / 2
        color: Util.alpha(root.foreground, 0.1)

        Rectangle {
            width: Math.max(parent.height, parent.width * root.fraction)
            height: parent.height
            radius: parent.radius
            color: Util.alpha(root.foreground, 0.28)

            Behavior on width {
                NumberAnimation {
                    duration: Style.duration(200)
                    easing.type: Easing.OutCubic
                }

            }

        }

        Rectangle {
            objectName: "cardMarker"
            x: (parent.width - width) * root.fraction
            anchors.verticalCenter: parent.verticalCenter
            width: root.markerSize
            height: width
            radius: width / 2
            color: root.markerColor

            Behavior on x {
                NumberAnimation {
                    duration: Style.duration(200)
                    easing.type: Easing.OutCubic
                }

            }

        }

    }

    Item {
        id: footerSlot

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Style.spacing.rowPaddingX
        anchors.rightMargin: Style.spacing.rowPaddingX
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.pad
        height: childrenRect.height
    }

}
