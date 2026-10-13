import QtQuick

// Runs against the real BarWidget.qml and Panel.qml through tests/run.sh, with
// the same bar facade (qs.Ui.PluginBarApi) the shell hands a third-party
// plugin. `h` is the harness; a test that has to wait is a generator and
// yields the number of milliseconds to wait.
Item {
    id: spec

    property var h: null

    function widget() {
        var w = h.createWidget({
        });
        // The facade forwards the flag to the bar through this callback.
        h.bar._setCenterHoverRevealSuppressed = function(value) {
            h.bar._centerHoverRevealSuppressed = value;
        };
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

}
