# koka.weather - Weather with Umbrella Alerts

A customized Omarchy weather widget that adds smart umbrella alerts to help you plan your day.

**Plugin ID:** `koka.weather`  
**Author:** Koka ([koka.no](https://koka.no))

## Features

- **Smart Umbrella Alerts**
  - ☔ Shows when rain is expected within the next 90 minutes (with minutes countdown)
  - ☂️ Shows when rain is expected later today (with hours countdown)
- Full weather information with detailed forecast panel
- Location auto-detection or manual configuration
- Temperature, humidity, wind speed, and feels-like temperature
- 4-day weather forecast
- Auto-refresh with configurable interval
- Click to view detailed panel
- Right-click for notification
- Middle-click to refresh

## Installation

1. Clone this plugin to your Omarchy plugins directory:
```bash
cd ~/.config/omarchy/plugins
git clone https://github.com/SjoenH/omarchy-weather-umbrella.git koka.weather
```

2. Add the plugin to your `~/.config/omarchy/shell.json`:
```json
{
  "center": [
    "koka.weather"
  ]
}
```

3. Restart Omarchy shell:
```bash
omarchy restart shell
```

## Configuration

Click the weather widget to open the detailed panel where you can:
- Set your location manually
- Configure temperature units (Celsius/Fahrenheit)
- Adjust auto-refresh interval

## How It Works

The plugin intelligently selects weather data sources based on your location:
- **Norway**: Uses Yr.no (met.no) API for superior accuracy in Norwegian locations
- **Rest of world**: Uses Open-Meteo API for global coverage

The plugin fetches:
- Current weather conditions
- Hourly precipitation forecasts (for umbrella alerts)
- Daily weather forecasts

Umbrella logic:
- **☔ + minutes (urgent)**: Rain expected within 2 hours, shows minutes until rain starts
- **☂️ + hours (reminder)**: Rain expected later (within 16 hours), shows hours until rain starts
- Precipitation threshold: >0.1mm for soon, >0.2mm for later

## Credits

Based on the official `omarchy.weather` plugin, enhanced with umbrella alert functionality.

## License

MIT
