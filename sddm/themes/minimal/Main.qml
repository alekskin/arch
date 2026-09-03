import QtQuick 2.15
import QtQuick.Window 2.15

Rectangle {
    id: root
    width: 1366; height: 768
    color: "#1e1e2e"

    property color surface:  "#313244"
    property color textcol:  "#cdd6f4"
    property color subtext:  "#7f849c"
    property color accent:   "#89b4fa"

    // Sway uses scale 2.0 on retina panels (e.g. 2560x1600 MBP) and 1.0 on
    // 1080p / 1366x768. The greeter runs on X11 before sway, so Qt stays at
    // 1x — size the UI from the pixel resolution instead.
    readonly property real uiScale: (Screen.width >= 2400 || Screen.height >= 1400) ? 2 : 1
    function s(px) { return Math.round(px * uiScale) }

    function doLogin() {
        sddm.login(userInput.text, passInput.text, sessionModel.lastIndex)
    }
    Connections {
        target: sddm
        function onLoginFailed() { passInput.text = ""; passInput.forceActiveFocus() }
    }

    Column {
        anchors.centerIn: parent
        spacing: s(12)
        width: s(300)

        // Username (prefilled with the last user)
        Rectangle {
            width: parent.width; height: s(42); radius: s(6); color: surface
            border.width: userInput.activeFocus ? uiScale : 0; border.color: accent
            Text {
                anchors.fill: parent; anchors.leftMargin: s(13)
                verticalAlignment: Text.AlignVCenter
                text: "Username"; color: subtext; font.pixelSize: s(15)
                visible: userInput.text.length === 0
            }
            TextInput {
                id: userInput
                anchors.fill: parent; anchors.leftMargin: s(12); anchors.rightMargin: s(12)
                verticalAlignment: TextInput.AlignVCenter
                color: textcol; font.pixelSize: s(15); clip: true; selectByMouse: true
                text: (typeof userModel !== "undefined" && userModel.lastUser) ? userModel.lastUser : ""
                KeyNavigation.tab: passInput
                onAccepted: passInput.forceActiveFocus()
            }
        }

        // Password
        Rectangle {
            width: parent.width; height: s(42); radius: s(6); color: surface
            border.width: passInput.activeFocus ? uiScale : 0; border.color: accent
            Text {
                anchors.fill: parent; anchors.leftMargin: s(13)
                verticalAlignment: Text.AlignVCenter
                text: "Password"; color: subtext; font.pixelSize: s(15)
                visible: passInput.text.length === 0
            }
            TextInput {
                id: passInput
                anchors.fill: parent; anchors.leftMargin: s(12); anchors.rightMargin: s(12)
                verticalAlignment: TextInput.AlignVCenter
                color: textcol; font.pixelSize: s(15); clip: true; selectByMouse: true
                echoMode: TextInput.Password; passwordCharacter: "•"
                KeyNavigation.tab: userInput
                onAccepted: root.doLogin()
            }
        }
    }

    // Small power controls, top-right
    Row {
        anchors.top: parent.top; anchors.right: parent.right; anchors.margins: s(22)
        spacing: s(18)
        Text {
            text: "Reboot"; color: subtext; font.pixelSize: s(13)
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sddm.reboot() }
        }
        Text {
            text: "Power Off"; color: subtext; font.pixelSize: s(13)
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sddm.powerOff() }
        }
    }

    Component.onCompleted: {
        if (userInput.text === "") userInput.forceActiveFocus()
        else passInput.forceActiveFocus()
    }
}
