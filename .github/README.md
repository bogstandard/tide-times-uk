# Tide Times UK SwiftBar Plugin

This SwiftBar plugin displays UK tide times and now includes the latest UK Shipping Forecast.

## Features

- Shows today's tide times for your selected UK location (from tidetimes.org.uk)
- Dropdown menu to select from hundreds of UK tide locations
- Displays wind speed for your selected location (via wttr.in)
- Displays the latest UK Shipping Forecast, with area selection and details for each area
- Caches location and forecast data for fast updates

## Shipping Forecast

- The plugin fetches and caches the latest UK Shipping Forecast from the Met Office
- You can select your preferred Shipping Forecast area from the dropdown menu
- The forecast for the selected area (wind, sea state, visibility, weather) is shown in the dropdown
- If the Met Office feed is unavailable, a sample forecast is used as fallback

## Usage

1. Place the `tide-times-uk.30m.sh` script in your SwiftBar or xbar plugins directory
2. Make it executable: `chmod +x tide-times-uk.30m.sh`
3. Click the menu bar item to select your tide location and Shipping Forecast area
4. Use the refresh options in the dropdown to update locations or forecast data

## Configuration & Caching

- User selections and cached data are stored in `~/.config/tide-times-swiftbar/`
- The plugin will auto-refresh every 30 minutes (or as configured)

## Requirements

- Bash, curl, awk, sed, and standard Unix tools

## Credits

- Tide data: [tidetimes.org.uk](https://www.tidetimes.org.uk/)
- Shipping Forecast: [Met Office](https://www.metoffice.gov.uk/)
- Wind data: [wttr.in](https://wttr.in/)

---

For issues or suggestions, open an issue or PR!
