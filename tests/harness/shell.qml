//@ pragma OmarchyLoadPatch
import QtQuick
import QtTest as QT
import Quickshell
import qs.Commons as Commons

// Spec runner. Loads the spec named by $SPEC_FILE, runs each of its test_*
// functions in name order and exits non-zero if any of them threw.
//
// A test that needs to wait (for a process to finish, or for a deferred
// call) is written as a generator and yields the number of milliseconds to
// wait:
//
//     function* test_probeReportsUp() {
//         var w = h.createWidget({ "url": "…" });
//         yield 500;
//         h.compare(w.status.up, true);
//     }
ShellRoot {
    id: runner

    property var spec: null
    property var names: []
    property int index: -1
    property var steps: null
    property int failed: 0

    function start() {
        var component = Qt.createComponent("file://" + Quickshell.env("SPEC_FILE"));
        if (component.status !== Component.Ready) {
            console.log("SPEC ERROR " + component.errorString());
            Qt.exit(2);
            return ;
        }
        runner.spec = component.createObject(stage, {
            "h": harness
        });
        var only = Quickshell.env("SPEC_ONLY") || "";
        var found = [];
        for (var key in runner.spec) {
            if (key.indexOf("test_") === 0 && typeof runner.spec[key] === "function" && key.indexOf(only) >= 0)
                found.push(key);

        }
        runner.names = found.sort();
        runner.next();
    }

    function next() {
        runner.index++;
        if (runner.index >= runner.names.length) {
            console.log("SPEC " + (runner.names.length - runner.failed) + " passed, " + runner.failed + " failed");
            Qt.exit(runner.failed > 0 ? 1 : 0);
            return ;
        }
        try {
            var result = runner.spec[runner.names[runner.index]]();
            if (result && typeof result.next === "function") {
                runner.steps = result;
                runner.step();
            } else {
                runner.finish(null);
            }
        } catch (e) {
            runner.finish(e);
        }
    }

    function step() {
        try {
            var result = runner.steps.next();
            if (result.done) {
                runner.finish(null);
            } else {
                pause.then = runner.step;
                pause.interval = Math.max(1, result.value || 1);
                pause.start();
            }
        } catch (e) {
            runner.finish(e);
        }
    }

    function finish(error) {
        runner.steps = null;
        if (error)
            runner.failed++;

        console.log("SPEC " + (error ? "FAIL " : "PASS ") + runner.names[runner.index] + (error ? " -- " + error : ""));
        harness.cleanup();
        pause.then = runner.next;
        pause.interval = 20;
        pause.start();
    }

    Window {
        id: window

        visible: true
        width: 900
        height: 900
        color: Commons.Color.background

        Item {
            id: stage

            anchors.fill: parent
        }

    }

    QT.TestEvent {
        id: events
    }

    Harness {
        id: harness

        stage: stage
        events: events
        pluginDir: Quickshell.env("PLUGIN_DIR")
    }

    Timer {
        id: pause

        property var then: null

        onTriggered: then()
    }

    // Key events only reach an item with active focus, which needs an active
    // window, so activate it before the first test runs.
    Timer {
        interval: 300
        running: true
        onTriggered: {
            window.requestActivate();
            pause.then = runner.start;
            pause.interval = 200;
            pause.start();
        }
    }

}
