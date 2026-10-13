import "Model.js" as Model
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
    // ---- Rain state ---------------------------------------------------------
    // ---- Location -----------------------------------------------------------

    id: root

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
    readonly property color foreground: root.bar ? root.bar.foreground : Color.foreground
    readonly property color dim: Qt.darker(root.foreground, 1.55)
    // One source (Open-Meteo hourly precipitation), one fetch, one state
    // object. Kept on failure so the bar keeps showing the last verdict.
    property var forecast: null
    // Radar nowcast steps from MET nowcast/2.0 (next ~90 min). Null while
    // unavailable or outside coverage; the verdict then falls back to the
    // hourly forecast.
    property var nowcastSteps: null
    // Clock tick: verdicts are recomputed from already-fetched series on this
    // cadence, so minute-level countdowns move without any new HTTP traffic.
    // The refetch timer only has to slide the data window.
    property date now: new Date()
    // Hourly verdict, recomputed against the tick like the radar verdict.
    readonly property var hourlyRain: {
        var hourly = forecast && forecast.hourly;
        if (hourly && hourly.precipitation && hourly.time)
            return Model.nextRain(hourly.precipitation, hourly.time, now);

        return {
            "state": "none",
            "minutesUntil": -1,
            "mm": 0
        };
    }
    // Radar verdict wins while the nowcast is live — it observes rain that
    // hourly grid data misses — and defers to the hourly forecast otherwise.
    readonly property var rain: {
        var nowcast = Model.nextRainNowcast(nowcastSteps, now);
        if (nowcast)
            return nowcast;

        return hourlyRain;
    }
    property bool fetchedOnce: false
    property int forecastRetries: 0
    // Bar display mode: the umbrella countdown or a mini radar chart.
    // "radar" with no live nowcast falls back to the umbrella label.
    readonly property string barMode: String(setting("barMode", "umbrella")) === "radar" ? "radar" : "umbrella"
    readonly property bool radarInBar: barMode === "radar" && nowcastSteps !== null
    // Hover text for the bar radar: verdict plus what the next 90 minutes
    // look like at peak.
    readonly property string radarTooltip: {
        var peak = 0;
        var peakMinutes = -1;
        var now = new Date();
        for (var i = 0; i < nowcastSeries.length; i++) {
            if (nowcastSeries[i].rate > peak) {
                peak = nowcastSeries[i].rate;
                peakMinutes = Math.max(0, Math.round((nowcastSeries[i].date - now) / 60000));
            }
        }
        if (peak <= Model.NOWCAST_THRESHOLD)
            return root.quietGlyph + " Dry for the next 90 minutes (radar)";

        if (root.rain.state === "now")
            return "☔ Raining now — " + Model.describeRate(peak) + " · " + peak.toFixed(1) + " mm/h peak within 90 min";

        var when = peakMinutes === 0 ? "now" : "in " + peakMinutes + " min";
        return "☔ Rain " + when + " · " + peak.toFixed(1) + " mm/h peak within 90 min";
    }
    // Current WMO weather code, for the quiet bar when nothing rain-related
    // is happening.
    property int currentWeatherCode: -1
    readonly property string quietGlyph: currentWeatherCode >= 0 ? Model.wmoEmoji(currentWeatherCode) : "☀️"
    // Bar text: quiet sun while dry, countdown as soon as rain matters. An
    // ellipsis until the first verdict lands, so the bar never lies about
    // data it doesn't have yet.
    readonly property string barText: {
        // Radar mode renders the iconComponent in the bar instead; empty text
        // hides the glyph. Missing nowcast data falls back to the umbrella.
        if (root.radarInBar && root.nowcastSeries.length > 0)
            return "";

        if (!root.fetchedOnce)
            return "…";

        var label = Model.barLabel(root.rain);
        return label !== "" ? label : root.quietGlyph;
    }
    readonly property var rainWindows: {
        var hourly = root.forecast && root.forecast.hourly;
        if (!hourly || !hourly.precipitation || !hourly.time)
            return [];

        return Model.rainWindows(hourly.precipitation, hourly.time, new Date(), Model.LATER_HOURS, Model.SOON_THRESHOLD);
    }
    // Radar steps inside the nowcast window (now → +90 min), for the chart.
    readonly property var nowcastSeries: {
        var steps = nowcastSteps;
        if (!steps)
            return [];

        var now = new Date();
        var from = now.getTime() - 150000;
        var to = now.getTime() + 90 * 60000;
        var out = [];
        for (var i = 0; i < steps.length; i++) {
            var t = steps[i].date.getTime();
            if (t >= from && t <= to)
                out.push(steps[i]);

        }
        return out;
    }
    readonly property string rainStatusLine: {
        if (!root.fetchedOnce)
            return "Waiting for forecast…";

        if (root.rain.state === "now")
            return "☔ Raining now — " + Model.describeRate(root.rain.mm) + " (" + root.rain.mm + " mm/h)";

        if (root.rain.state === "soon")
            return "☔ Rain starting in " + Math.max(0, root.rain.minutesUntil) + " min";

        if (root.rain.state === "later") {
            var t = new Date(Date.now() + root.rain.minutesUntil * 60000);
            return "🌂 Rain at " + Qt.formatTime(t, "HH:mm");
        }
        return root.quietGlyph + " Dry for the next 16 hours";
    }
    // Configured coordinates come from weather.json (owned by
    // omarchy-weather-location); without them the widget falls back to an
    // approximate IP-geolocated position, refreshed with every cycle.
    property var configuredLocationState: ({
        "name": "",
        "latitude": null,
        "longitude": null
    })
    property var ipLocation: null
    readonly property bool hasConfiguredCoordinates: !isNaN(parseFloat(String(configuredLocationState.latitude))) && !isNaN(parseFloat(String(configuredLocationState.longitude)))
    readonly property var activeLocation: hasConfiguredCoordinates ? configuredLocationState : ipLocation
    readonly property string locationName: activeLocation ? activeLocation.name : ""
    readonly property bool usingIpGeo: !hasConfiguredCoordinates && ipLocation !== null
    // Auto-refresh interval in minutes; clamped to a sane minimum.
    readonly property int refreshMinutes: Math.max(1, parseInt(setting("refreshMinutes", 15), 10) || 15)
    property FileView locationFile
    // ---- Location editing. Clicking the location label swaps it for a search
    //      field; picking a geocoded suggestion persists name + coordinates via
    //      omarchy-weather-location. An empty commit returns to auto.
    property bool editingLocation: false
    property bool savingLocation: false
    property var locationSuggestions: []
    property int suggestionIndex: 0
    property string geocodePendingQuery: ""
    property string geocodeActiveQuery: ""

    function open() {
        openedFromHotkey = false;
        setCenterHoverRevealSuppressed(false);
        root.controller.show();
        locationFile.reload();
        root.refresh();
    }

    function openFromHotkey() {
        openedFromHotkey = true;
        root.controller.show();
        locationFile.reload();
        root.refresh();
        // Set after showing, not before: showing hands the popout coordinator
        // over, which closes whichever panel was open, and that close clears the
        // shared flag. Deferring means the panel taking over always wins, while
        // a handoff to a panel that does not manage the flag still leaves it
        // cleared rather than stuck on.
        Qt.callLater(function() {
            if (root.opened)
                setCenterHoverRevealSuppressed(true);

        });
    }

    function close() {
        // Hide first, before anything that could fail. The panel is a
        // full-screen overlay while it is open, so a close that throws before
        // this line leaves every click on the screen landing on it.
        root.controller.hide();
        setCenterHoverRevealSuppressed(false);
        if (root.editingLocation)
            root.cancelEditingLocation();

    }

    function toggle() {
        if (root.opened)
            root.close();
        else
            root.openFromHotkey();
    }

    function switchPanel(direction) {
        if (root.bar && typeof root.bar.switchPanelFrom === "function")
            return root.bar.switchPanelFrom(root.barIdentity, direction);

        return false;
    }

    // The shell hands a third-party plugin a bar facade on which this flag is
    // read-only and is set through a function. Older shells passed the Bar
    // itself, where the property is written. Either way this must not throw:
    // open() and close() both call it.
    // ---- What the panel says about the verdict ----------------------------
    // The arched line over the title.
    function captionText() {
        var where = root.locationName !== "" ? " in " + root.locationName : "";
        if (!root.fetchedOnce)
            return "Checking the sky" + where;

        if (root.rain.state === "now")
            return "Raining now" + where;

        if (root.rain.state === "soon")
            return "Rain soon" + where;

        if (root.rain.state === "later")
            return "Rain later" + where;

        return "Dry" + where;
    }

    // The illustration between the title words: the bar's own glyph.
    function titleGlyph() {
        if (root.fetchedOnce && (root.rain.state === "now" || root.rain.state === "soon"))
            return "\u2614";

        if (root.fetchedOnce && root.rain.state === "later")
            return "\ud83c\udf02";

        return root.quietGlyph;
    }

    // Rounded to the minute: the countdown is whole minutes from a clock
    // tick, so the sum can land a few seconds short of the hour it means.
    function rainStartsAt() {
        var ms = root.now.getTime() + Math.max(0, root.rain.minutesUntil) * 60000;
        return new Date(Math.round(ms / 60000) * 60000);
    }

    // True when the radar shows any rain at all in its 90 minutes.
    readonly property bool radarShowsRain: {
        for (var i = 0; i < nowcastSeries.length; i++) {
            if (nowcastSeries[i].rate > 0.05)
                return true;

        }
        return false;
    }

    function rateText(rate) {
        return Model.describeRate(rate) + " \u00b7 " + (Math.round(rate * 10) / 10) + " mm/h";
    }

    function verdictName() {
        if (!root.fetchedOnce)
            return "Waiting for forecast\u2026";

        if (root.rain.state === "now")
            return "Raining now";

        if (root.rain.state === "soon" || root.rain.state === "later")
            return "Rain at " + Qt.formatTime(root.rainStartsAt(), "HH:mm");

        return "No rain";
    }

    function verdictDetail() {
        if (!root.fetchedOnce)
            return "";

        if (root.rain.state === "none")
            return "in the next 16 hours";

        return root.rateText(root.rain.mm);
    }

    // The countdown, as large as the bar's label is small.
    function verdictValue() {
        if (!root.fetchedOnce)
            return "\u2026";

        if (root.rain.state === "now")
            return "Now";

        if (root.rain.state === "soon")
            return String(Math.max(0, root.rain.minutesUntil));

        if (root.rain.state === "later")
            return String(Math.floor(root.rain.minutesUntil / 60));

        return "Dry";
    }

    function verdictUnit() {
        if (!root.fetchedOnce)
            return "";

        if (root.rain.state === "soon")
            return "min";

        return root.rain.state === "later" ? "h" : "";
    }

    function verdictNote() {
        return root.fetchedOnce && (root.rain.state === "soon" || root.rain.state === "later") ? "to go" : "";
    }

    // A wash of the foreground over the panel background, as the cards use.
    function tint(amount) {
        var from = Color.popups.background;
        return Qt.rgba(from.r + (root.foreground.r - from.r) * amount, from.g + (root.foreground.g - from.g) * amount, from.b + (root.foreground.b - from.b) * amount, 1);
    }

    // Under the verdict when the radar covers the place but sees nothing.
    // The hourly forecast decides then, and it can say rain now, or within
    // the radar's 90 minutes, while the radar is empty. Say which is which
    // rather than "raining now" over "radar is dry".
    function dryRadarLine() {
        var forecastOnly = root.rain.state === "now" || (root.rain.state === "soon" && root.rain.minutesUntil <= 90);
        return forecastOnly ? "Forecast only: the radar sees no rain yet" : "Radar is dry for the next 90 minutes";
    }

    function setCenterHoverRevealSuppressed(value) {
        if (!root.bar)
            return ;

        try {
            if (typeof root.bar.setCenterHoverRevealSuppressed === "function")
                root.bar.setCenterHoverRevealSuppressed(value);
            else if ("centerHoverRevealSuppressed" in root.bar)
                root.bar.centerHoverRevealSuppressed = value;
        } catch (e) {
            console.warn("Umbrella: could not set the bar's centerHoverRevealSuppressed flag:", e);
        }
    }

    function startEditingLocation() {
        editingLocation = true;
        savingLocation = false;
        locationSuggestions = [];
        suggestionIndex = 0;
        Qt.callLater(function() {
            locationField.text = root.configuredLocationState.name || root.locationName;
            locationField.selectAll();
            locationField.forceActiveFocus();
        });
    }

    function cancelEditingLocation() {
        editingLocation = false;
        savingLocation = false;
        locationSuggestions = [];
        geocodeDebounce.stop();
        Qt.callLater(function() {
            if (keyCatcher)
                keyCatcher.forceActiveFocus();

        });
    }

    function commitLocation() {
        var location = Model.locationCommit(locationField.text, locationSuggestions, suggestionIndex);
        if (location.name === "") {
            clearLocation();
            return ;
        }
        configuredLocationState = {
            "name": location.name,
            "latitude": location.latitude,
            "longitude": location.longitude
        };
        persistLocation(location.name, location.latitude, location.longitude);
        cancelEditingLocation();
    }

    function clearLocation() {
        persistLocation("", null, null);
        cancelEditingLocation();
    }

    function pickSuggestion(suggestion) {
        if (!suggestion)
            return ;

        configuredLocationState = {
            "name": suggestion.name,
            "latitude": suggestion.latitude,
            "longitude": suggestion.longitude
        };
        persistLocation(suggestion.name, suggestion.latitude, suggestion.longitude);
        cancelEditingLocation();
    }

    function persistLocation(name, latitude, longitude) {
        savingLocation = true;
        if (name && latitude !== null && longitude !== null)
            locationSaveProc.command = ["omarchy-weather-location", "--set", name, latitude + "," + longitude];
        else if (name)
            locationSaveProc.command = ["omarchy-weather-location", "--set", name];
        else
            locationSaveProc.command = ["omarchy-weather-location", "--clear"];
        locationSaveProc.running = true;
    }

    // ---- Refresh ------------------------------------------------------------
    function refresh() {
        // Each full refresh cycle gets a fresh retry budget, so an earlier
        // exhausted round (e.g. waking with the network still down) doesn't
        // starve retries for the rest of the session.
        forecastRetries = 0;
        if (hasConfiguredCoordinates)
            fetchForecast(parseFloat(String(configuredLocationState.latitude)), parseFloat(String(configuredLocationState.longitude)));
        else if (!ipGeoProc.running)
            ipGeoProc.running = true;
    }

    function fetchForecast(lat, lon) {
        if (isNaN(lat) || isNaN(lon))
            return ;

        forecastProc.command = ["curl", "-fsS", "--max-time", "6", "https://api.open-meteo.com/v1/forecast" + "?latitude=" + encodeURIComponent(String(lat)) + "&longitude=" + encodeURIComponent(String(lon)) + "&hourly=precipitation" + "&current=weather_code" + "&forecast_days=2" + "&timezone=auto"];
        forecastProc.running = true;
        fetchNowcast(lat, lon);
    }

    function applyForecast(parsed) {
        forecast = parsed;
        currentWeatherCode = parsed && parsed.current ? parseInt(parsed.current.weather_code, 10) : -1;
        fetchedOnce = true;
    }

    // Radar nowcast, the same source Yr's 90-minute graph uses. Only covers
    // Scandinavia and nearby; a failed or empty response just leaves the
    // hourly verdict in charge.
    function fetchNowcast(lat, lon) {
        // MET's nowcast radar only covers the Nordics + Baltics; outside
        // that there is no radar at all and the hourly forecast decides.
        if (isNaN(lat) || isNaN(lon) || !Model.inNowcastRegion(lat, lon)) {
            nowcastSteps = null;
            return ;
        }
        nowcastProc.command = ["curl", "-fsS", "--max-time", "6", "-H", "User-Agent: koka-umbrella/2.0 github.com/SjoenH/omarchy-umbrella", "https://api.met.no/weatherapi/nowcast/2.0/complete" + "?lat=" + encodeURIComponent(String(lat)) + "&lon=" + encodeURIComponent(String(lon))];
        nowcastProc.running = true;
    }

    // A dropped response (e.g. waking before the network is back) retries a
    // few times rather than waiting out the refresh timer with a stale verdict.
    function scheduleForecastRetry() {
        if (forecastRetries >= 3)
            return ;

        forecastRetries++;
        forecastRetryTimer.restart();
    }

    // ---- Right-click notification -------------------------------------------
    function notifyUmbrella() {
        var text = "";
        if (root.rain.state === "now") {
            text = "☔ Raining now — " + Model.describeRate(root.rain.mm) + " (" + root.rain.mm + " mm/h)";
        } else if (root.rain.state === "soon") {
            text = "☔ Rain in " + Math.max(0, root.rain.minutesUntil) + " min — " + Model.describeRate(root.rain.mm) + " (" + root.rain.mm + " mm/h)";
        } else if (root.rain.state === "later") {
            var t = new Date(Date.now() + root.rain.minutesUntil * 60000);
            text = "🌂 Rain at " + Qt.formatTime(t, "HH:mm") + " — " + Model.describeRate(root.rain.mm) + " (" + root.rain.mm + " mm/h)";
        } else {
            text = root.quietGlyph + " No rain expected in the next 16 hours";
        }
        notifyProc.command = ["omarchy-notification-send", text];
        notifyProc.running = true;
    }

    // Debounced geocoding. Only one curl runs at a time; if the query moved on
    // while a fetch was in flight, the latest query is fetched right after.
    function requestGeocode() {
        var query = locationField.text.trim();
        if (query.length < 2) {
            locationSuggestions = [];
            return ;
        }
        geocodePendingQuery = query;
        if (!geocodeProc.running)
            startGeocode();

    }

    function startGeocode() {
        if (geocodePendingQuery === "")
            return ;

        geocodeActiveQuery = geocodePendingQuery;
        geocodeProc.command = ["curl", "-fsS", "--max-time", "5", "https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(geocodeActiveQuery) + "&count=5&language=en&format=json"];
        geocodeProc.running = true;
    }

    // Bar display mode switch. Persists via the shell's inline settings
    // update (same path the catjam widget uses for its GIF choice).
    function setBarMode(mode) {
        var entry = {
        };
        for (var key in root.settings) if (key !== "id") {
            entry[key] = root.settings[key];
        }
        entry["barMode"] = mode;
        root.settings = entry;
        if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
            root.bar.shell.updateEntryInline(root.moduleName, entry);

    }

    objectName: "umbrellaPanel"
    moduleName: "koka.umbrella"
    manageIpc: false
    Accessible.role: Accessible.Dialog
    Accessible.name: "Umbrella Countdown"
    onConfiguredLocationStateChanged: Qt.callLater(root.refresh)

    // The first read can race shell startup (observed sporadically), leaving a
    // stored location unhonored until the next file write. One delayed reload
    // self-corrects; if the first read was fine it's a no-op, since identical
    // state doesn't change the location and so triggers no refetch.
    Timer {
        interval: 1500
        running: true
        onTriggered: locationFile.reload()
    }

    // ---- Processes & timers -------------------------------------------------
    Process {
        id: forecastProc

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var raw = String(text || "").trim();
                if (!raw) {
                    root.scheduleForecastRetry();
                    return ;
                }
                try {
                    root.applyForecast(JSON.parse(raw));
                    root.forecastRetries = 0;
                } catch (e) {
                    // Keep last-good verdict visible, but try again shortly.
                    root.scheduleForecastRetry();
                }
            }
        }

    }

    Timer {
        id: forecastRetryTimer

        interval: 2500
        onTriggered: {
            if (root.hasConfiguredCoordinates && root.activeLocation)
                root.fetchForecast(parseFloat(String(root.activeLocation.latitude)), parseFloat(String(root.activeLocation.longitude)));
            else if (!root.hasConfiguredCoordinates && !ipGeoProc.running)
                ipGeoProc.running = true;
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
                var loc = Model.parseIpGeo(text);
                if (loc) {
                    root.ipLocation = loc;
                    root.fetchForecast(loc.latitude, loc.longitude);
                } else {
                    root.scheduleForecastRetry();
                }
            }
        }

    }

    Process {
        id: nowcastProc

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var raw = String(text || "").trim();
                root.nowcastSteps = raw ? Model.parseNowcast(raw) : null;
            }
        }

    }

    // RainViewer, step 1: the maps index (host + latest frame path).
    Process {
        id: locationSaveProc

        onExited: function(exitCode) {
            if (exitCode !== 0) {
                root.savingLocation = false;
                return ;
            }
            // FileView watch picks the new state up; reload explicitly so saving
            // the already-active location still refreshes deterministically.
            locationFile.reload();
            root.savingLocation = false;
        }
    }

    Process {
        id: geocodeProc

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.locationSuggestions = root.editingLocation ? Model.parseGeocodingResults(text) : [];
                root.suggestionIndex = 0;
                if (root.geocodePendingQuery !== root.geocodeActiveQuery)
                    Qt.callLater(root.startGeocode);

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

    // Radar-only refetch, decoupled from the full forecast cycle. Minute-
    // level countdowns are recomputed locally on the clock tick; this curl
    // only slides the 90-minute data window. No-op outside MET coverage.
    Timer {
        id: radarTimer

        interval: 5 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: false
        onTriggered: {
            var location = root.activeLocation;
            if (location && location.latitude !== null && location.longitude !== null)
                root.fetchNowcast(parseFloat(String(location.latitude)), parseFloat(String(location.longitude)));

        }
    }

    // Clock tick: recompute verdicts (countdowns, bar label, windows) from
    // already-fetched series, no HTTP traffic.
    Timer {
        interval: 30 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    // ---- Panel --------------------------------------------------------------
    KeyboardPanel {
        id: panel

        anchorItem: root.anchorItem
        owner: root.barIdentity
        bar: root.bar
        open: root.opened
        centerOnBar: false
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(Style.space(340))
        contentHeight: panel.fittedContentHeight(umbrellaColumn.implicitHeight)

        PanelKeyCatcher {
            id: keyCatcher

            anchors.fill: parent
            blocked: root.editingLocation
            onReturnRequested: root.startEditingLocation()
            onCloseRequested: root.close()
            onTabRequested: function(direction) {
                root.switchPanel(direction);
            }

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
                    spacing: Style.space(12)

                    PanelTitle {
                        width: parent.width
                        caption: root.captionText()
                        leftWord: "Umbrella"
                        rightWord: "Countdown"
                        foreground: root.foreground
                        fontFamily: root.fontFamily

                        Text {
                            objectName: "titleGlyph"
                            anchors.centerIn: parent
                            textFormat: Text.PlainText
                            text: root.titleGlyph()
                            font.pixelSize: Math.round(parent.height * 0.72)
                        }

                    }

                    // ---- Verdict, over the radar when there is one ------------
                    StatCard {
                        objectName: "verdictCard"
                        width: parent.width
                        name: root.verdictName()
                        detail: root.verdictDetail()
                        value: root.verdictValue()
                        unit: root.verdictUnit()
                        note: root.verdictNote()
                        foreground: root.foreground
                        fontFamily: root.fontFamily

                        // In a Column so that whichever of the two is hidden
                        // takes no room in the card.
                        Column {
                            width: parent.width

                            NowcastChart {
                                objectName: "nowcastChart"
                                width: parent.width
                                visible: root.radarShowsRain
                                series: root.nowcastSeries
                                foreground: root.foreground
                                fontFamily: root.fontFamily
                            }

                            // A dry radar is one line, not an empty chart.
                            Text {
                                objectName: "radarDryLine"
                                width: parent.width
                                visible: root.nowcastSeries.length > 0 && !root.radarShowsRain
                                textFormat: Text.PlainText
                                text: root.dryRadarLine()
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                            }

                        }

                    }

                    // ---- Every rain window in the hourly forecast --------------
                    Column {
                        width: parent.width
                        spacing: Style.space(6)
                        visible: root.rainWindows.length > 0

                        Text {
                            textFormat: Text.PlainText
                            text: "Next 16 hours"
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: true
                        }

                        Repeater {
                            model: root.rainWindows

                            Rectangle {
                                id: windowRow

                                required property var modelData
                                required property int index
                                // Intensity is the window's total over its length.
                                readonly property real rate: modelData.mm / Math.max(0.25, (modelData.end - modelData.start) / 3.6e+06)

                                objectName: "rainWindow-" + index
                                width: parent.width
                                height: Style.space(34)
                                radius: Style.cornerRadius
                                color: root.tint(0.05)

                                Text {
                                    objectName: "rainWindowTime-" + windowRow.index
                                    anchors.left: parent.left
                                    anchors.leftMargin: Style.spacing.rowPaddingX
                                    anchors.verticalCenter: parent.verticalCenter
                                    textFormat: Text.PlainText
                                    text: Qt.formatTime(windowRow.modelData.start, "HH:mm") + " \u2013 " + Qt.formatTime(windowRow.modelData.end, "HH:mm")
                                    color: root.foreground
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.body
                                    font.weight: Font.DemiBold
                                }

                                Row {
                                    anchors.right: parent.right
                                    anchors.rightMargin: Style.spacing.rowPaddingX
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Style.space(6)

                                    Text {
                                        anchors.baseline: windowAmount.baseline
                                        textFormat: Text.PlainText
                                        text: Model.describeRate(windowRow.rate)
                                        color: root.dim
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                    }

                                    Text {
                                        id: windowAmount

                                        objectName: "rainWindowAmount-" + windowRow.index
                                        textFormat: Text.PlainText
                                        text: windowRow.modelData.mm + " mm"
                                        color: root.foreground
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.body
                                    }

                                }

                            }

                        }

                    }

                    // ---- Location ------------------------------------------------
                    Column {
                        width: parent.width
                        spacing: Style.space(2)

                        Text {
                            textFormat: Text.PlainText
                            text: "Location"
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: true
                        }

                        // The location as a control: click, or Return, to search.
                        BorderSurface {
                            id: locationRow

                            readonly property bool hot: locationMouse.containsMouse

                            objectName: "locationRow"
                            visible: !root.editingLocation
                            width: parent.width
                            height: locationField.implicitHeight
                            radius: Style.cornerRadius
                            color: Style.controlFill(activeFocus, hot, root.foreground, Color.accent)
                            borderSpec: Border.controlSpec(activeFocus ? "focus" : (hot ? "hover-cursor" : "normal"), root.foreground, Color.accent)
                            activeFocusOnTab: true
                            Accessible.role: Accessible.Button
                            Accessible.name: "Change location"
                            Keys.onReturnPressed: root.startEditingLocation()
                            Keys.onEnterPressed: root.startEditingLocation()
                            Keys.onSpacePressed: root.startEditingLocation()

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: locationRow.borderLeft + Style.spacing.controlPaddingX
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Style.space(6)

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    textFormat: Text.PlainText
                                    text: "\uf041" // nf-fa-map_marker
                                    color: root.dim
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.body
                                }

                                Text {
                                    objectName: "locationName"
                                    anchors.verticalCenter: parent.verticalCenter
                                    textFormat: Text.PlainText
                                    text: root.locationName !== "" ? root.locationName : "Set location"
                                    color: root.foreground
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.body
                                    font.italic: root.locationName === ""
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: root.usingIpGeo
                                    textFormat: Text.PlainText
                                    text: "\u00b7 approximate"
                                    color: root.dim
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                }

                            }

                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: locationRow.borderRight + Style.spacing.controlPaddingX
                                anchors.verticalCenter: parent.verticalCenter
                                textFormat: Text.PlainText
                                text: "Change"
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                            }

                            MouseArea {
                                id: locationMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.startEditingLocation()
                            }

                        }

                        Row {
                            visible: root.editingLocation
                            width: parent.width
                            spacing: Style.space(6)

                            TextField {
                                id: locationField

                                objectName: "locationField"
                                width: parent.width - clearLocationButton.width - parent.spacing
                                enabled: !root.savingLocation
                                placeholderText: "Search city"
                                foreground: root.foreground
                                font.family: root.fontFamily
                                Accessible.name: "Search for a city"
                                onTextChanged: {
                                    if (root.editingLocation && !root.savingLocation)
                                        geocodeDebounce.restart();

                                }
                                Keys.onPressed: function(event) {
                                    if (event.key === Qt.Key_Escape) {
                                        root.cancelEditingLocation();
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Down) {
                                        if (root.suggestionIndex < root.locationSuggestions.length - 1)
                                            root.suggestionIndex++;

                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Up) {
                                        if (root.suggestionIndex > 0)
                                            root.suggestionIndex--;

                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                        root.commitLocation();
                                        event.accepted = true;
                                    }
                                }
                            }

                            // Clear back to IP auto-detect. While a committed location is
                            // saving, this same compact affordance becomes a spinner.
                            Rectangle {
                                id: clearLocationButton

                                objectName: "clearLocationButton"
                                width: Style.space(22)
                                height: Style.space(22)
                                anchors.verticalCenter: parent.verticalCenter
                                radius: Math.min(4, Style.cornerRadius)
                                color: !root.savingLocation && clearLocationArea.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
                                Accessible.role: Accessible.Button
                                Accessible.name: "Detect the location automatically"

                                Text {
                                    textFormat: Text.PlainText
                                    anchors.centerIn: parent
                                    text: root.savingLocation ? "\udb82\udd96" : "\u2715"
                                    font.family: root.fontFamily
                                    color: root.dim
                                    font.pixelSize: Style.font.bodySmall

                                    RotationAnimator on rotation {
                                        running: root.savingLocation
                                        from: 0
                                        to: 360
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
                            topPadding: Style.space(4)
                            spacing: Style.space(2)

                            Repeater {
                                model: root.locationSuggestions

                                Rectangle {
                                    id: suggestionRow

                                    required property var modelData
                                    required property int index

                                    objectName: "suggestion-" + index
                                    width: parent.width
                                    height: Style.space(34)
                                    radius: Style.cornerRadius
                                    color: root.suggestionIndex === index ? Style.selectedFillFor(root.foreground, Color.accent) : (rowHover.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent")

                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        anchors.leftMargin: Style.spacing.rowPaddingX
                                        spacing: 0

                                        Text {
                                            textFormat: Text.PlainText
                                            text: suggestionRow.modelData.name
                                            color: root.foreground
                                            font.family: root.fontFamily
                                            font.pixelSize: Style.font.body
                                        }

                                        Text {
                                            textFormat: Text.PlainText
                                            visible: suggestionRow.modelData.description !== ""
                                            text: suggestionRow.modelData.description
                                            color: root.dim
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

                    // ---- Bar display: mini radar chart or the countdown ---------
                    Toggle {
                        objectName: "radarToggle"
                        width: parent.width
                        label: "Radar in the bar"
                        description: "The next 90 minutes as a chart"
                        checked: root.barMode === "radar"
                        foreground: root.foreground
                        accent: Color.accent
                        fontFamily: root.fontFamily
                        onClicked: root.setBarMode(root.barMode === "radar" ? "umbrella" : "radar")
                    }

                }

            }

        }

    }

    locationFile: FileView {
        path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/weather.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.configuredLocationState = Model.parseLocationFile(text())
        onLoadFailed: root.configuredLocationState = Model.parseLocationFile("")
    }

}
