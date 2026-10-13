import QtQuick
import qs.Commons

// The panel's heading, after Omarchy's world clock: an arched caption over
// two title words with a small illustration between them. Whatever is
// declared inside becomes that illustration.
Column {
    id: root

    property string caption: ""
    property string leftWord: ""
    property string rightWord: ""
    property color foreground: Color.foreground
    property string fontFamily: Style.font.family
    readonly property color dim: Qt.darker(foreground, 1.55)
    readonly property int iconSize: Math.round(Style.font.display * 1.3)
    default property alias icon: iconSlot.data

    spacing: Style.space(2)

    ArcText {
        objectName: "titleCaption"
        width: parent.width
        text: root.caption
        color: root.dim
        fontFamily: root.fontFamily
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(9)

        Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.leftWord
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.weight: Font.DemiBold
        }

        Item {
            id: iconSlot

            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: root.iconSize
            implicitHeight: root.iconSize
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.rightWord
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.weight: Font.DemiBold
        }

    }

}
