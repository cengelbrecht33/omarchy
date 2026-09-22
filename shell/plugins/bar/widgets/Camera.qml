import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.camera"

  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []

  function isVideoSource(node) {
    if (!node || node.isStream) return false
    var kind = String(node.type || "")
    return kind.indexOf("VideoSource") !== -1 || kind.indexOf("Video/Source") !== -1
  }

  readonly property bool pipewireCamera: {
    for (var i = 0; i < root.nodes.length; i++) {
      if (root.isVideoSource(root.nodes[i])) return true
    }
    return false
  }

  // "absent", "idle", or "busy". The probe covers apps that open /dev/video*
  // directly; PipeWire only labels the camera device, not the capture stream.
  property string cameraState: "absent"
  readonly property bool present: pipewireCamera || cameraState !== "absent"
  readonly property bool inUse: cameraState === "busy"

  visible: present
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  PwObjectTracker {
    objects: {
      var list = []
      for (var i = 0; i < root.nodes.length; i++) {
        if (root.isVideoSource(root.nodes[i])) list.push(root.nodes[i])
      }
      return list
    }
  }

  function probePath() {
    var path = Qt.resolvedUrl("camera-busy.sh").toString()
    if (path.indexOf("file://") === 0)
      path = decodeURIComponent(path.substring(7))
    return path
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (busyProc.running) return
      busyProc.command = [root.probePath()]
      busyProc.running = true
    }
  }

  Process {
    id: busyProc
    stdout: StdioCollector {
      id: busyOut
      waitForEnd: true
    }
    onExited: function(code) {
      var state = String(busyOut.text || "").trim()
      if (state === "busy" || state === "idle" || state === "absent")
        root.cameraState = state
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.inUse ? "󰻂" : "󰄀"
    active: root.inUse
    tooltipText: root.inUse ? "Camera in use" : "Camera live"
  }
}
