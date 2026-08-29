import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "koka.umbrella"
  manageIpc: false

  property var anchorItem: null
  property bool openedFromHotkey: false

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget: the popout coordinator (and with it the open-panel dot under the
  // pill) compares against `slot.activeItem`, and switchPanelFrom looks the
  // slot up the same way.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property string barForeground: root.bar ? root.bar.foreground : Color.foreground
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  function open() {
    openedFromHotkey = false
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
    locationFile.reload()
    root.refresh()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    locationFile.reload()
    root.refresh()
    // Set after showing, not before: showing hands the popout coordinator
    // over, which closes whichever panel was open, and that close clears the
    // shared flag. Deferring means the panel taking over always wins, while
    // a handoff to a panel that does not manage the flag still leaves it
    // cleared rather than stuck on.
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    if (root.editingLocation) root.cancelEditingLocation()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  // ---- Rain state ---------------------------------------------------------
  //
  // One source (Open-Meteo hourly precipitation), one fetch, one state
  // object. Kept on failure so the bar keeps showing the last verdict.
  property var forecast: null
  property var rain: ({ state: "none", minutesUntil: -1, mm: 0 })
  property bool fetchedOnce: false
  property int forecastRetries: 0

  // Bar text: quiet sun while dry, countdown as soon as rain matters. An
  // ellipsis until the first verdict lands, so the bar never lies about
  // data it doesn't have yet.
  readonly property string barText: {
    if (!root.fetchedOnce) return "…"
    var label = Model.barLabel(root.rain)
    return label !== "" ? label : "☀️"
  }

  readonly property var rainWindows: {
    var hourly = root.forecast && root.forecast.hourly
    if (!hourly || !hourly.precipitation || !hourly.time) return []
    return Model.rainWindows(hourly.precipitation, hourly.time, new Date(), Model.LATER_HOURS, Model.SOON_THRESHOLD)
  }

  readonly property string rainStatusLine: {
    if (!root.fetchedOnce) return "Waiting for forecast…"
    if (root.rain.state === "soon")
      return "☔ Rain starting in " + Math.max(0, root.rain.minutesUntil) + " min"
    if (root.rain.state === "later") {
      var t = new Date(Date.now() + root.rain.minutesUntil * 60000)
      return "🌂 Rain at " + Qt.formatTime(t, "HH:mm")
    }
    return "☀️ Dry for the next 16 hours"
  }

  // ---- Location -----------------------------------------------------------
  //
  // Configured coordinates come from weather.json (owned by
  // omarchy-weather-location); without them the widget falls back to an
  // approximate IP-geolocated position, refreshed with every cycle.
  property var configuredLocationState: ({ name: "", latitude: null, longitude: null })
  property var ipLocation: null

  readonly property bool hasConfiguredCoordinates: !isNaN(parseFloat(String(configuredLocationState.latitude))) && !isNaN(parseFloat(String(configuredLocationState.longitude)))
  readonly property var activeLocation: hasConfiguredCoordinates ? configuredLocationState : ipLocation
  readonly property string locationName: activeLocation ? activeLocation.name : ""
  readonly property bool usingIpGeo: !hasConfiguredCoordinates && ipLocation !== null

  // Auto-refresh interval in minutes; clamped to a sane minimum.
  readonly property int refreshMinutes: Math.max(1, parseInt(setting("refreshMinutes", 15), 10) || 15)

  property FileView locationFile: FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/weather.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.configuredLocationState = Model.parseLocationFile(text())
    onLoadFailed: root.configuredLocationState = Model.parseLocationFile("")
  }

  // The first read can race shell startup (observed sporadically), leaving a
  // stored location unhonored until the next file write. One delayed reload
  // self-corrects; if the first read was fine it's a no-op, since identical
  // state doesn't change the location and so triggers no refetch.
  Timer {
    interval: 1500
    running: true
    onTriggered: locationFile.reload()
  }

  onConfiguredLocationStateChanged: Qt.callLater(root.refresh)

  // ---- Location editing. Clicking the location label swaps it for a search
  //      field; picking a geocoded suggestion persists name + coordinates via
  //      omarchy-weather-location. An empty commit returns to auto.
  property bool editingLocation: false
  property bool savingLocation: false
  property var locationSuggestions: []
  property int suggestionIndex: 0
  property string geocodePendingQuery: ""
  property string geocodeActiveQuery: ""

  function startEditingLocation() {
    editingLocation = true
    savingLocation = false
    locationSuggestions = []
    suggestionIndex = 0
    Qt.callLater(function() {
      locationField.text = root.configuredLocationState.name || root.locationName
      locationField.selectAll()
      locationField.forceActiveFocus()
    })
  }

  function cancelEditingLocation() {
    editingLocation = false
    savingLocation = false
    locationSuggestions = []
    geocodeDebounce.stop()
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function commitLocation() {
    var location = Model.locationCommit(locationField.text, locationSuggestions, suggestionIndex)
    if (location.name === "") {
      clearLocation()
      return
    }
    configuredLocationState = {
      name: location.name,
      latitude: location.latitude,
      longitude: location.longitude
    }
    persistLocation(location.name, location.latitude, location.longitude)
    cancelEditingLocation()
  }

  function clearLocation() {
    persistLocation("", null, null)
    cancelEditingLocation()
  }

  function pickSuggestion(suggestion) {
    if (!suggestion) return
    configuredLocationState = {
      name: suggestion.name,
      latitude: suggestion.latitude,
      longitude: suggestion.longitude
    }
    persistLocation(suggestion.name, suggestion.latitude, suggestion.longitude)
    cancelEditingLocation()
  }

  function persistLocation(name, latitude, longitude) {
    savingLocation = true
    if (name && latitude !== null && longitude !== null)
      locationSaveProc.command = ["omarchy-weather-location", "--set", name, latitude + "," + longitude]
    else if (name)
      locationSaveProc.command = ["omarchy-weather-location", "--set", name]
    else
      locationSaveProc.command = ["omarchy-weather-location", "--clear"]
    locationSaveProc.running = true
  }

  // ---- Refresh ------------------------------------------------------------
  function refresh() {
    // Each full refresh cycle gets a fresh retry budget, so an earlier
    // exhausted round (e.g. waking with the network still down) doesn't
    // starve retries for the rest of the session.
    forecastRetries = 0
    if (hasConfiguredCoordinates) {
      fetchForecast(parseFloat(String(configuredLocationState.latitude)), parseFloat(String(configuredLocationState.longitude)))
    } else if (!ipGeoProc.running) {
      ipGeoProc.running = true
    }
  }

  function fetchForecast(lat, lon) {
    if (isNaN(lat) || isNaN(lon)) return
    forecastProc.command = ["curl", "-fsS", "--max-time", "6",
      "https://api.open-meteo.com/v1/forecast"
      + "?latitude=" + encodeURIComponent(String(lat))
      + "&longitude=" + encodeURIComponent(String(lon))
      + "&hourly=precipitation"
      + "&forecast_days=2"
      + "&timezone=auto"]
    forecastProc.running = true
  }

  function applyForecast(parsed) {
    forecast = parsed
    var hourly = parsed && parsed.hourly
    if (hourly && hourly.precipitation && hourly.time)
      rain = Model.nextRain(hourly.precipitation, hourly.time, new Date())
    else
      rain = { state: "none", minutesUntil: -1, mm: 0 }
    fetchedOnce = true
  }

  // A dropped response (e.g. waking before the network is back) retries a
  // few times rather than waiting out the refresh timer with a stale verdict.
  function scheduleForecastRetry() {
    if (forecastRetries >= 3) return
    forecastRetries++
    forecastRetryTimer.restart()
  }

  // ---- Right-click notification -------------------------------------------
  function notifyUmbrella() {
    var text = ""
    if (root.rain.state === "soon") {
      text = "☔ Rain in " + Math.max(0, root.rain.minutesUntil) + " min (" + root.rain.mm + " mm/h)"
    } else if (root.rain.state === "later") {
      var t = new Date(Date.now() + root.rain.minutesUntil * 60000)
      text = "🌂 Rain at " + Qt.formatTime(t, "HH:mm") + " (" + root.rain.mm + " mm/h)"
    } else {
      text = "☀️ No rain expected in the next 16 hours"
    }
    notifyProc.command = ["omarchy-notification-send", text]
    notifyProc.running = true
  }

  // ---- Processes & timers -------------------------------------------------
  Process {
    id: forecastProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) {
          root.scheduleForecastRetry()
          return
        }
        try {
          root.applyForecast(JSON.parse(raw))
          root.forecastRetries = 0
        } catch (e) {
          // Keep last-good verdict visible, but try again shortly.
          root.scheduleForecastRetry()
        }
      }
    }
  }

  Timer {
    id: forecastRetryTimer
    interval: 2500
    onTriggered: {
      if (root.hasConfiguredCoordinates && root.activeLocation)
        root.fetchForecast(parseFloat(String(root.activeLocation.latitude)), parseFloat(String(root.activeLocation.longitude)))
      else if (!root.hasConfiguredCoordinates && !ipGeoProc.running)
        ipGeoProc.running = true
    }
  }

  // Approximate position when nothing is configured. One curl, no key;
  // failure just leaves the previous position (or none) in place.
  Process {
    id: ipGeoProc
    command: ["curl", "-fsS", "--max-time", "5", "https://ipwho.is/"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var loc = Model.parseIpGeo(text)
        if (loc) {
          root.ipLocation = loc
          root.fetchForecast(loc.latitude, loc.longitude)
        } else {
          root.scheduleForecastRetry()
        }
      }
    }
  }

  Process {
    id: locationSaveProc
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.savingLocation = false
        return
      }
      // FileView watch picks the new state up; reload explicitly so saving
      // the already-active location still refreshes deterministically.
      locationFile.reload()
      root.savingLocation = false
    }
  }

  // Debounced geocoding. Only one curl runs at a time; if the query moved on
  // while a fetch was in flight, the latest query is fetched right after.
  function requestGeocode() {
    var query = locationField.text.trim()
    if (query.length < 2) {
      locationSuggestions = []
      return
    }
    geocodePendingQuery = query
    if (!geocodeProc.running) startGeocode()
  }

  function startGeocode() {
    if (geocodePendingQuery === "") return
    geocodeActiveQuery = geocodePendingQuery
    geocodeProc.command = ["curl", "-fsS", "--max-time", "5",
      "https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(geocodeActiveQuery) + "&count=5&language=en&format=json"]
    geocodeProc.running = true
  }

  Process {
    id: geocodeProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.locationSuggestions = root.editingLocation ? Model.parseGeocodingResults(text) : []
        root.suggestionIndex = 0
        if (root.geocodePendingQuery !== root.geocodeActiveQuery) Qt.callLater(root.startGeocode)
      }
    }
  }

  Timer {
    id: geocodeDebounce
    interval: 300
    onTriggered: root.requestGeocode()
  }

  Process {
    id: notifyProc
  }

  Timer {
    id: refreshTimer
    interval: root.refreshMinutes * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // ---- Panel --------------------------------------------------------------
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(umbrellaColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editingLocation
      onReturnRequested: root.startEditingLocation()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: umbrellaScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: umbrellaColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: umbrellaColumn
          width: umbrellaScroll.width
          spacing: Style.space(14)
          padding: Style.space(4)

          // ---- Rain -----------------------------------------------------
          Column {
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: "RAIN"
              color: Qt.darker(root.barForeground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
              font.bold: true
            }

            Text {
              width: parent.width
              text: root.rainStatusLine
              color: root.barForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              elide: Text.ElideRight
            }

            Column {
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: root.rainWindows

                Item {
                  id: windowRow
                  required property var modelData
                  width: parent.width
                  height: Style.space(22)

                  Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "  " + Qt.formatTime(windowRow.modelData.start, "HH:mm") + " – " + Qt.formatTime(windowRow.modelData.end, "HH:mm")
                    color: root.barForeground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: windowRow.modelData.mm + " mm"
                    color: Qt.darker(root.barForeground, 1.4)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                }
              }
            }
          }

          // ---- Location -------------------------------------------------
          Column {
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: "LOCATION"
              color: Qt.darker(root.barForeground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
              font.bold: true
            }

            Row {
              visible: !root.editingLocation
              spacing: Style.space(6)

              TapHandler {
                onTapped: root.startEditingLocation()
              }
              HoverHandler {
                cursorShape: Qt.PointingHandCursor
              }

              Text {
                text: ""  // nf-fa-map_marker
                color: Qt.darker(root.barForeground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                text: root.locationName !== "" ? root.locationName : "Set location"
                color: Qt.darker(root.barForeground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.italic: root.locationName === ""
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                visible: root.usingIpGeo
                text: "· approximate"
                color: Qt.darker(root.barForeground, 1.8)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Row {
              visible: root.editingLocation
              spacing: Style.space(6)

              TextField {
                id: locationField
                width: Style.space(190)
                enabled: !root.savingLocation
                placeholderText: "Search city"
                foreground: root.barForeground
                font.family: root.fontFamily

                onTextChanged: if (root.editingLocation && !root.savingLocation) geocodeDebounce.restart()

                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) {
                    root.cancelEditingLocation()
                    event.accepted = true
                  } else if (event.key === Qt.Key_Down) {
                    if (root.suggestionIndex < root.locationSuggestions.length - 1) root.suggestionIndex++
                    event.accepted = true
                  } else if (event.key === Qt.Key_Up) {
                    if (root.suggestionIndex > 0) root.suggestionIndex--
                    event.accepted = true
                  } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.commitLocation()
                    event.accepted = true
                  }
                }
              }

              // Clear back to IP auto-detect. While a committed location is
              // saving, this same compact affordance becomes a spinner.
              Rectangle {
                width: Style.space(18)
                height: Style.space(18)
                anchors.verticalCenter: parent.verticalCenter
                radius: Math.min(4, Style.cornerRadius)
                color: !root.savingLocation && clearLocationArea.containsMouse ? Style.hoverFillFor(root.barForeground, Color.accent) : "transparent"

                Text {
                  anchors.centerIn: parent
                  text: root.savingLocation ? "󰦖" : "✕"
                  font.family: root.fontFamily
                  color: Qt.darker(root.barForeground, 1.4)
                  font.pixelSize: Style.font.bodySmall

                  RotationAnimator on rotation {
                    running: root.savingLocation
                    from: 0; to: 360
                    duration: 800
                    loops: Animation.Infinite
                  }
                }

                MouseArea {
                  id: clearLocationArea
                  anchors.fill: parent
                  enabled: !root.savingLocation
                  hoverEnabled: true
                  cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: root.clearLocation()
                }
              }
            }

            // ---- Geocoding suggestions while the location is being edited.
            Column {
              visible: root.editingLocation && !root.savingLocation && root.locationSuggestions.length > 0
              width: parent.width
              spacing: Style.space(2)

              Repeater {
                model: root.locationSuggestions

                Rectangle {
                  id: suggestionRow
                  required property var modelData
                  required property int index
                  width: parent.width
                  height: Style.space(34)
                  radius: Style.cornerRadius
                  color: root.suggestionIndex === index
                    ? Style.selectedFillFor(root.barForeground, Color.accent)
                    : (rowHover.hovered ? Style.hoverFillFor(root.barForeground, Color.accent) : "transparent")

                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(8)
                    spacing: 0

                    Text {
                      text: suggestionRow.modelData.name
                      color: root.barForeground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }

                    Text {
                      visible: suggestionRow.modelData.description !== ""
                      text: suggestionRow.modelData.description
                      color: Qt.darker(root.barForeground, 1.6)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  MouseArea {
                    id: rowHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.pickSuggestion(suggestionRow.modelData)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
