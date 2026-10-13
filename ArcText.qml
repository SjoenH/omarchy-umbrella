import QtQuick
import qs.Commons

// One line of text arched over whatever sits below it, the way the caption
// sits over the title in Omarchy's world clock. Each character is its own
// Text, moved and turned to follow a shallow circular arc.
Item {
    id: root

    property string text: ""
    // How far the two ends sit below the middle of the line.
    property real rise: Style.space(6)
    property color color: Color.foreground
    property string fontFamily: Style.font.family
    property int pixelSize: Style.font.caption
    readonly property var letters: text.split("")
    // Left edge of every character on the flat line, then the line's width.
    readonly property var edges: {
        // advanceWidth() does not register the font as a dependency.
        var font = metrics.font.family + metrics.font.pixelSize;
        var out = [0];
        for (var i = 0; i < letters.length; i++) out.push(out[i] + metrics.advanceWidth(letters[i]))
        return out;
    }
    readonly property real lineWidth: edges[edges.length - 1]
    readonly property real sag: Math.min(rise, lineWidth / 4)
    // Radius of the circle through the middle of the line and both ends.
    readonly property real arcRadius: sag > 0 ? lineWidth * lineWidth / (8 * sag) : 0

    function angleAt(index) {
        if (arcRadius <= 0)
            return 0;

        return ((edges[index] + edges[index + 1]) / 2 - lineWidth / 2) / arcRadius;
    }

    implicitWidth: Math.ceil(lineWidth + metrics.height)
    implicitHeight: Math.ceil(metrics.height + sag)
    Accessible.role: Accessible.StaticText
    Accessible.name: root.text

    FontMetrics {
        id: metrics

        font.family: root.fontFamily
        font.pixelSize: root.pixelSize
    }

    Repeater {
        model: root.letters.length

        Text {
            required property int index
            readonly property real angle: root.angleAt(index)

            width: root.edges[index + 1] - root.edges[index]
            height: metrics.height
            x: root.width / 2 + (root.arcRadius > 0 ? root.arcRadius * Math.sin(angle) : (root.edges[index] + root.edges[index + 1] - root.lineWidth) / 2) - width / 2
            y: root.arcRadius * (1 - Math.cos(angle))
            rotation: angle * 180 / Math.PI
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
            text: root.letters[index] || ""
            color: root.color
            font.family: root.fontFamily
            font.pixelSize: root.pixelSize
            // Native rendering ignores the rotation.
            renderType: Text.QtRendering
        }

    }

}
