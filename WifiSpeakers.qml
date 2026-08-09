import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  // Injected by Omarchy's plugin host.
  property var shell: null
  property var manifest: null

  readonly property string pluginId: manifest && manifest.id ? manifest.id : "stappmus.wifi-speakers"
  readonly property string backendPath: decodeURIComponent(
    String(Qt.resolvedUrl("scripts/audio-output")).replace("file://", ""))
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
  readonly property string cacheDir: runtimeDir + "/omarchy-wifi-speakers"
  readonly property string snapshotPath: cacheDir + "/snapshot.json"
  readonly property string discoveryService: "omarchy-audio-speaker-discovery.service"

  property bool opened: false
  property var speakers: []
  property string discoveryStatus: "scanning"
  property string currentKind: "internal"
  property string currentSpeakerId: ""
  property string currentLabel: "Internal speakers"
  property string pendingKind: ""
  property string pendingSpeakerId: ""
  property string pendingProtocol: ""
  property string pendingLabel: ""
  property string errorMessage: ""
  property int selectedIndex: 0
  property bool selectionPinned: false
  property bool cacheDirectoryReady: false
  property bool currentRefreshQueued: false
  property string lastCacheRaw: "\u0000"
  property string lastModelSignature: ""

  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int rowSpacing: Style.spacing.xs
  readonly property int rowHeight: Math.max(Style.space(62), Style.font.heading + Style.font.bodySmall + Style.space(25))
  readonly property int headerHeight: Math.max(Style.space(68), Style.font.heading + Style.font.bodySmall + Style.space(24))
  readonly property int footerHeight: Math.max(Style.space(28), Style.font.caption + Style.space(12))
  readonly property int listHeight: Math.min(outputModel.count, 6) * rowHeight
    + Math.max(0, Math.min(outputModel.count, 6) - 1) * rowSpacing
  readonly property int cardWidth: Math.min(Style.space(500), panel.width - Style.gapsOut * 2)
  readonly property int cardHeight: Math.min(
    card.contentTopInset + card.contentBottomInset
      + headerHeight + Style.spacing.md + listHeight + Style.spacing.md + footerHeight,
    panel.height - Style.gapsOut * 2
  )

  readonly property string subtitle: {
    if (routeProcess.running) {
      return pendingKind === "internal"
        ? "Switching to internal speakers..."
        : "Connecting to " + pendingLabel + "..."
    }
    if (errorMessage) return errorMessage
    if (discoveryStatus === "scanning") return "Current: " + currentLabel + " · scanning"
    if (discoveryStatus === "error") return "Current: " + currentLabel + " · discovery unavailable"
    return "Current: " + currentLabel
  }

  function open(_payloadJson) {
    opened = true
    errorMessage = ""
    selectionPinned = false
    pointerGate.reset()
    selectCurrentRow()
    ensureDiscovery(false)
    refreshCache()
    refreshCurrent()
    Qt.callLater(function() {
      if (keyCatcher) keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    opened = false
  }

  function ping(_arg) {
    return "ok"
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else opened = false
  }

  function applySnapshot(raw) {
    var snapshotRaw = String(raw || "")
    if (snapshotRaw === lastCacheRaw) return

    try {
      var snapshot = JSON.parse(snapshotRaw)
      var status = String(snapshot.status || "")
      if (snapshot.schemaVersion !== 1
          || (status !== "ready" && status !== "scanning" && status !== "error")
          || !Array.isArray(snapshot.speakers)) return

      var parsed = []
      for (var i = 0; i < snapshot.speakers.length; i++) {
        var item = snapshot.speakers[i] || {}
        var protocol = String(item.protocol || "")
        var speakerId = String(item.speakerId || "")
        if (!speakerId || (protocol !== "cast" && protocol !== "raop")) continue
        parsed.push({
          speakerId: speakerId,
          label: String(item.label || "Wi-Fi speaker"),
          protocol: protocol,
          serviceName: String(item.serviceName || ""),
          host: String(item.host || ""),
          address: String(item.address || ""),
          port: String(item.port || ""),
          transport: String(item.transport || ""),
          encryptionCodec: String(item.encryptionCodec || ""),
          model: String(item.model || "")
        })
      }

      lastCacheRaw = snapshotRaw
      cacheDirectoryReady = true
      discoveryStatus = status
      speakers = status === "error" ? [] : parsed
      rebuildRows()
    } catch (_error) {
      // Atomic replacement should make parse errors impossible. Keep the
      // last coherent generation if a filesystem read is interrupted.
    }
  }

  function snapshotLoadFailed() {
    speakers = []
    lastCacheRaw = "\u0000"
    discoveryStatus = "scanning"
    rebuildRows()
  }

  function speakerDetail(speaker) {
    var protocol = speaker.protocol === "cast" ? "Google Cast" : "AirPlay"
    if (speaker.model && speaker.model !== "Google Cast speaker" && speaker.model !== "AirPlay speaker")
      return speaker.model + " · " + protocol
    return protocol
  }

  function rowKey(row) {
    if (!row) return ""
    return row.kind + ":" + row.speakerId
  }

  function selectCurrentRow() {
    var nextIndex = 0
    for (var i = 0; i < outputModel.count; i++) {
      if (outputModel.get(i).current) {
        nextIndex = i
        break
      }
    }
    selectedIndex = nextIndex
    Qt.callLater(function() {
      if (resultList && outputModel.count > 0)
        resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function isCurrent(kind, speakerId) {
    if (kind === "internal") return currentKind === "internal"
    return kind === "speaker" && currentKind !== "internal"
      && speakerId !== "" && speakerId === currentSpeakerId
  }

  function outputSignature() {
    var available = []
    for (var i = 0; i < speakers.length; i++) {
      available.push([
        speakers[i].speakerId,
        speakers[i].label,
        speakers[i].protocol,
        speakers[i].model
      ])
    }
    return JSON.stringify([
      discoveryStatus,
      currentKind,
      currentSpeakerId,
      available
    ])
  }

  function rebuildRows() {
    var signature = outputSignature()
    if (signature === lastModelSignature) return
    lastModelSignature = signature
    pointerGate.reset()

    var wantedKey = ""
    if (selectedIndex >= 0 && selectedIndex < outputModel.count)
      wantedKey = rowKey(outputModel.get(selectedIndex))

    outputModel.clear()
    outputModel.append({
      kind: "internal",
      speakerId: "",
      protocol: "internal",
      label: "Internal speakers",
      detail: "This computer",
      selectable: true,
      current: isCurrent("internal", "")
    })

    if (discoveryStatus === "ready" || discoveryStatus === "scanning") {
      for (var i = 0; i < speakers.length; i++) {
        var speaker = speakers[i]
        outputModel.append({
          kind: "speaker",
          speakerId: speaker.speakerId,
          protocol: speaker.protocol,
          label: speaker.label,
          detail: speakerDetail(speaker),
          selectable: true,
          current: isCurrent("speaker", speaker.speakerId)
        })
      }
    }

    if (discoveryStatus === "scanning") {
      outputModel.append({
        kind: "status",
        speakerId: "",
        protocol: "",
        label: "Scanning for Wi-Fi speakers...",
        detail: "Speakers appear here as they are detected",
        selectable: false,
        current: false
      })
    } else if (discoveryStatus === "error") {
      outputModel.append({
        kind: "retry",
        speakerId: "",
        protocol: "",
        label: "Speaker discovery unavailable",
        detail: "Press Enter to try again",
        selectable: true,
        current: false
      })
    } else if (speakers.length === 0) {
      outputModel.append({
        kind: "retry",
        speakerId: "",
        protocol: "",
        label: "No Wi-Fi speakers found",
        detail: "Press Enter to scan again",
        selectable: true,
        current: false
      })
    }

    var nextIndex = -1
    if (!selectionPinned) {
      for (var currentIndex = 0; currentIndex < outputModel.count; currentIndex++) {
        if (outputModel.get(currentIndex).current) {
          nextIndex = currentIndex
          break
        }
      }
    } else if (wantedKey) {
      for (var wantedIndex = 0; wantedIndex < outputModel.count; wantedIndex++) {
        if (rowKey(outputModel.get(wantedIndex)) === wantedKey) {
          nextIndex = wantedIndex
          break
        }
      }
    }
    if (nextIndex < 0) nextIndex = 0
    selectedIndex = nextIndex
    Qt.callLater(function() {
      if (resultList && outputModel.count > 0)
        resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function parseCurrent(raw) {
    try {
      var current = JSON.parse(String(raw || "{}"))
      if (!current || (current.kind !== "internal" && current.kind !== "cast" && current.kind !== "raop"))
        return
      currentKind = current.kind
      currentSpeakerId = String(current.speakerId || "")
      currentLabel = String(current.label || (current.kind === "internal" ? "Internal speakers" : "Wi-Fi speaker"))
      rebuildRows()
    } catch (_error) {
      // Preserve the last known selection if the audio service is restarting.
    }
  }

  function refreshCache() {
    snapshotFile.reload()
  }

  function refreshCurrent() {
    if (currentProcess.running) {
      currentRefreshQueued = true
      return
    }
    currentRefreshQueued = false
    currentProcess.command = [backendPath, "current", "--json"]
    currentProcess.running = true
  }

  function ensureDiscovery(restart) {
    if (serviceProcess.running) return
    if (restart) {
      speakers = []
      lastCacheRaw = "\u0000"
      discoveryStatus = "scanning"
      errorMessage = ""
      rebuildRows()
    }
    serviceProcess.command = ["systemctl", "--user", restart ? "restart" : "start", discoveryService]
    serviceProcess.running = true
  }

  function selectByDelta(delta) {
    if (outputModel.count === 0) return
    pointerGate.reset()
    selectionPinned = true
    var index = selectedIndex
    for (var i = 0; i < outputModel.count; i++) {
      index = (index + delta + outputModel.count) % outputModel.count
      if (outputModel.get(index).selectable) {
        selectedIndex = index
        resultList.positionViewAtIndex(index, ListView.Contain)
        return
      }
    }
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    selectionPinned = true
    selectedIndex = index
  }

  function activateIndex(index) {
    if (routeProcess.running || index < 0 || index >= outputModel.count) return
    var row = outputModel.get(index)
    if (!row.selectable) return
    if (row.kind === "retry") {
      ensureDiscovery(true)
      return
    }
    if (row.current) {
      requestClose()
      return
    }

    pendingKind = row.kind
    pendingSpeakerId = row.speakerId
    pendingProtocol = row.protocol
    pendingLabel = row.label
    errorMessage = ""
    routeProcess.command = row.kind === "internal"
      ? [backendPath, "internal"]
      : [backendPath, "connect", row.speakerId, row.protocol]
    routeProcess.running = true
  }

  Component.onCompleted: {
    rebuildRows()
    ensureDiscovery(false)
    refreshCache()
    refreshCurrent()
  }

  ListModel {
    id: outputModel
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  FileView {
    id: directoryWatcher
    path: root.cacheDirectoryReady ? root.cacheDir : ""
    watchChanges: true
    printErrors: false
    onFileChanged: refreshDebounce.restart()
  }

  FileView {
    id: snapshotFile
    path: root.snapshotPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applySnapshot(text())
    onLoadFailed: root.snapshotLoadFailed()
    onFileChanged: refreshDebounce.restart()
  }

  Timer {
    id: refreshDebounce
    interval: 60
    onTriggered: root.refreshCache()
  }

  Timer {
    interval: 2000
    running: root.opened
    repeat: true
    onTriggered: root.refreshCache()
  }

  Timer {
    id: currentRefresh
    interval: 150
    onTriggered: root.refreshCurrent()
  }

  Process {
    id: currentProcess
    stdout: StdioCollector {
      id: currentOutput
      waitForEnd: true
    }
    onExited: {
      root.parseCurrent(currentOutput.text)
      if (root.currentRefreshQueued) Qt.callLater(root.refreshCurrent)
    }
  }

  Process {
    id: serviceProcess
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.speakers = []
        root.lastCacheRaw = "\u0000"
        root.discoveryStatus = "error"
        root.rebuildRows()
      } else {
        root.cacheDirectoryReady = false
        Qt.callLater(function() {
          root.cacheDirectoryReady = true
          refreshDebounce.restart()
        })
      }
    }
  }

  Process {
    id: routeProcess
    stderr: StdioCollector {
      id: routeError
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var completedKind = root.pendingKind
      var completedId = root.pendingSpeakerId
      var completedProtocol = root.pendingProtocol
      var completedLabel = root.pendingLabel
      root.pendingKind = ""
      root.pendingSpeakerId = ""
      root.pendingProtocol = ""
      root.pendingLabel = ""

      if (exitCode === 0) {
        root.currentKind = completedKind === "internal" ? "internal" : completedProtocol
        root.currentSpeakerId = completedId
        root.currentLabel = completedLabel
        root.errorMessage = ""
        root.rebuildRows()
        root.requestClose()
      } else {
        root.errorMessage = completedKind === "internal"
          ? "Could not switch to internal speakers"
          : "Could not connect to " + completedLabel
        root.rebuildRows()
      }
      currentRefresh.restart()
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-wifi-speakers"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.requestClose()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      anchors.centerIn: parent
      radius: Style.cornerRadius
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: root.opened

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.requestClose()
            event.accepted = true
          } else if (event.key === Qt.Key_Up || event.text === "k") {
            root.selectByDelta(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down || event.text === "j") {
            root.selectByDelta(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.activateIndex(root.selectedIndex)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.md

        Item {
          width: parent.width
          height: root.headerHeight

          Column {
            anchors.left: parent.left
            anchors.right: escapeHint.left
            anchors.rightMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(5)

            Text {
              width: parent.width
              text: "Wi-Fi speakers"
              color: Color.menu.text
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.heading
              font.weight: Font.DemiBold
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              text: root.subtitle
              color: root.errorMessage ? Color.urgent : Color.menu.text
              opacity: root.errorMessage ? 1 : 0.58
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
          }

          Text {
            id: escapeHint
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "Esc"
            color: Color.menu.text
            opacity: 0.4
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }
        }

        Item {
          width: parent.width
          height: Math.max(0, parent.height - root.headerHeight
            - root.footerHeight - Style.spacing.md * 2)

          ListView {
            id: resultList
            anchors.fill: parent
            model: outputModel
            clip: true
            spacing: root.rowSpacing
            boundsBehavior: Flickable.StopAtBounds

            delegate: BorderSurface {
              id: row
              required property int index
              required property string kind
              required property string speakerId
              required property string protocol
              required property string label
              required property string detail
              required property bool selectable
              required property bool current

              readonly property bool hasCursor: selectable && index === root.selectedIndex
              readonly property bool connecting: routeProcess.running
                && ((kind === "internal" && root.pendingKind === "internal")
                  || (kind === "speaker" && speakerId === root.pendingSpeakerId))

              width: ListView.view.width
              height: root.rowHeight
              radius: Style.cornerRadius
              color: hasCursor ? Color.menu.selectedBackground : "transparent"
              borderSpec: hasCursor
                ? Border.surfaceSpec("menu", "selected-border", Color.menu.selectedBorder, 0)
                : Border.none()
              opacity: selectable ? 1 : 0.68

              Text {
                id: rowIcon
                width: Style.space(34)
                anchors.left: parent.left
                anchors.leftMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                text: row.kind === "internal" ? "\uf028"
                  : (row.kind === "speaker" ? "\uf1eb" : "\u21bb")
                color: row.hasCursor ? Color.menu.selectedText : Color.menu.text
                font.family: Style.font.family
                font.pixelSize: Style.font.iconLarge
                horizontalAlignment: Text.AlignHCenter

                NumberAnimation on rotation {
                  from: 0
                  to: 360
                  duration: 900
                  loops: Animation.Infinite
                  running: root.opened && row.kind === "status"
                }
              }

              Column {
                anchors.left: rowIcon.right
                anchors.leftMargin: Style.space(8)
                anchors.right: rowTrail.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(3)

                Text {
                  width: parent.width
                  text: row.connecting ? (row.kind === "internal" ? "Switching..." : "Connecting...") : row.label
                  color: row.hasCursor ? Color.menu.selectedText : Color.menu.text
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.heading
                  font.weight: Font.Medium
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: row.detail
                  color: row.hasCursor ? Color.menu.selectedText : Color.menu.text
                  opacity: row.hasCursor ? 0.72 : 0.5
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
              }

              Text {
                id: rowTrail
                width: Style.space(76)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                text: row.connecting ? "Working" : (row.current ? "\u2713 Current" : "")
                color: row.hasCursor ? Color.menu.selectedText : Color.menu.text
                opacity: row.current || row.connecting ? 0.72 : 0
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                horizontalAlignment: Text.AlignRight
              }

              MouseArea {
                anchors.fill: parent
                enabled: row.selectable && !routeProcess.running
                hoverEnabled: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onPositionChanged: function(mouse) {
                  root.selectFromPointer(row.index, row, mouse)
                }
                onClicked: {
                  root.selectionPinned = true
                  root.selectedIndex = row.index
                  root.activateIndex(row.index)
                }
              }
            }
          }
        }

        Text {
          width: parent.width
          height: root.footerHeight
          text: "\u2191/\u2193 select · Enter connect · Super+Mute close"
          color: Color.menu.text
          opacity: 0.38
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          elide: Text.ElideRight
        }
      }
    }
  }
}
