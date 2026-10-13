import QtQuick

// Runs against the real BarWidget.qml and Panel.qml through tests/run.sh, with
// the same bar facade (qs.Ui.PluginBarApi) the shell hands a third-party
// plugin. `h` is the harness; a test that has to wait is a generator and
// yields the number of milliseconds to wait.
//
// Weather comes from tests/fixtures/bin/curl, which answers by latitude, and
// the location lives in a throwaway HOME (see tests/setup.sh). Without a
// saved location the plugin locates itself by IP, which the fixture answers
// with "Fixtureville": dry now, rain in three hours for four hours.
Item {
    id: spec

    property var h: null
    // Long enough for a save, a forecast and a radar request to come back.
    readonly property int fetch: 900

    function panel() {
        return h.byName("umbrellaPanel");
    }

    // Save a location the way picking a search result does. Its latitude
    // decides the weather the fixture serves.
    function moveTo(name, latitude, longitude) {
        panel().pickSuggestion({
            "name": name,
            "latitude": latitude,
            "longitude": longitude
        });
    }

    function widget() {
        var w = h.createWidget({
        });
        // The facade forwards the flag to the bar through this callback.
        h.bar._setCenterHoverRevealSuppressed = function(value) {
            h.bar._centerHoverRevealSuppressed = value;
        };
        // Every test starts unlocated: the saved location outlives a widget.
        panel().clearLocation();
        return w;
    }

    // Regression: close() wrote the bar's centerHoverRevealSuppressed flag
    // directly. On the plugin facade that property is read-only, so close()
    // threw before it reached controller.hide(). The panel's full-screen
    // overlay then stayed up and swallowed every click on the screen.
    function* test_clickingTheWidgetAgainClosesThePanel() {
        var w = widget();
        yield 100;
        w.handlePress(Qt.LeftButton);
        yield 100;
        h.compare(w.opened, true, "a click opens the panel");
        w.handlePress(Qt.LeftButton);
        yield 100;
        h.compare(w.opened, false, "a second click closes it");
    }

    function* test_escapeClosesThePanel() {
        var w = widget();
        yield 100;
        w.open();
        yield 100;
        h.compare(w.opened, true);
        h.key(Qt.Key_Escape);
        yield 100;
        h.compare(w.opened, false);
    }

    // What a click outside the panel, and a switch to another widget's
    // panel, call on the widget.
    function* test_theBarCanCloseThePanel() {
        var w = widget();
        yield 100;
        w.open();
        yield 100;
        w.close();
        yield 100;
        h.compare(w.opened, false, "close()");
        w.open();
        yield 100;
        w.closeForPopoutSwitch();
        yield 100;
        h.compare(w.opened, false, "closeForPopoutSwitch()");
    }

    function* test_theCenterHoverRevealFlagFollowsThePanel() {
        var w = widget();
        yield 100;
        w.open();
        yield 100;
        h.compare(h.bar.centerHoverRevealSuppressed, true, "suppressed while the panel is open");
        w.close();
        yield 100;
        h.compare(h.bar.centerHoverRevealSuppressed, false, "and released when it closes");
    }

    // Closing must never depend on the bar: whatever the bar object is, the
    // panel has to come down.
    function* test_thePanelClosesEvenIfTheBarRefusesTheFlag() {
        var w = widget();
        h.bar._setCenterHoverRevealSuppressed = function(value) {
            throw new Error("bar says no");
        };
        yield 100;
        w.open();
        yield 100;
        h.compare(w.opened, true);
        try {
            w.close();
        } catch (e) {
        }
        yield 100;
        h.compare(w.opened, false);
    }

    // --- The bar ----------------------------------------------------------

    // Regression: the label was given to an icon button, which fits its text
    // into an icon-sized canvas, so "\ud83c\udf02 3h" was drawn a few pixels tall.
    function* test_theBarLabelIsReadableText() {
        var w = widget();
        yield fetch;
        var button = h.byName("barButton");
        h.verify(/^\ud83c\udf02 \dh$/.test(button.text), "rain later reads as hours, got " + button.text);
        h.verify(button.labelWidth > 0, "painted as a text label");
        h.verify(w.implicitWidth >= button.labelWidth, "and the widget is wide enough for it");
    }

    function* test_theBarShowsAnEllipsisUntilTheFirstForecast() {
        var w = widget();
        h.compare(h.byName("barButton").text, "\u2026");
        yield fetch;
        h.verify(h.byName("barButton").text !== "\u2026");
    }

    // --- The verdict ------------------------------------------------------

    function* test_rainLaterCountsDownInHours() {
        var w = widget();
        yield fetch;
        var p = panel(), card = h.byName("verdictCard");
        h.compare(p.rain.state, "later");
        h.compare(h.byName("titleCaption").text, "Rain later in Fixtureville");
        h.compare(h.byName("titleGlyph").text, "\ud83c\udf02");
        var starts = new Date();
        starts.setHours(starts.getHours() + 3, 0, 0, 0);
        h.compare(card.name, "Rain at " + Qt.formatTime(starts, "HH:mm"));
        h.compare(card.detail, "light rain \u00b7 0.8 mm/h");
        h.compare(card.value, String(Math.floor(p.rain.minutesUntil / 60)));
        h.compare(card.unit + " " + card.note, "h to go");
        h.compare(h.byName("barButton").text, "\ud83c\udf02 " + card.value + "h", "the bar and the card agree");
    }

    function* test_rainNow() {
        var w = widget();
        yield fetch;
        moveTo("Rainy Bay", 61.2, 6.1);
        yield fetch;
        var card = h.byName("verdictCard");
        h.compare(h.byName("barButton").text, "\u2614 Now");
        h.compare(h.byName("titleCaption").text, "Raining now in Rainy Bay");
        h.compare(h.byName("titleGlyph").text, "\u2614");
        h.compare(card.name, "Raining now");
        h.compare(card.detail, "light rain \u00b7 2.4 mm/h");
        h.compare(card.value + card.unit + card.note, "Now");
    }

    // Regression: the start time was the tick plus whole minutes, which
    // landed a few seconds short and printed as a minute early (14:59).
    function* test_rainSoonCountsDownInMinutesToTheRadarStep() {
        var w = widget();
        yield fetch;
        moveTo("Soon Sound", 62.4, 6.1);
        yield fetch;
        var p = panel(), card = h.byName("verdictCard");
        h.compare(p.rain.state, "soon");
        h.verify(p.rain.minutesUntil >= 35 && p.rain.minutesUntil <= 40, "about forty minutes away, got " + p.rain.minutesUntil);
        h.compare(card.value, String(p.rain.minutesUntil));
        h.compare(card.unit + " " + card.note, "min to go");
        h.compare(h.byName("barButton").text, "\u2614 " + p.rain.minutesUntil + "m");
        h.compare(p.rainStartsAt().getMinutes() % 5, 0, "radar steps are on five-minute marks");
        h.compare(p.rainStartsAt().getSeconds(), 0);
        h.compare(card.name, "Rain at " + Qt.formatTime(p.rainStartsAt(), "HH:mm"));
        h.compare(h.byName("titleCaption").text, "Rain soon in Soon Sound");
    }

    function* test_dry() {
        var w = widget();
        yield fetch;
        moveTo("Dry Hill", 63.4, 10.4);
        yield fetch;
        var card = h.byName("verdictCard");
        h.compare(h.byName("barButton").text, "\u2601\ufe0f", "the quiet glyph for an overcast sky");
        h.compare(h.byName("titleCaption").text, "Dry in Dry Hill");
        h.compare(card.name, "No rain");
        h.compare(card.detail, "in the next 16 hours");
        h.compare(card.value + card.unit + card.note, "Dry");
        h.compare(panel().rainWindows.length, 0);
    }

    function* test_aFailedFetchKeepsTheLastVerdict() {
        var w = widget();
        yield fetch;
        h.compare(panel().rain.state, "later");
        moveTo("Offline Atoll", 0.5, 0.5);
        yield fetch;
        h.compare(panel().rain.state, "later", "the verdict is kept");
        h.compare(h.byName("verdictCard").unit, "h");
    }

    // --- Radar ------------------------------------------------------------

    function* test_theRadarChartAppearsWhenTheRadarSeesRain() {
        var w = widget();
        yield fetch;
        var chart = h.byName("nowcastChart"), dry = h.byName("radarDryLine");
        h.compare(panel().nowcastSeries.length > 0, true, "Fixtureville is inside radar coverage");
        h.compare(panel().radarShowsRain, false);
        moveTo("Soon Sound", 62.4, 6.1);
        yield fetch;
        w.open();
        yield 100;
        h.compare(panel().radarShowsRain, true);
        h.compare(chart.visible, true);
        h.compare(dry.visible, false);
        h.verify(chart.series.length >= 18, "ninety minutes of five-minute steps, got " + chart.series.length);
        h.compare(h.byName("nowcastBar-0").height, 0, "dry at first");
        var last = chart.series.length - 1, peak = 0;
        for (var i = 0; i <= last; i++) peak = Math.max(peak, h.byName("nowcastBar-" + i).height)
        h.verify(peak > 20, "the heaviest step fills the chart, got " + peak);
    }

    function* test_aDryRadarIsOneLineNotAnEmptyChart() {
        var w = widget();
        yield fetch;
        w.open();
        yield 100;
        h.compare(h.byName("nowcastChart").visible, false);
        h.compare(h.byName("radarDryLine").visible, true);
        h.compare(h.byName("radarDryLine").text, "Radar is dry for the next 90 minutes");
    }

    function* test_outsideRadarCoverageTheHourlyForecastDecides() {
        var w = widget();
        yield fetch;
        moveTo("Madrid", 40.4, -3.7);
        yield fetch;
        w.open();
        yield 100;
        var p = panel();
        h.compare(p.nowcastSteps, null);
        h.compare(p.rain.state, "soon");
        h.compare(h.byName("nowcastChart").visible, false);
        h.compare(h.byName("radarDryLine").visible, false);
        h.compare(h.byName("verdictCard").detail, "light rain \u00b7 0.6 mm/h");
    }

    function* test_theRadarToggleMovesTheChartIntoTheBar() {
        var w = widget();
        yield fetch;
        moveTo("Soon Sound", 62.4, 6.1);
        yield fetch;
        w.open();
        yield 100;
        var toggle = h.byName("radarToggle");
        h.compare(toggle.checked, false);
        h.compare(w.radarInBar, false);
        h.click(toggle);
        yield 100;
        h.compare(h.lastPersisted().barMode, "radar");
        h.compare(toggle.checked, true);
        h.compare(w.radarInBar, true);
        h.compare(h.byName("barButton").visible, false, "the chart replaces the label");
        h.click(toggle);
        yield 100;
        h.compare(h.lastPersisted().barMode, "umbrella");
        h.compare(w.radarInBar, false);
    }

    // --- Rain windows -----------------------------------------------------

    function* test_everyRainWindowIsARow() {
        var w = widget();
        yield fetch;
        w.open();
        yield 100;
        var from = new Date();
        from.setHours(from.getHours() + 3, 0, 0, 0);
        var to = new Date(from.getTime() + 4 * 3.6e+06);
        h.compare(panel().rainWindows.length, 1);
        h.compare(h.byName("rainWindowTime-0").text, Qt.formatTime(from, "HH:mm") + " \u2013 " + Qt.formatTime(to, "HH:mm"));
        h.compare(h.byName("rainWindowAmount-0").text, "7.5 mm");
    }

    // --- Location ---------------------------------------------------------

    function* test_anIpLocationIsMarkedApproximate() {
        var w = widget();
        yield fetch;
        h.compare(h.byName("locationName").text, "Fixtureville");
        h.compare(panel().usingIpGeo, true);
        moveTo("Dry Hill", 63.4, 10.4);
        yield fetch;
        h.compare(h.byName("locationName").text, "Dry Hill");
        h.compare(panel().usingIpGeo, false);
    }

    function* test_searchingAndPickingALocationWithTheKeyboard() {
        var w = widget();
        yield fetch;
        w.open();
        yield 100;
        h.click(h.byName("locationRow"));
        yield 100;
        var field = h.byName("locationField");
        h.compare(panel().editingLocation, true);
        h.compare(field.activeFocus, true, "the search field takes the keyboard");
        h.compare(field.text, "Fixtureville", "prefilled and selected");
        h.type("hill");
        yield fetch;
        h.compare(panel().locationSuggestions.length, 2);
        h.key(Qt.Key_Down);
        h.compare(panel().suggestionIndex, 1);
        h.key(Qt.Key_Return);
        yield fetch;
        h.compare(panel().editingLocation, false);
        h.compare(h.byName("locationName").text, "Dry Hill");
        h.compare(h.byName("verdictCard").value, "Dry", "and the forecast follows the new location");
        h.compare(w.opened, true, "the panel stays open");
    }

    function* test_escapeLeavesTheSearchBeforeItClosesThePanel() {
        var w = widget();
        yield fetch;
        w.open();
        yield 100;
        h.click(h.byName("locationRow"));
        yield 100;
        h.key(Qt.Key_Escape);
        yield 100;
        h.compare(panel().editingLocation, false);
        h.compare(w.opened, true, "the first Escape only leaves the search");
        h.key(Qt.Key_Escape);
        yield 100;
        h.compare(w.opened, false, "the second closes the panel");
    }

    function* test_clearingTheLocationReturnsToAutomatic() {
        var w = widget();
        yield fetch;
        moveTo("Dry Hill", 63.4, 10.4);
        yield fetch;
        w.open();
        yield 100;
        h.click(h.byName("locationRow"));
        yield 100;
        h.click(h.byName("clearLocationButton"));
        yield fetch;
        h.compare(h.byName("locationName").text, "Fixtureville");
        h.compare(panel().usingIpGeo, true);
    }

}
