import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "koka.weather"
  ipcTarget: "omarchy.weather"
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

  // Parsed wttr.in j1 response. Kept on failure so stale data stays visible.
  property var report: null
  property var dailyForecastReport: null
  property string wttrLocation: ""

  // Configured location, read from the weather.json state file (owned by
  // omarchy-weather-location). The query is the wttr.in path segment
  // (coordinates when stored, else the encoded name); empty means IP
  // auto-detect. The watch makes hand edits take effect live.
  property var configuredLocationState: ({ name: "", latitude: null, longitude: null })
  readonly property string configuredLocation: configuredLocationState.name
  readonly property string locationQuery: Model.wttrLocationQuery(configuredLocationState.name, configuredLocationState.latitude, configuredLocationState.longitude)

  // Keep the previous report visible while the new location loads. The
  // editor remains open with a spinner, so stale data is never presented
  // under the newly configured location label.
  onLocationQueryChanged: {
    if (savingLocation) savingLocationQueryStarted = true
    forecastRetries = 0
    dailyForecastRetries = 0
    forecastProc.running = false
    dailyForecastProc.running = false
    Qt.callLater(refresh)
  }

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
  // state doesn't change locationQuery and so triggers no refetch.
  Timer {
    interval: 1500
    running: true
    onTriggered: locationFile.reload()
  }

  property int forecastRetries: 0
  property int dailyForecastRetries: 0

  // Click-to-edit state for the location label.
  property bool editingLocation: false
  property bool savingLocation: false
  property bool savingLocationQueryStarted: false
  property var locationSuggestions: []
  property int suggestionIndex: 0
  property string geocodePendingQuery: ""
  property string geocodeActiveQuery: ""

  // Shared hero/bar icon state, updated with each successful weather response.
  property string label: ""
  property bool needUmbrellaSoon: false
  property bool needUmbrellaToday: false
  property int minutesUntilRain: -1  // Minutes until rain starts, -1 if no rain expected

  // wttr's current conditions when available; open-meteo's (bundled with the
  // much faster daily forecast fetch) fill the hero while wttr is in flight.
  readonly property bool hasConfiguredCoordinates: !isNaN(parseFloat(String(configuredLocationState.latitude))) && !isNaN(parseFloat(String(configuredLocationState.longitude)))
  readonly property var openMeteoCurrent: Model.openMeteoCurrentCondition(dailyForecastReport)
  readonly property var current: (hasConfiguredCoordinates && openMeteoCurrent) ? openMeteoCurrent : ((report && report.current_condition && report.current_condition[0]) ? report.current_condition[0] : openMeteoCurrent)
  readonly property var areaInfo: report && report.nearest_area && report.nearest_area[0] ? report.nearest_area[0] : null
  readonly property var forecastDays: buildForecastDays()
  readonly property string reportCountry: areaInfo && areaInfo.country && areaInfo.country[0] ? areaInfo.country[0].value : ""

  readonly property bool useImperial: Model.shouldUseImperial(setting("unit", ""), Qt.locale().name, reportCountry)

  // Auto-refresh interval in minutes; clamped to a sane minimum.
  readonly property int refreshMinutes: Math.max(1, parseInt(setting("refreshMinutes", 15), 10) || 15)

  readonly property string reportLocation:  configuredLocation || wttrLocation || (areaInfo && areaInfo.areaName && areaInfo.areaName[0] ? areaInfo.areaName[0].value : "")
  readonly property string reportTempNum:   current ? String(useImperial ? current.temp_F : current.temp_C) : ""
  readonly property string tempUnit:        "°" + (useImperial ? "F" : "C")
  readonly property string reportFeels:     current ? formatTemp(useImperial ? current.FeelsLikeF : current.FeelsLikeC) : ""
  readonly property string reportWind:      current ? (useImperial ? (current.windspeedMiles + " mph") : (current.windspeedKmph + " km/h")) : ""
  readonly property string reportHumidity:  current ? (current.humidity + "%") : ""

  function refresh() {
    // Each full refresh cycle gets a fresh retry budget, so an earlier
    // exhausted round (e.g. waking with the network still down) doesn't
    // starve retries for the rest of the session.
    forecastRetries = 0
    dailyForecastRetries = 0
    if (!forecastProc.running) forecastProc.running = true
    if (root.locationQuery === "" && !locationProc.running) locationProc.running = true
    // With stored coordinates this fetches open-meteo right away — no need
    // to wait for the slow wttr response. Without them it's a no-op until
    // wttr reports the detected area.
    refreshDailyForecast(null)
  }

  function refreshDailyForecast(sourceReport) {
    if (dailyForecastProc.running) return

    var lat = parseFloat(String(root.configuredLocationState.latitude))
    var lon = parseFloat(String(root.configuredLocationState.longitude))
    if (isNaN(lat) || isNaN(lon)) {
      var area = sourceReport && sourceReport.nearest_area && sourceReport.nearest_area[0] ? sourceReport.nearest_area[0] : root.areaInfo
      if (!area) return
      lat = parseFloat(String(area.latitude || ""))
      lon = parseFloat(String(area.longitude || ""))
    }
    if (isNaN(lat) || isNaN(lon)) return

    // Use Yr.no (met.no) for Norway, Open-Meteo for rest of world
    var inNorway = isInNorway(lat, lon)
    var url = ""
    
    if (inNorway) {
      url = "https://api.met.no/weatherapi/locationforecast/2.0/complete"
        + "?lat=" + encodeURIComponent(String(lat))
        + "&lon=" + encodeURIComponent(String(lon))
      dailyForecastProc.command = ["curl", "-fsS", "--max-time", "5", "-H", "User-Agent: koka.weather/1.0 github.com/SjoenH/omarchy-weather-umbrella", url]
    } else {
      url = "https://api.open-meteo.com/v1/forecast"
        + "?latitude=" + encodeURIComponent(String(lat))
        + "&longitude=" + encodeURIComponent(String(lon))
        + "&daily=weather_code,temperature_2m_max,temperature_2m_min"
        + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day"
        + "&hourly=precipitation"
        + "&forecast_days=4"
        + "&timezone=auto"
      dailyForecastProc.command = ["curl", "-fsS", "--max-time", "5", url]
    }
    
    dailyForecastProc.running = true
  }
  
  function isInNorway(lat, lon) {
    // Norway bounding box (approximate): lat 57.5-71.5, lon 4.5-31.5
    return lat >= 57.5 && lat <= 71.5 && lon >= 4.5 && lon <= 31.5
  }
  
  function convertYrSymbolToOpenMeteoCode(symbolCode) {
    // Convert Yr.no symbol codes to Open-Meteo WMO weather codes
    // Yr.no: https://api.met.no/weatherapi/weathericon/2.0/documentation
    // Open-Meteo: https://open-meteo.com/en/docs (WMO codes)
    
    // Remove _day/_night/_polartwilight suffix
    var base = symbolCode.replace(/_day|_night|_polartwilight/g, "")
    
    switch (base) {
      case "clearsky": return 0  // Clear sky
      case "fair": return 1  // Mainly clear
      case "partlycloudy": return 2  // Partly cloudy
      case "cloudy": return 3  // Overcast
      case "fog": return 45  // Fog
      case "lightrainshowers": return 80  // Light rain showers
      case "rainshowers": return 81  // Rain showers
      case "heavyrainshowers": return 82  // Heavy rain showers
      case "lightrain": return 61  // Light rain
      case "rain": return 63  // Rain
      case "heavyrain": return 65  // Heavy rain
      case "lightrainandthunder": return 95  // Thunderstorm
      case "rainandthunder": return 95  // Thunderstorm
      case "heavyrainandthunder": return 95  // Thunderstorm
      case "lightsleetshowers": return 68  // Light sleet
      case "sleetshowers": return 68  // Sleet
      case "heavysleetshowers": return 68  // Heavy sleet
      case "lightsleet": return 66  // Light sleet
      case "sleet": return 67  // Sleet
      case "heavysleet": return 68  // Heavy sleet
      case "lightsnowshowers": return 85  // Light snow showers
      case "snowshowers": return 85  // Snow showers
      case "heavysnowshowers": return 86  // Heavy snow showers
      case "lightsnow": return 71  // Light snow
      case "snow": return 73  // Snow
      case "heavysnow": return 75  // Heavy snow
      case "lightsleetandthunder": return 95  // Thunderstorm with sleet
      case "sleetandthunder": return 95  // Thunderstorm with sleet
      case "lightsnowandthunder": return 95  // Thunderstorm with snow
      case "snowandthunder": return 95  // Thunderstorm with snow
      case "heavysleetandthunder": return 95  // Thunderstorm with sleet
      case "heavysnowandthunder": return 95  // Thunderstorm with snow
      default: return 3  // Default to overcast if unknown
    }
  }

  // ---- Location editing. Clicking the location label swaps it for a search
  //      field; picking a geocoded suggestion persists name + coordinates to
  //      the module's shell.json entry. An empty commit returns to auto.
  function startEditingLocation() {
    editingLocation = true
    savingLocation = false
    savingLocationQueryStarted = false
    locationSuggestions = []
    suggestionIndex = 0
    Qt.callLater(function() {
      locationField.text = root.configuredLocation
      locationField.selectAll()
      locationField.forceActiveFocus()
    })
  }

  function cancelEditingLocation() {
    editingLocation = false
    savingLocation = false
    savingLocationQueryStarted = false
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
    savingLocation = true
    savingLocationQueryStarted = false
    configuredLocationState = {
      name: location.name,
      latitude: location.latitude,
      longitude: location.longitude
    }
    persistLocation(location.name, location.latitude, location.longitude)
  }

  function clearLocation() {
    persistLocation("", null, null)
    wttrLocation = ""
    cancelEditingLocation()
  }

  function pickSuggestion(suggestion) {
    if (!suggestion) return
    savingLocation = true
    savingLocationQueryStarted = false
    configuredLocationState = {
      name: suggestion.name,
      latitude: suggestion.latitude,
      longitude: suggestion.longitude
    }
    persistLocation(suggestion.name, suggestion.latitude, suggestion.longitude)
  }

  function finishSavingLocation() {
    if (savingLocation && savingLocationQueryStarted) cancelEditingLocation()
  }

  function persistLocation(name, latitude, longitude) {
    if (name && latitude !== null && longitude !== null)
      locationSaveProc.command = ["omarchy-weather-location", "--set", name, latitude + "," + longitude]
    else if (name)
      locationSaveProc.command = ["omarchy-weather-location", "--set", name]
    else
      locationSaveProc.command = ["omarchy-weather-location", "--clear"]
    locationSaveProc.running = true
  }

  function checkRainFromForecast(forecastData) {
    // Check if this is Yr.no (met.no) or Open-Meteo data
    if (forecastData && forecastData.properties && forecastData.properties.timeseries) {
      checkRainFromYrNo(forecastData)
    } else {
      checkRainFromOpenMeteo(forecastData)
    }
  }
  
  function checkRainFromYrNo(forecastData) {
    // Check Yr.no (met.no) forecast for precipitation
    if (!forecastData || !forecastData.properties || !forecastData.properties.timeseries) {
      root.needUmbrellaSoon = false
      root.needUmbrellaToday = false
      root.minutesUntilRain = -1
      return
    }
    
    var timeseries = forecastData.properties.timeseries
    var now = new Date()
    
    // Check for rain and calculate minutes until it starts
    var rainThresholdSoon = 0.1
    var rainThresholdToday = 0.2
    var firstRainTime = null
    var rainSoon = false
    var rainToday = false
    
    // Process each hourly entry
    for (var i = 0; i < Math.min(timeseries.length, 16); i++) {
      var entry = timeseries[i]
      if (!entry || !entry.time || !entry.data || !entry.data.next_1_hours) continue
      
      var entryTime = new Date(entry.time)
      var hoursDiff = (entryTime - now) / (1000 * 60 * 60)
      if (hoursDiff < 0) continue  // Skip past entries
      
      var details = entry.data.next_1_hours.details
      if (!details) continue
      
      var precip = parseFloat(details.precipitation_amount || 0)
      
      // Check if this is within 2 hours (soon)
      if (hoursDiff <= 2 && precip > rainThresholdSoon) {
        if (!firstRainTime) {
          firstRainTime = entryTime
          root.minutesUntilRain = Math.round((entryTime - now) / (1000 * 60))
        }
        rainSoon = true
        break
      }
      
      // Check if this is within 16 hours (today)
      if (hoursDiff <= 16 && precip > rainThresholdToday) {
        if (!firstRainTime) {
          firstRainTime = entryTime
          root.minutesUntilRain = Math.round((entryTime - now) / (1000 * 60))
        }
        rainToday = true
        if (!rainSoon) break  // Continue checking for soon rain
      }
    }
    
    if (!firstRainTime) {
      root.minutesUntilRain = -1
    }
    
    root.needUmbrellaSoon = rainSoon
    root.needUmbrellaToday = rainToday && !rainSoon
  }
  
  function checkRainFromOpenMeteo(forecastData) {
    // Check Open-Meteo forecast for precipitation
    if (!forecastData || !forecastData.hourly || !forecastData.hourly.precipitation || !forecastData.hourly.time) {
      root.needUmbrellaSoon = false
      root.needUmbrellaToday = false
      root.minutesUntilRain = -1
      return
    }
    
    var precipitation = forecastData.hourly.precipitation
    var times = forecastData.hourly.time
    var now = new Date()
    
    // Find current hour index
    var currentIndex = -1
    for (var i = 0; i < times.length; i++) {
      var time = new Date(times[i])
      if (time >= now) {
        currentIndex = i
        break
      }
    }
    
    if (currentIndex === -1) {
      root.needUmbrellaSoon = false
      root.needUmbrellaToday = false
      root.minutesUntilRain = -1
      return
    }
    
    // Check for rain and calculate minutes until it starts
    var rainThresholdSoon = 0.1
    var rainThresholdToday = 0.2
    var firstRainIndex = -1
    var rainSoon = false
    var rainToday = false
    
    // First check next 2 hours with lower threshold for "soon" detection
    for (var j = currentIndex; j < Math.min(currentIndex + 2, precipitation.length); j++) {
      if (precipitation[j] && precipitation[j] > rainThresholdSoon) {
        if (firstRainIndex === -1) {
          firstRainIndex = j
          var rainTime = new Date(times[j])
          root.minutesUntilRain = Math.round((rainTime - now) / (1000 * 60))
        }
        rainSoon = true
        break
      }
    }
    
    // If no soon rain, check next 16 hours with higher threshold for "today" detection
    if (!rainSoon) {
      for (var k = currentIndex; k < Math.min(currentIndex + 16, precipitation.length); k++) {
        if (precipitation[k] && precipitation[k] > rainThresholdToday) {
          if (firstRainIndex === -1) {
            firstRainIndex = k
            var rainTimeLater = new Date(times[k])
            root.minutesUntilRain = Math.round((rainTimeLater - now) / (1000 * 60))
          }
          rainToday = true
          break
        }
      }
    }
    
    if (firstRainIndex === -1) {
      root.minutesUntilRain = -1
    }
    
    root.needUmbrellaSoon = rainSoon
    root.needUmbrellaToday = rainToday && !rainSoon
  }

  function updateLabelWithUmbrella(icon) {
    var umbrellaIcon = ""
    if (root.needUmbrellaSoon) {
      if (root.minutesUntilRain >= 0) {
        umbrellaIcon = " ☔ " + root.minutesUntilRain + "m"
      } else {
        umbrellaIcon = " ☔"
      }
    } else if (root.needUmbrellaToday) {
      if (root.minutesUntilRain >= 0) {
        var hours = Math.floor(root.minutesUntilRain / 60)
        umbrellaIcon = " ☂️ " + hours + "h"
      } else {
        umbrellaIcon = " ☂️"
      }
    }
    root.label = icon + umbrellaIcon
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
    geocodeActiveQuery = geocodePendingQuery
    geocodeProc.command = ["curl", "-fsS", "--max-time", "5",
      "https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(geocodeActiveQuery) + "&count=5&language=en&format=json"]
    geocodeProc.running = true
  }

  function buildForecastDays() {
    return Model.buildForecastDays(report, dailyForecastReport, Qt.formatDate(new Date(), "yyyy-MM-dd"))
  }

  function openMeteoForecastDays() {
    return Model.openMeteoForecastDays(dailyForecastReport, Qt.formatDate(new Date(), "yyyy-MM-dd"))
  }

  function wttrNextForecastDays() {
    return Model.wttrNextForecastDays(report, Qt.formatDate(new Date(), "yyyy-MM-dd"))
  }

  function isFutureForecastDate(dateString) {
    return Model.isFutureForecastDate(dateString, Qt.formatDate(new Date(), "yyyy-MM-dd"))
  }

  function roundedTemp(value) {
    return Model.roundedTemp(value)
  }

  function celsiusToFahrenheit(value) {
    return Model.celsiusToFahrenheit(value)
  }

  function formatTemp(value) {
    return Model.formatTemp(value, useImperial)
  }

  function dayName(dateString) {
    return Model.dayName(dateString, function(date) { return Qt.formatDate(date, "dddd") })
  }

  // Bare degree value (no unit letter), used in the forecast row.
  function bareTempForDay(day, kind) {
    return Model.bareTempForDay(day, kind, useImperial)
  }

  // Representative icon for a forecast day: the hourly entry nearest noon.
  function dayIcon(day) {
    return Model.dayIcon(day)
  }

  function iconForOpenMeteoCode(code) {
    return Model.iconForOpenMeteoCode(code)
  }

  // Mirrors omarchy-weather-icon's wttr.in code → nerd-font glyph mapping.
  function iconForCode(code, night) {
    return Model.iconForCode(code, night)
  }

  Process {
    id: forecastProc
    command: ["curl", "-fsS", "--max-time", "10", "https://wttr.in/" + root.locationQuery + "?format=j1"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) {
          root.scheduleForecastRetry()
          return
        }
        try {
          var parsed = JSON.parse(raw)
          root.report = parsed
          if (!root.hasConfiguredCoordinates)
            root.updateLabelWithUmbrella(Model.provisionalCurrentIcon(parsed.current_condition && parsed.current_condition[0], ""))
          root.forecastRetries = 0
          if (Model.weatherResponseCompletesSave(root.hasConfiguredCoordinates, "wttr"))
            root.finishSavingLocation()
          // Stored coordinates already drove the fast open-meteo fetch from
          // refresh(); only auto-detect needs the area wttr reported.
          if (isNaN(parseFloat(String(root.configuredLocationState.latitude))))
            root.refreshDailyForecast(parsed)
        } catch (e) {
          // Keep last-good report visible, but try again shortly.
          root.scheduleForecastRetry()
        }
      }
    }
  }

  // wttr.in can be slow or flaky, especially for a location it hasn't
  // cached yet. Retry a few times before leaving it to the refresh timer.
  function scheduleForecastRetry() {
    if (forecastRetries >= 3) return
    forecastRetries++
    forecastRetryTimer.restart()
  }

  Timer {
    id: forecastRetryTimer
    interval: 2500
    onTriggered: if (!forecastProc.running) forecastProc.running = true
  }

  // With configured coordinates this fetch is the only thing that updates the
  // bar icon, so a dropped response (e.g. waking before the network is back)
  // must retry rather than wait out the refresh timer with a stale icon.
  function scheduleDailyForecastRetry() {
    if (dailyForecastRetries >= 3) return
    dailyForecastRetries++
    dailyForecastRetryTimer.restart()
  }

  Timer {
    id: dailyForecastRetryTimer
    interval: 2500
    onTriggered: root.refreshDailyForecast(null)
  }

  Process {
    id: dailyForecastProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) {
          root.scheduleDailyForecastRetry()
          return
        }
        try {
          var parsed = JSON.parse(raw)
          
          // Check if this is Yr.no or Open-Meteo data
          var isYrNo = parsed.properties && parsed.properties.timeseries
          var parsedCurrent = null
          
          if (isYrNo) {
            // For Yr.no, extract current conditions from first timeseries entry
            if (parsed.properties.timeseries && parsed.properties.timeseries.length > 0) {
              var firstEntry = parsed.properties.timeseries[0]
              if (firstEntry.data && firstEntry.data.instant && firstEntry.data.instant.details) {
                var details = firstEntry.data.instant.details
                var symbolCode = firstEntry.data.next_1_hours?.summary?.symbol_code || ""
                
                // Convert Yr.no symbol_code to Open-Meteo weather code
                var weatherCode = convertYrSymbolToOpenMeteoCode(symbolCode)
                
                parsedCurrent = {
                  temp_C: Math.round(details.air_temperature || 0),
                  temp_F: Math.round((details.air_temperature || 0) * 9/5 + 32),
                  FeelsLikeC: Math.round(details.air_temperature || 0),  // Yr doesn't provide feels-like
                  FeelsLikeF: Math.round((details.air_temperature || 0) * 9/5 + 32),
                  humidity: Math.round(details.relative_humidity || 0),
                  windspeedKmph: Math.round((details.wind_speed || 0) * 3.6),  // m/s to km/h
                  windspeedMiles: Math.round((details.wind_speed || 0) * 2.237),  // m/s to mph
                  openMeteoWeatherCode: weatherCode,
                  isDay: symbolCode.includes("_day") ? 1 : (symbolCode.includes("_night") ? 0 : 1)
                }
              }
            }
          } else {
            parsedCurrent = Model.openMeteoCurrentCondition(parsed)
          }
          
          root.dailyForecastReport = parsed
          root.checkRainFromForecast(parsed)
          if (parsedCurrent) {
            root.updateLabelWithUmbrella(Model.currentIcon(parsedCurrent, ""))
          }
          root.dailyForecastRetries = 0
          if (Model.weatherResponseCompletesSave(root.hasConfiguredCoordinates, isYrNo ? "yr" : "open-meteo"))
            root.finishSavingLocation()
        } catch (e) {
          // Keep last-good daily forecast visible, but try again shortly.
          root.scheduleDailyForecastRetry()
        }
      }
    }
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
    id: locationSaveProc
    onExited: function(exitCode) {
      if (exitCode !== 0 || !root.savingLocation) return

      // FileView handles changed locations. Explicitly refresh here too so
      // saving the already-active location cannot strand the spinner.
      locationFile.reload()
      if (!root.savingLocationQueryStarted) {
        root.savingLocationQueryStarted = true
        root.forecastRetries = 0
        root.dailyForecastRetries = 0
        forecastProc.running = false
        dailyForecastProc.running = false
        Qt.callLater(root.refresh)
      }
    }
  }

  Process {
    id: locationProc
    command: ["curl", "-fsS", "--max-time", "4", "https://wttr.in/?format=%l"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) return
        root.wttrLocation = raw.split(",")[0]
      }
    }
  }

  Timer {
    id: refreshTimer
    interval: root.refreshMinutes * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function edit(): void { root.openFromHotkey(); root.startEditingLocation() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(480))
    contentHeight: panel.fittedContentHeight(weatherColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editingLocation
      onReturnRequested: root.startEditingLocation()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: weatherScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: weatherColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: weatherColumn
          width: weatherScroll.width
          spacing: Style.space(14)

      // ---- Hero row: big icon + temp on the left; location and stats stacked on the right.
      Item {
        id: heroRow
        width: parent.width
        height: Math.max(heroLeft.height, heroRight.height)

        // Narrow panels (fittedContentWidth can shrink below the preferred
        // 480) shrink decorative sizes instead of letting the left group run
        // under the stats column.
        readonly property bool compact: width < Style.space(460)

        Column {
          id: heroRight
          width: weatherStats.implicitWidth
          anchors.right: parent.right
          anchors.rightMargin: Style.space(20)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(12)

          Row {
            visible: !root.editingLocation && root.reportLocation !== ""
            spacing: Style.space(6)

            TapHandler {
              onTapped: root.startEditingLocation()
            }
            HoverHandler {
              cursorShape: Qt.PointingHandCursor
            }

            Text {
              text: ""  // nf-fa-map_marker
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              // Elide long names instead of overflowing past the panel edge.
              text: (root.reportLocation || "").toUpperCase()
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              font.letterSpacing: 1
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideRight
              width: Math.min(implicitWidth, Math.max(0, heroRight.width - Style.space(26)))
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
              foreground: root.bar.foreground
              font.family: root.bar.fontFamily

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
            // loading, this same compact affordance becomes a spinner.
            Rectangle {
              width: Style.space(18)
              height: Style.space(18)
              anchors.verticalCenter: parent.verticalCenter
              radius: Math.min(4, Style.cornerRadius)
              color: !root.savingLocation && clearLocationArea.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"

              Text {
                anchors.centerIn: parent
                text: root.savingLocation ? "󰦖" : "✕"
                font.family: root.bar.fontFamily
                color: Qt.darker(root.bar.foreground, 1.4)
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

          Row {
            id: weatherStats
            visible: !!root.current
            spacing: heroRow.compact ? Style.space(14) : Style.space(36)

            Column {
              spacing: Style.space(5)
              Text {
                text: "FEELS"
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }
              Text {
                text: root.reportFeels
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
              }
            }

            Column {
              spacing: Style.space(5)
              Text {
                text: "WIND"
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }
              Text {
                text: root.reportWind
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
              }
            }

            Column {
              spacing: Style.space(5)
              Text {
                text: "HUMID"
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }
              Text {
                text: root.reportHumidity
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
              }
            }
          }
        }

        Row {
          id: heroLeft
          anchors.left: parent.left
          anchors.leftMargin: Style.space(16)
          // Right-bounded by the stats column so the two sides can never
          // collide; the temperature shrinks (HorizontalFit) to whatever
          // width is left.
          anchors.right: heroRight.left
          anchors.rightMargin: Style.space(14)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(16)

          Text {
            id: heroIcon
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 5
            text: root.label || "—"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            // Decorative condition emoji; intentionally larger than the
            // Style.font.* scale's displayLarge (28).
            font.pixelSize: heroRow.compact ? 44 : 64
          }

          Item {
            width: Math.max(0, heroLeft.width - heroIcon.width - heroLeft.spacing)
            height: tempBig.height
            anchors.verticalCenter: parent.verticalCenter

            Text {
              id: tempBig
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              // Hero temperature read-out; deliberately oversized, outside
              // the Style.font.* scale.
              text: root.reportTempNum || "—"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: 56
              font.bold: true
              fontSizeMode: Text.HorizontalFit
              minimumPixelSize: 22
              width: Math.min(implicitWidth, Math.max(0, parent.width - unitText.width - Style.space(2)))
            }
            Text {
              id: unitText
              text: root.current ? root.tempUnit : ""
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
              anchors.left: tempBig.right
              anchors.leftMargin: Style.space(2)
              anchors.top: tempBig.top
              anchors.topMargin: Style.space(10)
            }
          }
        }
      }

      // ---- Geocoding suggestions while the location is being edited.
      Column {
        visible: root.editingLocation && !root.savingLocation && root.locationSuggestions.length > 0
        width: parent.width
        spacing: 0

        Repeater {
          model: root.locationSuggestions

          Rectangle {
            required property var modelData
            required property int index
            width: parent.width
            height: suggestionRow.implicitHeight + Style.space(12)
            radius: Style.cornerRadius
            color: index === root.suggestionIndex ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"

            Row {
              id: suggestionRow
              anchors.left: parent.left
              anchors.leftMargin: Style.space(16)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              Text {
                text: modelData.name
                color: index === root.suggestionIndex ? Style.hoverStateColor(root.bar.foreground, Color.accent) : root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
              }
              Text {
                visible: text !== ""
                text: modelData.description
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onPositionChanged: root.suggestionIndex = index
              onClicked: root.pickSuggestion(modelData)
            }
          }
        }
      }

      Text {
        visible: !root.current
        text: "Fetching forecast…"
        color: Qt.darker(root.bar.foreground, 1.5)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.italic: true
      }

      // ---- Divider between current conditions and forecast.
      Rectangle {
        visible: root.forecastDays.length > 0
        width: parent.width
        height: Style.spacing.hairline
        color: root.bar.foreground
        opacity: 0.12
      }

      // ---- Forecast row: each cell has the day icon left of a day-name + hi/lo column.
      //      Wrapped in an Item so the block of cells can be centered within the popup.
      Item {
        visible: root.forecastDays.length > 0
        width: parent.width
        height: forecastRow.height

        Row {
          id: forecastRow
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(44)

          Repeater {
            model: root.forecastDays

            Row {
              required property var modelData
              required property int index
              spacing: Style.space(10)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.dayIcon(modelData)
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.display
              }

              Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  text: root.dayName(modelData.date).toUpperCase()
                  color: Qt.darker(root.bar.foreground, 1.4)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1
                }

                Row {
                  spacing: Style.space(6)

                  Text {
                    text: root.bareTempForDay(modelData, "max")
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    text: root.bareTempForDay(modelData, "min")
                    color: Qt.darker(root.bar.foreground, 1.5)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
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
  }

}
