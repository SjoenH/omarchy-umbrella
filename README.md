# Weather with Umbrella Alerts

A customized Omarchy weather widget that adds smart umbrella alerts to help you plan your day.

## Features

- **Smart Umbrella Alerts**
  - ☂️ Shows when rain is expected within the next 90 minutes
  - ☔ Shows when rain is expected later today (within 16 hours)
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
git clone <your-repo-url> henry.weather
```

2. Add the plugin to your `~/.config/omarchy/shell.json`:
```json
{
  "center": [
    "henry.weather"
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

The plugin uses the Open-Meteo API to fetch:
- Current weather conditions
- Hourly precipitation forecasts
- Daily weather forecasts

Umbrella logic:
- **☂️ (urgent)**: Any hour in the next 2 hours has >0.1mm precipitation
- **☔ (later)**: Any hour in the next 16 hours has >0.2mm precipitation

## Credits

Based on the official `omarchy.weather` plugin, enhanced with umbrella alert functionality.

## License

MIT
