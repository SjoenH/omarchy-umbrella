// Pure logic for the umbrella widget: location state, rain windows, and the
// bar label. Everything here is Qt-free so it runs under node and
// qmltestrunner; QML owns time formatting and the network.
//
// Rain amounts are hourly totals in mm from Open-Meteo's hourly=precipitation
// (the only weather source; timestamps are local ISO strings like
// "2026-08-29T15:00").

// ---- Rain thresholds -------------------------------------------------------
//
// Two windows mirror the original dual-source widget: within the next two
// hours a drizzle counts (bring the umbrella now), later today only a proper
// shower does (umbrella before leaving). Comparisons are strict, so exactly
// 0.1mm stays dry.
var SOON_HOURS = 2
var LATER_HOURS = 16
var SOON_THRESHOLD = 0.1
var LATER_THRESHOLD = 0.2
// Radar nowcast (MET nowcast/2.0): precipitation_rate in mm/h per 5-min
// step. Low bar so light drizzle counts as raining; the source is observed,
// not a grid forecast.
var NOWCAST_THRESHOLD = 0.1

// MET nowcast/2.0/complete response → sorted steps [{date, rate}] with rate
// in mm/h. Null on anything unusable so the caller falls back to the hourly
// forecast verdict.
function parseNowcast(raw) {
    try {
        var data = JSON.parse(String(raw || "{}"))
        var series = data && data.properties && data.properties.timeseries
        if (!series || !series.length)
            return null

        var steps = []
        for (var i = 0; i < series.length; i++) {
            var entry = series[i]
            var rate = entry && entry.data && entry.data.instant
                && entry.data.instant.details
                ? parseFloat(entry.data.instant.details.precipitation_rate) : NaN
            var date = new Date(entry.time)
            if (isNaN(date.getTime()) || isNaN(rate))
                continue
            steps.push({ date: date, rate: rate })
        }
        return steps.length ? steps : null
    } catch (e) {
        return null
    }
}

// Radar verdict for the next 90 minutes. Returns null when the nowcast sees
// no rain (the hourly verdict then decides), otherwise the same shape as
// nextRain: the first radar step above threshold is rain "now", a later one
// is "soon" with minutesUntil.
function nextRainNowcast(steps, now) {
    if (!steps || steps.length === 0)
        return null

    for (var i = 0; i < steps.length; i++) {
        if (steps[i].rate > NOWCAST_THRESHOLD) {
            return {
                state: i === 0 ? "now" : "soon",
                minutesUntil: i === 0 ? 0 : Math.max(0, Math.round((steps[i].date - now) / 60000)),
                mm: steps[i].rate
            }
        }
    }
    return null
}

// Index of the hour bucket containing `now` (its start is <= now). Hourly
// timestamps mark bucket starts, so the in-progress hour — where rain happening
// right now lives — has a start in the past and must not be skipped.
function currentIndex(times, now) {
    var found = -1
    for (var i = 0; i < times.length; i++) {
        var t = new Date(times[i])
        if (!isNaN(t.getTime()) && t <= now)
            found = i
        else if (found !== -1)
            break
    }
    // `now` before the first bucket: treat the first bucket as upcoming so
    // future rain in a short forecast array is still seen.
    if (found === -1 && times.length > 0) {
        var first = new Date(times[0])
        if (!isNaN(first.getTime()) && first > now)
            return 0
    }
    return found
}

// The next rain that matters. Returns
//   { state: "now"|"soon"|"later"|"none", minutesUntil: int, mm: number }
// with minutesUntil -1 for "none". "now" means the current hour bucket is
// already raining. "soon" wins over "later" whenever both windows match,
// matching the original widget's precedence.
function nextRain(precipitation, times, now) {
    var none = { state: "none", minutesUntil: -1, mm: 0 }
    if (!precipitation || !times || precipitation.length === 0 || times.length === 0)
        return none

    var cur = currentIndex(times, now)
    if (cur === -1)
        return none

    var current = precipitation[cur]
    if (current !== undefined && current !== null && current > SOON_THRESHOLD)
        return { state: "now", minutesUntil: 0, mm: current }

    for (var j = cur + 1; j < Math.min(cur + 1 + SOON_HOURS, precipitation.length); j++) {
        if (precipitation[j] !== undefined && precipitation[j] !== null && precipitation[j] > SOON_THRESHOLD) {
            var soonTime = new Date(times[j])
            return {
                state: "soon",
                minutesUntil: Math.round((soonTime - now) / 60000),
                mm: precipitation[j]
            }
        }
    }

    for (var k = cur; k < Math.min(cur + LATER_HOURS, precipitation.length); k++) {
        if (precipitation[k] !== undefined && precipitation[k] !== null && precipitation[k] > LATER_THRESHOLD) {
            var laterTime = new Date(times[k])
            return {
                state: "later",
                minutesUntil: Math.round((laterTime - now) / 60000),
                mm: precipitation[k]
            }
        }
    }

    return none
}

// Contiguous rain runs within the first `hours` entries, for the panel
// timeline. Returns [{ start: Date, end: Date, mm: number }] with end
// exclusive; a run still raining at the horizon ends there.
function rainWindows(precipitation, times, now, hours, threshold) {
    var windows = []
    if (!precipitation || !times || precipitation.length === 0 || times.length === 0)
        return windows

    var cur = currentIndex(times, now)
    if (cur === -1)
        return windows

    var runStart = -1
    var runMm = 0
    var limit = Math.min(cur + hours, precipitation.length)
    for (var j = cur; j < limit; j++) {
        var wet = precipitation[j] !== undefined && precipitation[j] !== null && precipitation[j] > threshold
        if (wet) {
            if (runStart === -1) {
                runStart = j
                runMm = 0
            }
            runMm += Number(precipitation[j]) || 0
        } else if (runStart !== -1) {
            windows.push({
                start: new Date(times[runStart]),
                end: new Date(times[j]),
                mm: Math.round(runMm * 10) / 10
            })
            runStart = -1
        }
    }
    if (runStart !== -1) {
        var end = new Date(times[limit - 1])
        end = new Date(end.getTime() + 3600000)
        windows.push({
            start: new Date(times[runStart]),
            end: end,
            mm: Math.round(runMm * 10) / 10
        })
    }
    return windows
}

// ---- Bar label -------------------------------------------------------------
//
// "" means the widget falls back to its quiet dry glyph.
function barLabel(rain) {
    if (!rain)
        return ""
    if (rain.state === "now")
        return "☔ Now"
    if (rain.state === "soon")
        return rain.minutesUntil >= 0 ? "☔ " + rain.minutesUntil + "m" : "☔"
    if (rain.state === "later") {
        if (rain.minutesUntil >= 0) {
            var hours = Math.floor(rain.minutesUntil / 60)
            return "🌂 " + hours + "h"
        }
        return "🌂"
    }
    return ""
}

// ---- Location --------------------------------------------------------------
//
// omarchy-weather-location owns
// ~/.local/state/omarchy/settings/weather.json:
//   {"name": ..., "latitude": ..., "longitude": ...}
// Missing, blank, or unparseable means the location is unset and the panel
// falls back to an approximate IP-geolocated position.
function parseLocationFile(raw) {
    var unset = { name: "", latitude: null, longitude: null }
    try {
        var data = JSON.parse(String(raw || ""))
        if (!data || typeof data !== "object")
            return unset

        var latitude = parseFloat(data.latitude)
        var longitude = parseFloat(data.longitude)
        var hasCoordinates = !isNaN(latitude) && !isNaN(longitude)
        return {
            name: typeof data.name === "string" ? data.name.replace(/^\s+|\s+$/g, "") : "",
            latitude: hasCoordinates ? latitude : null,
            longitude: hasCoordinates ? longitude : null
        }
    } catch (e) {
        return unset
    }
}

// ipapi.co/json → coordinates + city, flagged approximate. Null on anything
// unusable, so the caller keeps the "no location" state.
function parseIpGeo(raw) {
    try {
        var data = JSON.parse(String(raw || "{}"))
        if (!data || typeof data !== "object")
            return null
        var latitude = parseFloat(data.latitude)
        var longitude = parseFloat(data.longitude)
        if (isNaN(latitude) || isNaN(longitude))
            return null
        return {
            name: typeof data.city === "string" ? data.city : "",
            latitude: latitude,
            longitude: longitude,
            approximate: true
        }
    } catch (e) {
        return null
    }
}

// Open-Meteo geocoding response → suggestion rows for the location search.
function parseGeocodingResults(raw) {
    try {
        var data = JSON.parse(String(raw || "{}"))
        var results = data.results
        if (!results || !results.length)
            return []

        var out = []
        for (var i = 0; i < results.length; i++) {
            var r = results[i]
            if (!r || !r.name || r.latitude === undefined || r.longitude === undefined)
                continue
            var region = [r.admin1, r.country].filter(function(part) { return !!part }).join(", ")
            out.push({
                name: String(r.name),
                description: region,
                latitude: r.latitude,
                longitude: r.longitude
            })
        }
        return out
    } catch (e) {
        return []
    }
}

// Commit the search field: prefer the highlighted suggestion, fall back to
// the raw text as a name-only location, empty means "back to auto".
function locationCommit(text, suggestions, selectedIndex) {
    var name = String(text || "").replace(/^\s+|\s+$/g, "")
    if (name === "")
        return { name: "", latitude: null, longitude: null }

    var choices = suggestions || []
    var index = Math.max(0, Math.min(parseInt(selectedIndex, 10) || 0, choices.length - 1))
    var suggestion = choices[index]
    if (suggestion)
        return suggestion

    return { name: name, latitude: null, longitude: null }
}

if (typeof module !== "undefined") {
    module.exports = {
        SOON_HOURS: SOON_HOURS,
        LATER_HOURS: LATER_HOURS,
        SOON_THRESHOLD: SOON_THRESHOLD,
        LATER_THRESHOLD: LATER_THRESHOLD,
        NOWCAST_THRESHOLD: NOWCAST_THRESHOLD,
        nextRain: nextRain,
        parseNowcast: parseNowcast,
        nextRainNowcast: nextRainNowcast,
        rainWindows: rainWindows,
        barLabel: barLabel,
        parseLocationFile: parseLocationFile,
        parseIpGeo: parseIpGeo,
        parseGeocodingResults: parseGeocodingResults,
        locationCommit: locationCommit
    }
}
