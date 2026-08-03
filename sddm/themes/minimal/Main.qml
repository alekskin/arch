import QtQuick 2.15

Rectangle {
    id: root
    width: 1366; height: 768
    color: "#1e1e2e"

    property color surface:  "#313244"
    property color textcol:  "#cdd6f4"
    property color subtext:  "#7f849c"
    property color accent:   "#89b4fa"

    function doLogin() {
        sddm.login(userInput.text, passInput.text, sessionModel.lastIndex)
    }
    Connections {
        target: sddm
        function onLoginFailed() { passInput.text = ""; passInput.forceActiveFocus() }
    }

    Column {
        anchors.centerIn: parent
        spacing: 12
        width: 300

        // Username (prefilled with the last user)
        Rectangle {
            width: parent.width; height: 42; radius: 6; color: surface
            border.width: userInput.activeFocus ? 1 : 0; border.color: accent
            Text {
                anchors.fill: parent; anchors.leftMargin: 13
                verticalAlignment: Text.AlignVCenter
                text: "Username"; color: subtext; font.pixelSize: 15
                visible: userInput.text.length === 0
            }
            TextInput {
                id: userInput
                anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                verticalAlignment: TextInput.AlignVCenter
                color: textcol; font.pixelSize: 15; clip: true; selectByMouse: true
                text: (typeof userModel !== "undefined" && userModel.lastUser) ? userModel.lastUser : ""
                KeyNavigation.tab: passInput
                onAccepted: passInput.forceActiveFocus()
            }
        }

        // Password
        Rectangle {
            width: parent.width; height: 42; radius: 6; color: surface
            border.width: passInput.activeFocus ? 1 : 0; border.color: accent
            Text {
                anchors.fill: parent; anchors.leftMargin: 13
                verticalAlignment: Text.AlignVCenter
                text: "Password"; color: subtext; font.pixelSize: 15
                visible: passInput.text.length === 0
            }
            TextInput {
                id: passInput
                anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                verticalAlignment: TextInput.AlignVCenter
                color: textcol; font.pixelSize: 15; clip: true; selectByMouse: true
                echoMode: TextInput.Password; passwordCharacter: "•"
                KeyNavigation.tab: userInput
                onAccepted: root.doLogin()
            }
        }
    }

    // Small power controls, top-right
    Row {
        anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 22
        spacing: 18
        Text {
            text: "Reboot"; color: subtext; font.pixelSize: 13
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sddm.reboot() }
        }
        Text {
            text: "Power Off"; color: subtext; font.pixelSize: 13
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sddm.powerOff() }
        }
    }

    Component.onCompleted: {
        if (userInput.text === "") userInput.forceActiveFocus()
        else passInput.forceActiveFocus()
    }
}
