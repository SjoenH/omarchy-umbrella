import QtQuick
import Quickshell
import qs.Commons as Commons
import qs.Ui as Ui

// Stands in for the bar host. It builds the widget the way Bar.qml's
// ModuleSlot does (construct first, then inject bar, moduleName and settings),
// hands it the same PluginBarApi facade a third-party plugin gets, and
// records everything the plugin asks the shell to persist.
QtObject {
    id: harness

    property Item stage: null
    property QtObject events: null
    property string pluginDir: ""
    // Every entry the plugin passed to bar.shell.updateEntryInline, oldest first.
    property var persisted: []
    // The real host writes shell.json and then pushes the new entry back
    // into widget.settings. Turn this off to test a write that never lands.
    property bool echoSettings: true
    property var widget: null
    property QtObject bar: null
    property var _created: []
    property Component _barApi
    property Component _shell

    function verify(condition, message) {
        if (!condition)
            throw new Error(message || "verify failed");

    }

    function compare(actual, expected, message) {
        var a = JSON.stringify(actual), e = JSON.stringify(expected);
        if (a !== e)
            throw new Error((message ? message + ": " : "") + "expected " + e + ", got " + a);

    }

    function env(name) {
        return Quickshell.env(name) || "";
    }

    function lastPersisted() {
        return persisted.length > 0 ? persisted[persisted.length - 1] : null;
    }

    function createWidget(settings, file) {
        var component = Qt.createComponent("file://" + pluginDir + "/" + (file || "BarWidget.qml"));
        if (component.status !== Component.Ready)
            throw new Error(component.errorString());

        var w = component.createObject(stage);
        var id = w.moduleName;
        var shell = _shell.createObject(harness);
        var api = _barApi.createObject(harness, {
            "pluginId": id,
            "moduleName": id,
            "shell": shell,
            "foreground": Commons.Color.bar.text,
            "barForeground": Commons.Color.bar.text,
            "background": Commons.Color.bar.background,
            "urgent": Commons.Color.bar.active,
            "fontFamily": Commons.Style.font.family,
            "barSize": Commons.Style.bar.sizeHorizontal
        });
        _created.push(w, api, shell);
        harness.widget = w;
        harness.bar = api;
        harness.persisted = [];
        // Same order as ModuleSlot.injectProps.
        w.bar = api;
        w.moduleName = id;
        w.settings = JSON.parse(JSON.stringify(settings || {
        }));
        return w;
    }

    // Look an object up by objectName anywhere in the test window, including
    // non-visual children and whatever a Loader has loaded.
    function byName(name) {
        var found = _search(stage, function(o) {
            return o.objectName === name;
        });
        if (!found)
            throw new Error("no object named \"" + name + "\"");

        return found;
    }

    function _search(node, matches) {
        if (!node)
            return null;

        if (matches(node))
            return node;

        var kids = [];
        var lists = [node.children, node.data, node.item ? [node.item] : null];
        for (var l = 0; l < lists.length; l++) {
            for (var i = 0; lists[l] && i < lists[l].length; i++) {
                if (kids.indexOf(lists[l][i]) < 0)
                    kids.push(lists[l][i]);

            }
        }
        for (var k = 0; k < kids.length; k++) {
            var found = _search(kids[k], matches);
            if (found)
                return found;

        }
        return null;
    }

    function click(item) {
        verify(events.mouseClick(item, item.width / 2, item.height / 2, Qt.LeftButton, Qt.NoModifier, -1), "click was not delivered");
    }

    function type(text) {
        for (var i = 0; i < text.length; i++) verify(events.keyClickChar(text[i], Qt.NoModifier, -1), "key was not delivered")
    }

    function key(code) {
        verify(events.keyClick(code, Qt.NoModifier, -1), "key was not delivered");
    }

    function cleanup() {
        for (var i = 0; i < _created.length; i++) _created[i].destroy()
        _created = [];
        widget = null;
        bar = null;
        persisted = [];
        echoSettings = true;
    }

    _barApi: Component {
        Ui.PluginBarApi {
        }

    }

    _shell: Component {
        QtObject {
            function updateEntryInline(id, settings) {
                var entry = JSON.parse(JSON.stringify(settings));
                harness.persisted = harness.persisted.concat([entry]);
                if (!harness.echoSettings)
                    return true;

                var target = harness.widget;
                Qt.callLater(function() {
                    if (harness.widget !== target || !target)
                        return ;

                    var pushed = {
                    };
                    for (var key in entry) {
                        if (key !== "id")
                            pushed[key] = entry[key];

                    }
                    target.settings = pushed;
                });
                return true;
            }

        }

    }

}
