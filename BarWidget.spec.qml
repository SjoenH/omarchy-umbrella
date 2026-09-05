import "Model.js" as Model
import QtQuick 2.15
import QtTest 1.2

TestCase {
    // Fixed "now" so windows and minute math are deterministic. Times are
    // local ISO strings exactly like Open-Meteo returns with timezone=auto.
    readonly property date now: new Date(2026, 7, 29, 12, 0, 0)

    function series(precip) {
        var times = [];
        var amounts = [];
        for (var i = 0; i < 24; i++) {
            var h = i % 24;
            var day = 29 + Math.floor(i / 24);
            times.push("2026-08-" + day + "T" + (h < 10 ? "0" + h : h) + ":00");
            amounts.push(precip[i] !== undefined ? precip[i] : 0);
        }
        return [amounts, times];
    }

    function test_dry() {
        var s = series({
        });
        var rain = Model.nextRain(s[0], s[1], now);
        compare(rain.state, "none");
        compare(rain.minutesUntil, -1);
        compare(Model.barLabel(rain), "");
    }

    function test_soon_within_two_hours() {
        var s = series({
            "13": 0.3
        });
        var rain = Model.nextRain(s[0], s[1], now);
        compare(rain.state, "soon");
        compare(rain.minutesUntil, 60);
        compare(rain.mm, 0.3);
        compare(Model.barLabel(rain), "☔ 60m");
    }

    function test_raining_now() {
        // Rain in the in-progress hour bucket is happening now, not "soon".
        var s = series({
            "12": 0.5
        });
        var rain = Model.nextRain(s[0], s[1], now);
        compare(rain.state, "now");
        compare(rain.minutesUntil, 0);
        compare(Model.barLabel(rain), "☔ Now");
    }

    function test_soon_wins_over_later() {
        var s = series({
            "12": 0.3,
            "17": 0.5
        });
        var rain = Model.nextRain(s[0], s[1], now);
        compare(rain.state, "now");
        compare(rain.minutesUntil, 0);
    }

    function test_later_within_sixteen_hours() {
        var s = series({
            "17": 0.3
        });
        var rain = Model.nextRain(s[0], s[1], now);
        compare(rain.state, "later");
        compare(rain.minutesUntil, 300);
        compare(Model.barLabel(rain), "🌂 5h");
    }

    function test_drizzle_outside_soon_window_is_dry() {
        // 0.15mm at hour+5 is below the later threshold and outside the
        // soon window: neither alert fires.
        var s = series({
            "17": 0.15
        });
        compare(Model.nextRain(s[0], s[1], now).state, "none");
    }

    function test_thresholds_are_strict() {
        var s = series({
            "12": 0.1
        });
        compare(Model.nextRain(s[0], s[1], now).state, "none");
        var t = series({
            "17": 0.2
        });
        compare(Model.nextRain(t[0], t[1], now).state, "none");
    }

    function test_barLabel_variants() {
        compare(Model.barLabel({
            "state": "soon",
            "minutesUntil": 45
        }), "☔ 45m");
        compare(Model.barLabel({
            "state": "soon",
            "minutesUntil": -1
        }), "☔");
        compare(Model.barLabel({
            "state": "later",
            "minutesUntil": -1
        }), "🌂");
        compare(Model.barLabel(null), "");
    }

    function test_rainWindows_contiguous_run() {
        var s = series({
            "15": 0.3,
            "16": 0.2,
            "17": 0.4
        });
        var windows = Model.rainWindows(s[0], s[1], now, 16, 0.1);
        compare(windows.length, 1);
        compare(windows[0].start.getHours(), 15);
        compare(windows[0].end.getHours(), 18);
        compare(windows[0].mm, 0.9);
    }

    function test_rainWindow_open_at_horizon() {
        var s = series({
            "23": 0.5
        });
        var windows = Model.rainWindows(s[0], s[1], now, 16, 0.1);
        compare(windows.length, 1);
        // Run still raining at the horizon ends one hour past the last entry.
        compare(windows[0].end.getTime() - windows[0].start.getTime(), 3.6e+06);
    }

    function test_parseNowcast_and_radar_verdict() {
        var raw = JSON.stringify({
            "properties": {
                "timeseries": [{
                    "time": "2026-08-29T12:00:00Z",
                    "data": {
                        "instant": {
                            "details": {
                                "precipitation_rate": 0
                            }
                        }
                    }
                }, {
                    "time": "2026-08-29T12:05:00Z",
                    "data": {
                        "instant": {
                            "details": {
                                "precipitation_rate": 0.4
                            }
                        }
                    }
                }, {
                    "time": "2026-08-29T12:10:00Z",
                    "data": {
                        "instant": {
                            "details": {
                                "precipitation_rate": 0
                            }
                        }
                    }
                }]
            }
        });
        var steps = Model.parseNowcast(raw);
        compare(steps.length, 3);
        compare(Model.parseNowcast("not json"), null);
        var base = new Date(2026, 7, 29, 14, 0, 0);
        // First step wet → raining now.
        var wet = [{
            "date": new Date(base.getTime()),
            "rate": 0.4
        }, {
            "date": new Date(base.getTime() + 300000),
            "rate": 0
        }];
        var nowRain = Model.nextRainNowcast(wet, base);
        compare(nowRain.state, "now");
        compare(nowRain.mm, 0.4);
        // Rain starting in 5 minutes → soon with countdown.
        var soon = [{
            "date": new Date(base.getTime()),
            "rate": 0
        }, {
            "date": new Date(base.getTime() + 300000),
            "rate": 0.4
        }];
        var soonRain = Model.nextRainNowcast(soon, base);
        compare(soonRain.state, "soon");
        compare(soonRain.minutesUntil, 5);
        // Dry radar → null so the hourly verdict decides.
        compare(Model.nextRainNowcast([{
            "date": base,
            "rate": 0
        }], base), null);
        compare(Model.nextRainNowcast(null, base), null);
    }

    function test_describeRate() {
        compare(Model.describeRate(0.2), "light drizzle");
        compare(Model.describeRate(1), "light rain");
        compare(Model.describeRate(4), "moderate rain");
        compare(Model.describeRate(10), "heavy rain");
        compare(Model.describeRate(undefined), "light drizzle");
    }

    function test_inNowcastRegion() {
        verify(Model.inNowcastRegion(58.97, 5.73));
        verify(Model.inNowcastRegion(60.17, 24.94));
        verify(!Model.inNowcastRegion(41.9, 12.5));
        verify(!Model.inNowcastRegion(40.71, -74));
    }

    function test_wmoEmoji() {
        compare(Model.wmoEmoji(0), "☀️");
        compare(Model.wmoEmoji(2), "⛅");
        compare(Model.wmoEmoji(3), "☁️");
        compare(Model.wmoEmoji(61), "🌧️");
        compare(Model.wmoEmoji(71), "❄️");
        compare(Model.wmoEmoji(95), "⛈️");
        compare(Model.wmoEmoji(undefined), "🌍");
    }

    function test_parseIpGeo() {
        var good = Model.parseIpGeo('{"latitude": 59.91, "longitude": 10.75, "city": "Oslo"}');
        compare(good.latitude, 59.91);
        compare(good.name, "Oslo");
        verify(good.approximate === true);
        compare(Model.parseIpGeo("not json"), null);
        compare(Model.parseIpGeo('{"city": "Oslo"}'), null);
    }

    function test_parseLocationFile() {
        var good = Model.parseLocationFile('{"name": "Bergen", "latitude": 60.39, "longitude": 5.32}');
        compare(good.name, "Bergen");
        compare(good.latitude, 60.39);
        var bad = Model.parseLocationFile("");
        compare(bad.name, "");
        verify(bad.latitude === null);
    }

    function test_locationCommit() {
        var choices = [{
            "name": "Oslo",
            "latitude": 59.9,
            "longitude": 10.7
        }];
        var picked = Model.locationCommit("osl", choices, 0);
        compare(picked.name, "Oslo");
        // With no suggestions the raw text becomes a name-only location.
        compare(Model.locationCommit("Nowhere", [], 0).name, "Nowhere");
        // Empty text returns to auto-detect.
        verify(Model.locationCommit("  ", choices, 0).latitude === null);
    }

    name: "UmbrellaModel"
}
