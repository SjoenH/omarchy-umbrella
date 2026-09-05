# koka.umbrella — Umbrella Countdown

A single-purpose Omarchy bar widget that counts down to the next rain. No
temperatures, no forecasts, no weather dashboard — just the one question:
**do I need an umbrella today?**

**Plugin ID:** `koka.umbrella`
**Author:** koka.no ([koka.no](https://koka.no))

## Bar states

| State | Meaning |
|-------|---------|
| `☀️` | No rain expected in the next 16 hours |
| `☔ 30m` | Rain starting within 2 hours — minutes countdown |
| `🌂 2h` | Rain expected later today — hours countdown |

Rain counts when the hourly precipitation exceeds 0.1 mm within the next
2 hours (soon) or 0.2 mm within 16 hours (later).

## Installation

```sh
omarchy plugin add https://github.com/SjoenH/omarchy-umbrella.git --enable
```

Then add `koka.umbrella` to your bar layout in `~/.config/omarchy/shell.json`
and restart the shell:

```sh
omarchy restart shell
```

## Remove

```sh
omarchy plugin remove koka.umbrella
```

## Usage

- **Left-click** — panel with the rain timeline (start–end and mm of every
  rain window in the next 16 hours) and the location setting
- **Right-click** — notification with the current rain verdict
- **Middle-click** — force a refresh

Location is read from `omarchy-weather-location` (shared with the stock
weather tooling). Without a configured location the widget falls back to an
approximate IP-geolocated position. Weather data: [Open-Meteo](https://open-meteo.com),
hourly precipitation, no API key.

Auto-refresh defaults to 15 minutes; set `"refreshMinutes"` on the widget's
entry in `~/.config/omarchy/shell.json` to change it.

Set `"barMode": "radar"` to show a Yr-style mini radar chart (next 90
minutes) in the bar instead of the umbrella countdown. With no live radar
data it falls back to the umbrella label.

## Development

```sh
# Pure logic tests (rain windows, thresholds, labels)
qmltestrunner -input BarWidget.spec.qml

# Lint
OMARCHY_PATH=/usr/share/omarchy qmllint -I /usr/share/omarchy/shell *.qml
```

## History

This started as `koka.weather`, a fork of the official `omarchy.weather`
plugin with umbrella alerts bolted on. v2.0.0 dropped the whole weather
picture to focus on the one job it was actually doing.

## License

MIT
