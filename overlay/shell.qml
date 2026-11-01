import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "geometry.js" as Geometry

// The scrolling capture's selection and controls, run by `shotkit scroll` as
// its own Quickshell instance (qs -p this directory), so it needs nothing from
// the user's shell. The region and the state directory come in the
// environment: SHOTKIT_GEOMETRY (slurp's "X,Y WxH") and SHOTKIT_STATE. It
// shows an outline around the region and a bar with Start and Cancel (Enter,
// Escape). Start or Cancel touches a file in the state directory, which the
// script waits on; the script then switches the bar to Stop over IPC and
// closes it all when done.
//
// Nothing here may end up in the frames: the outline is drawn just outside the
// region and the bar beside it (see controlsPlacement). A region with no room
// beside it gets the bar inside only while waiting for Start; while recording
// it is hidden there and the shortcut stops the capture. Every window takes
// input on the bar only, so scrolling and clicks inside the region reach the
// page; the keyboard is taken only while Start is waiting.
ShellRoot {
    id: capture

    readonly property var region: Geometry.parseGeometry(Quickshell.env("SHOTKIT_GEOMETRY") || "")
    readonly property string stateDirectory: Quickshell.env("SHOTKIT_STATE") || ""
    readonly property string scrollKey: Quickshell.env("SHOTKIT_SCROLL_KEY") || "the shortcut"
    property bool recording: false

    // Catppuccin Mocha.
    readonly property color base: "#1e1e2e"
    readonly property color text: "#cdd6f4"
    readonly property color subtext: "#a6adc8"
    readonly property color accent: "#b4befe"
    readonly property color red: "#f38ba8"
    readonly property int fontSize: 13

    readonly property int outlineWidth: 2
    // The outline's distance from the region, so grim's rounding never grabs it.
    readonly property int outlineInset: outlineWidth + 1
    readonly property int gap: 12
    readonly property var placement: region ? Geometry.controlsPlacement(region, Quickshell.screens, { width: bar.implicitWidth, height: bar.implicitHeight }, gap) : null

    function tint(color, alpha) {
        return Qt.rgba(color.r, color.g, color.b, alpha);
    }

    function answer(name) {
        Quickshell.execDetached(["touch", stateDirectory + "/" + name]);
        // Quit here too, so a script that died without its EXIT trap does not
        // leave the overlay holding the keyboard.
        if (name === "cancel")
            Qt.quit();
    }

    // Tells the script the overlay is up; without it the script falls back to
    // a notification.
    Component.onCompleted: {
        if (region === null || stateDirectory === "")
            Qt.quit();
        else
            Quickshell.execDetached(["touch", stateDirectory + "/ready"]);
    }

    IpcHandler {
        target: "scrollCapture"

        function record(): void {
            capture.recording = true;
        }

        function close(): void {
            Qt.quit();
        }
    }

    // Measured once, outside any window, so the placement knows its size.
    ControlBar {
        id: bar
        visible: false
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: overlay

            required property var modelData
            readonly property bool hasControls: capture.placement !== null && capture.placement.screen === modelData
                && !(capture.recording && capture.placement.inside)

            screen: modelData
            visible: capture.region !== null
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "shotkit-scroll-capture"
            WlrLayershell.keyboardFocus: hasControls && !capture.recording ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            color: "transparent"
            mask: Region {
                item: overlay.hasControls ? controls : null
            }

            // Spans every screen the region does; each window draws its part.
            Rectangle {
                readonly property var region: capture.region || { x: 0, y: 0, width: 0, height: 0 }

                x: region.x - overlay.modelData.x - capture.outlineInset
                y: region.y - overlay.modelData.y - capture.outlineInset
                width: region.width + 2 * capture.outlineInset
                height: region.height + 2 * capture.outlineInset
                color: "transparent"
                border.width: capture.outlineWidth
                border.color: capture.recording ? capture.red : capture.accent
            }

            ControlBar {
                id: controls
                visible: overlay.hasControls
                x: capture.placement ? capture.placement.x : 0
                y: capture.placement ? capture.placement.y : 0
                focus: true
                Keys.onReturnPressed: capture.answer("start")
                Keys.onEnterPressed: capture.answer("start")
                Keys.onEscapePressed: capture.answer("cancel")
            }
        }
    }

    component Label: Text {
        textFormat: Text.PlainText
        color: capture.text
        font.pixelSize: capture.fontSize
        font.weight: Font.DemiBold
    }

    component Button: Rectangle {
        id: button

        property alias text: label.text
        property color textColor: capture.accent

        signal clicked()

        implicitWidth: label.implicitWidth + 20
        implicitHeight: label.implicitHeight + 8
        radius: height / 2
        color: hover.hovered ? capture.tint(capture.accent, 0.14) : "transparent"
        border.width: 1
        border.color: capture.tint(capture.accent, hover.hovered ? 0.4 : 0.18)

        Label {
            id: label
            anchors.centerIn: parent
            color: button.textColor
            font.pixelSize: capture.fontSize - 1
        }
        HoverHandler {
            id: hover
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            onTapped: button.clicked()
        }
    }

    component ControlBar: Rectangle {
        implicitWidth: row.implicitWidth + 32
        implicitHeight: row.implicitHeight + 16
        radius: height / 2
        color: capture.tint(capture.base, 0.92)
        border.width: 1
        border.color: capture.recording ? capture.red : capture.tint(capture.accent, 0.18)

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 10

            Label {
                text: capture.recording ? "Scroll the page" : "Scrolling capture"
                color: capture.recording ? capture.red : capture.accent
            }
            Label {
                text: capture.recording ? capture.scrollKey + " stops" : "Enter or " + capture.scrollKey
                color: capture.subtext
                font.pixelSize: capture.fontSize - 2
            }
            Button {
                visible: !capture.recording
                text: "Start"
                onClicked: capture.answer("start")
            }
            Button {
                visible: !capture.recording
                text: "Cancel"
                textColor: capture.subtext
                onClicked: capture.answer("cancel")
            }
            Button {
                visible: capture.recording
                text: "Stop"
                textColor: capture.red
                onClicked: capture.answer("stop")
            }
        }
    }
}
