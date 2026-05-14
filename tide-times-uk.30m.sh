#!/bin/bash
# <xbar.title>Brighton Marina Tide Times</xbar.title>
# <xbar.refreshTime>30m</xbar.refreshTime>
# <xbar.desc>Shows today's tide times for Brighton Marina from tidetimes.org.uk</xbar.desc>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
# <swiftbar.hideSwiftBar>true</swiftbar.hideSwiftBar>

set -u

DEFAULT_SLUG="brighton-marina"
SHIPPING_FORECAST_AREA="Viking" 
LOCATIONS_PAGE_URL="https://www.tidetimes.org.uk/uk-tides"
BASE_URL="https://www.tidetimes.org.uk"
FORECAST_URL="https://www.metoffice.gov.uk/public/data/CoreProductCache/ShippingForecast/Latest"
PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tide-times-swiftbar"
SELECTED_FILE="$CONFIG_DIR/selected-location"
LOCATIONS_FILE="$CONFIG_DIR/locations.tsv"
SHIPPING_FORECAST_CACHE="$CONFIG_DIR/shipping-forecast.xml"
SELECTED_SHIPPING_FORECAST_FILE="$CONFIG_DIR/selected-shipping-forecast"

mkdir -p "$CONFIG_DIR"

parse_locations_stream() {
  tr '\n' ' ' \
    | grep -oE '<a href="/[^"]+-tide-times" title="[^"]+">[^<]+</a>' \
    | sed -E 's#<a href="/([^"]+)-tide-times" title="[^"]+">([^<]+)</a>#\1\t\2#' \
    | awk -F '\t' 'NF==2 && $1 != "" && $2 != "" { print $1 "\t" $2 }' \
    | sort -u
}

build_locations_cache() {
  local tmp_file
  tmp_file=$(mktemp)

  if curl -fsSL "$LOCATIONS_PAGE_URL" | parse_locations_stream > "$tmp_file" && [ -s "$tmp_file" ]; then
    mv "$tmp_file" "$LOCATIONS_FILE"
    return 0
  fi

  rm -f "$tmp_file"
  return 1
}

parse_shipping_forecast() {
  # Extract all area names and their forecasts from the XML.
  # Multiline values are normalized to single-space strings.
  local xml_file="$1"
  [ ! -f "$xml_file" ] && return 1

  perl -0777 -ne '
    while (m{<area-forecast>(.*?)</area-forecast>}sg) {
      my $block = $1;
      my ($all) = $block =~ m{<all>\s*(.*?)\s*</all>}s;

      # Limit value extraction to the top-level area-forecast fields.
      my $top = $block;
      $top =~ s{<area>.*$}{}s;

      my ($wind) = $top =~ m{<wind>\s*(.*?)\s*</wind>}s;
      my ($seastate) = $top =~ m{<seastate>\s*(.*?)\s*</seastate>}s;
      my ($visibility) = $top =~ m{<visibility>\s*(.*?)\s*</visibility>}s;
      my ($weather) = $top =~ m{<weather>\s*(.*?)\s*</weather>}s;

      for ($all, $wind, $seastate, $visibility, $weather) {
        $_ = "" unless defined $_;
        s/[\r\n]+/ /g;
        s/\s+/ /g;
        s/^\s+|\s+$//g;
        s/\t/ /g;
      }

      next if $all eq "";

      # Some forecasts group areas in <all>, e.g. "Viking, North Utsire, South Utsire".
      # Emit one row per area so menu selection remains granular.
      my @areas = split(/\s*,\s*/, $all);
      for my $area (@areas) {
        next if !defined $area || $area eq "";
        print join("\t", $area, $wind, $seastate, $visibility, $weather), "\n";
      }
    }
  ' "$xml_file"
}

build_shipping_forecast_cache() {
  local shipping_areas_file="$CONFIG_DIR/shipping-forecast-areas.tsv"
  
  if curl -fsSL "$FORECAST_URL" -o "$SHIPPING_FORECAST_CACHE" && [ -s "$SHIPPING_FORECAST_CACHE" ]; then
    # Parse the forecast and build the areas cache
    if parse_shipping_forecast "$SHIPPING_FORECAST_CACHE" > "$shipping_areas_file.tmp" && [ -s "$shipping_areas_file.tmp" ]; then
      mv "$shipping_areas_file.tmp" "$shipping_areas_file"
      return 0
    fi
  fi
  rm -f "$SHIPPING_FORECAST_CACHE"
  return 1
}

build_shipping_areas_cache() {
  local shipping_areas_file="$CONFIG_DIR/shipping-forecast-areas.tsv"
  if [ -s "$SHIPPING_FORECAST_CACHE" ]; then
    if parse_shipping_forecast "$SHIPPING_FORECAST_CACHE" > "$shipping_areas_file.tmp" && [ -s "$shipping_areas_file.tmp" ]; then
      mv "$shipping_areas_file.tmp" "$shipping_areas_file"
      return 0
    fi
  fi
  return 1
}

normalize_shipping_areas_cache() {
  local shipping_areas_file="$CONFIG_DIR/shipping-forecast-areas.tsv"
  local tmp_file

  [ ! -s "$shipping_areas_file" ] && return 1

  tmp_file=$(mktemp)
  if awk -F '\t' 'BEGIN { OFS = "\t" }
    NF >= 5 {
      n = split($1, areas, /,[[:space:]]*/)
      for (i = 1; i <= n; i++) {
        area = areas[i]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", area)
        if (area == "") {
          continue
        }
        if (!seen[area]++) {
          print area, $2, $3, $4, $5
        }
      }
    }
  ' "$shipping_areas_file" > "$tmp_file" && [ -s "$tmp_file" ]; then
    mv "$tmp_file" "$shipping_areas_file"
    return 0
  fi

  rm -f "$tmp_file"
  return 1
}

get_shipping_forecast_for_area() {
  # Get forecast data for a specific area
  # Usage: get_shipping_forecast_for_area "area_name" "forecast_file"
  local area="$1"
  local forecast_file="$2"
  [ ! -f "$forecast_file" ] && return 1
  
  awk -F '\t' -v area="$area" '$1 == area { print $2 "\t" $3 "\t" $4 "\t" $5; exit }' "$CONFIG_DIR/shipping-forecast-areas.tsv" 2>/dev/null
}

case "${1:-}" in
  --set-location)
    if [ -n "${2:-}" ]; then
      echo "$2" > "$SELECTED_FILE"
    fi
    exit 0
    ;;
  --set-shipping-forecast)
    if [ -n "${2:-}" ]; then
      echo "$2" > "$SELECTED_SHIPPING_FORECAST_FILE"
    fi
    exit 0
    ;;
  --refresh-locations)
    rm -f "$LOCATIONS_FILE"
    build_locations_cache >/dev/null 2>&1 || true
    exit 0
    ;;
  --refresh-shipping-forecast)
    rm -f "$SHIPPING_FORECAST_CACHE" "$CONFIG_DIR/shipping-forecast-areas.tsv"
    build_shipping_forecast_cache >/dev/null 2>&1 || true
    exit 0
    ;;
esac

if [ ! -s "$LOCATIONS_FILE" ]; then
  build_locations_cache >/dev/null 2>&1 || true
fi

# Ensure shipping forecast cache exists
SHIPPING_FORECAST_AREAS_FILE="$CONFIG_DIR/shipping-forecast-areas.tsv"
if [ ! -s "$SHIPPING_FORECAST_CACHE" ]; then
  build_shipping_forecast_cache >/dev/null 2>&1 || true
fi

# If we still don't have a cache, try to use sample data
if [ ! -s "$SHIPPING_FORECAST_CACHE" ] && [ -f "$PLUGIN_DIR/sample-shipping-forecast-data.xml" ]; then
  cp "$PLUGIN_DIR/sample-shipping-forecast-data.xml" "$SHIPPING_FORECAST_CACHE"
  build_shipping_areas_cache >/dev/null 2>&1 || true
fi

# Ensure area list is granular even if an older cache contains grouped names.
normalize_shipping_areas_cache >/dev/null 2>&1 || true

selected_slug="$DEFAULT_SLUG"
if [ -f "$SELECTED_FILE" ]; then
  selected_slug=$(tr -d '\r\n' < "$SELECTED_FILE")
fi

# Load selected shipping forecast area
selected_shipping_area="$SHIPPING_FORECAST_AREA"
if [ -f "$SELECTED_SHIPPING_FORECAST_FILE" ]; then
  selected_shipping_area=$(tr -d '\r\n' < "$SELECTED_SHIPPING_FORECAST_FILE")
fi

if [ -s "$LOCATIONS_FILE" ]; then
  selected_title=$(awk -F '\t' -v slug="$selected_slug" '$1 == slug { print $2; exit }' "$LOCATIONS_FILE")
else
  selected_title="Brighton Marina"
fi

if [ -z "${selected_title:-}" ] && [ -s "$LOCATIONS_FILE" ]; then
  selected_slug=$(awk -F '\t' 'NR==1 { print $1; exit }' "$LOCATIONS_FILE")
  selected_title=$(awk -F '\t' 'NR==1 { print $2; exit }' "$LOCATIONS_FILE")
  echo "$selected_slug" > "$SELECTED_FILE"
fi

if [ -z "${selected_slug:-}" ]; then
  selected_slug="$DEFAULT_SLUG"
fi

RSS_URL="$BASE_URL/$selected_slug-tide-times.rss"

# Cache file for today's RSS data (keyed by slug + date so it's always fresh)
TODAY=$(date +"%Y-%m-%d")
RSS_CACHE_FILE="$CONFIG_DIR/rss-${selected_slug}-${TODAY}.cache"
# Clean up stale caches from previous days
find "$CONFIG_DIR" -maxdepth 1 -name "rss-*.cache" ! -name "rss-${selected_slug}-${TODAY}.cache" -delete 2>/dev/null || true

# Fetch the RSS feed, falling back to today's cache if the network is unavailable
data=$(curl -s --max-time 10 "$RSS_URL")
if echo "$data" | grep -q '<item>'; then
  # Successful fetch — update the cache
  echo "$data" > "$RSS_CACHE_FILE"
elif [ -s "$RSS_CACHE_FILE" ]; then
  # Network unavailable but we have today's cache — use it and schedule a refresh
  data=$(cat "$RSS_CACHE_FILE")
fi

# Extract the <description> from the first <item>
desc=$(echo "$data" | awk 'BEGIN{RS="<item>";FS="</item>"} NR==2{print $1}' | grep -o '<description>.*</description>' | sed 's/<\/?description>//g')

# Decode HTML entities and split <br/> to newlines using Perl for robustness
desc=$(echo "$desc" | perl -pe 's/&lt;br\/?&gt;|&lt;br&gt;|<br\/?\s*>/\n/gi; s/&amp;/\&/g; s/&lt;/</g; s/&gt;/>/g; s/&quot;/"/g; s/&#x28;/(/g; s/&#x29;/)/g')

# Remove HTML tags and blank lines
plain=$(echo "$desc" | sed 's/<[^>]*>//g' | sed '/^\s*$/d')



# --- DEBUGGING: Set this to e.g. "14:30" to spoof the time of day ---
# Leave empty to use the real current time
SPOOF_TIME=""

# Get current time in minutes since midnight, using spoof if set
if [ -n "$SPOOF_TIME" ]; then
  spoof_hour=${SPOOF_TIME%:*}
  spoof_minute=${SPOOF_TIME#*:}
  now_minutes=$((10#$spoof_hour * 60 + 10#$spoof_minute))
else
  now_minutes=$(date +"%H")
  now_minutes=$((10#$now_minutes * 60 + 10#$(date +"%M")))
fi

# Filter out past tide events and remove empty lines
all_tide_lines=$(echo "$plain" | grep -E '^[0-9]{2}:[0-9]{2}.*' | sed '/^\s*$/d')
upcoming_lines=$(echo "$all_tide_lines" | while IFS= read -r line; do
  [ -z "$(echo "$line" | tr -d '[:space:]')" ] && continue
  tide_time=$(echo "$line" | grep -oE '^[0-9]{2}:[0-9]{2}')
  tide_hour=${tide_time%:*}
  tide_minute=${tide_time#*:}
  tide_minutes=$((10#$tide_hour * 60 + 10#$tide_minute))
  if [ $tide_minutes -ge $now_minutes ]; then
    echo "$line"
  fi
done)

# Always compute the most recent past tide
recent_past_line=$(echo "$all_tide_lines" | while IFS= read -r line; do
  [ -z "$(echo "$line" | tr -d '[:space:]')" ] && continue
  tide_time=$(echo "$line" | grep -oE '^[0-9]{2}:[0-9]{2}')
  tide_hour=${tide_time%:*}
  tide_minute=${tide_time#*:}
  tide_minutes=$((10#$tide_hour * 60 + 10#$tide_minute))
  if [ $tide_minutes -le $now_minutes ]; then
    echo "$tide_minutes $line"
  fi
done | sort -n | tail -1 | cut -d' ' -f2-)


# Function to round depth to 1 decimal place, remove 'Tide', and remove parentheses from depth
round_depth_and_clean() {
  # Expects a line like: 19:11 - Low Tide (1.04m)
  echo "$1" | perl -pe '
    s/\bHigh Tide\b|\bHigh\b/⬆/g;
    s/\bLow Tide\b|\bLow\b/⬇/g;
    s/\((\d+\.\d{1,2})m\)/" ".sprintf("%.1f", $1)."m"/e;
    s/  / /g;
    s/^([0-9]{2}:[0-9]{2}) - /$1 /'
}

round_depth_and_clean_with_time_until() {
  local line="$1"
  local tide_time=$(echo "$line" | grep -oE '^[0-9]{2}:[0-9]{2}')
  local tide_hour=${tide_time%:*}
  local tide_minute=${tide_time#*:}
  local tide_minutes=$((10#$tide_hour * 60 + 10#$tide_minute))
  local minutes_until=$((tide_minutes - now_minutes))

  local time_until=""
  if [ $minutes_until -gt 0 ]; then
    local hours=$(( (minutes_until + 30) / 60 ))
    if [ $hours -gt 0 ]; then
      time_until="~ ${hours} hour$( [ $hours -gt 1 ] && echo "s" )"
    else
      time_until="~ Soon"
    fi
  fi

  echo "$(round_depth_and_clean "$line") $time_until"
}



# Fetch windspeed for the selected location (UK only)
WIND_PLACE="${selected_title:-Brighton Marina} UK"
WIND_PLACE_ENCODED=$(echo "$WIND_PLACE" | sed 's/ /+/g')
wind_raw=$(curl -s "wttr.in/${WIND_PLACE_ENCODED}?u&format=%w?")
# Remove trailing % or ? and whitespace
wind_clean=$(echo "$wind_raw" | sed 's/[?%].*$//' | tr -d '\n ')

# Determine what to show in the menu bar (topline)
topline=""

# Check if RSS feed is empty or missing
if [ -z "$data" ] || ! echo "$data" | grep -q '<item>' ; then
  topline="???"
  # perform a refresh
  build_locations_cache >/dev/null 2>&1 || true
else
  # Try to get the first upcoming tide
  first_upcoming=""
  if IFS= read -r first_upcoming_line && [ -n "$first_upcoming_line" ]; then
    first_upcoming="$first_upcoming_line"
  fi <<< "$upcoming_lines"
  if [ -n "$first_upcoming" ]; then
    topline="$(round_depth_and_clean "$first_upcoming")"
  else
    # If no upcoming, use the most recent past tide (no 'gone' in topbar)
    if [ -n "$recent_past_line" ]; then
      topline="$(round_depth_and_clean "$recent_past_line")"
    else
      topline="???"
    fi
  fi
fi

# Output for xbar/SwiftBar (main menu bar)
if [ -z "$(echo "$topline" | tr -d '[:space:]')" ]; then
  echo ":helm: ???"
else
  # Append windspeed if available and not empty, using '-' instead of '|'
  if [ -n "$wind_clean" ]; then
    echo ":helm: $topline $wind_clean"
  else
    echo ":helm: $topline"
  fi
fi

echo "---"

# We are now in the dropdown menu

echo "**${selected_title:-Unknown}** | md=true bash=true terminal=false" # No action on click, just for formatting with color

echo "--Refresh Locations | bash=\"$0\" param1=--refresh-locations terminal=false refresh=true"
echo "-----"
if [ -s "$LOCATIONS_FILE" ]; then
  while IFS=$'\t' read -r slug title; do
    [ -z "$slug" ] && continue
    marker=""
    if [ "$slug" = "$selected_slug" ]; then
      marker="✓ "
    fi
    echo "--${marker}${title} | bash=\"$0\" param1=--set-location param2=\"$slug\" terminal=false refresh=true"
  done < "$LOCATIONS_FILE"
else
  echo "No locations available"
fi

echo "-----"
echo "**${selected_shipping_area}** | md=true bash=true terminal=false"
echo "--Refresh Shipping Areas | bash=\"$0\" param1=--refresh-shipping-forecast terminal=false refresh=true"
echo "-----"

# Display shipping forecast areas
if [ -s "$SHIPPING_FORECAST_AREAS_FILE" ]; then
  while IFS=$'\t' read -r area wind seastate visibility weather; do
    [ -z "$area" ] && continue
    marker=""
    if [ "$area" = "$selected_shipping_area" ]; then
      marker="✓ "
    fi
    echo "--${marker}${area} | bash=\"$0\" param1=--set-shipping-forecast param2=\"$area\" terminal=false refresh=true"
  done < "$SHIPPING_FORECAST_AREAS_FILE"
else
  echo "--No forecast areas available"
fi

echo "---"

# Show today's date in the menu, with color for readability
echo "*$(date +"%A %-d %B %Y")* | md=true bash=true terminal=false"

# Show all upcoming tide events, or if none, the most recent past tide
if [ -n "$upcoming_lines" ]; then
  echo "$upcoming_lines" | while IFS= read -r line; do
    [ -z "$(echo "$line" | tr -d '[:space:]')" ] && continue
    echo ":helm: $(round_depth_and_clean_with_time_until "$line") | bash=true terminal=false"
  done
elif [ -n "$recent_past_line" ]; then
  # Show the most recent past tide in the dropdown, with 'Concludes Today' appended
  echo ":helm: $(round_depth_and_clean "$recent_past_line") ~ Concludes Today | bash=true terminal=false"
fi

echo "---"

# Display forecast for selected shipping area
if [ -s "$SHIPPING_FORECAST_AREAS_FILE" ]; then
  forecast_data=$(awk -F '\t' -v area="$selected_shipping_area" '$1 == area { print $2 "\t" $3 "\t" $4 "\t" $5; exit }' "$SHIPPING_FORECAST_AREAS_FILE")
  if [ -n "$forecast_data" ]; then
    wind=$(echo "$forecast_data" | cut -f1)
    seastate=$(echo "$forecast_data" | cut -f2)
    visibility=$(echo "$forecast_data" | cut -f3)
    weather=$(echo "$forecast_data" | cut -f4)

    # Remove any leading/trailing whitespace from the forecast data
    wind=$(echo "$wind" | sed 's/^[ \t]*//;s/[ \t]*$//')
    seastate=$(echo "$seastate" | sed 's/^[ \t]*//;s/[ \t]*$//')
    visibility=$(echo "$visibility" | sed 's/^[ \t]*//;s/[ \t]*$//')
    weather=$(echo "$weather" | sed 's/^[ \t]*//;s/[ \t]*$//')

    # add fullstop to end of string if not already present
    [ -n "$wind" ] && [[ ! "$wind" =~ [\.\!]$ ]] && wind="$wind."
    [ -n "$seastate" ] && [[ ! "$seastate" =~ [\.\!]$ ]] && seastate="$seastate."
    [ -n "$visibility" ] && [[ ! "$visibility" =~ [\.\!]$ ]] && visibility="$visibility."
    [ -n "$weather" ] && [[ ! "$weather" =~ [\.\!]$ ]] && weather="$weather."
    
    # Replace North with N, East with E, South with S, West with W, Northwest with NW, Northeast with NE, Southwest with SW, Southeast with SE
    replacements=(
      "Northwest:NW"
      "northwest:NW"
      "Northwesterly:NW-ly"
      "northwesterly:NW-ly"
      "Northeast:NE"
      "northeast:NE"
      "Northeasterly:N-ly"
      "northeasterly:N-ly"
      "Southwest:SW"
      "southwest:SW"
      "Southwesterly:S-ly"
      "southwesterly:S-ly"
      "Southeast:SE"
      "southeast:SE"
      "Southeasterly:S-ly"
      "southeasterly:S-ly"
      "North:N"
      "north:N"
      "Northerly:-ly"
      "northerly:-ly"
      "East:E"
      "east:E"
      "Easterly:E-ly"
      "easterly:E-ly"
      "South:S"
      "south:S"
      "Southerly:S-ly"
      "southerly:S-ly"
      "West:W"
      "west:W"
      "Westerly:W-ly"
      "westerly:W-ly"
    )
    for replacement in "${replacements[@]}"; do
      IFS=':' read -r long short <<< "$replacement"
      wind=$(echo "$wind" | sed "s/[[:<:]]$long[[:>:]]/$short/g")
      seastate=$(echo "$seastate" | sed "s/[[:<:]]$long[[:>:]]/$short/g")
      visibility=$(echo "$visibility" | sed "s/[[:<:]]$long[[:>:]]/$short/g")
      weather=$(echo "$weather" | sed "s/[[:<:]]$long[[:>:]]/$short/g")
    done

    echo "*:wind:* $wind | md=true bash=true terminal=false"
    echo "*:waveform.path.ecg:* $seastate | md=true bash=true terminal=false"
    echo "*:paintbrush:* $visibility | md=true bash=true terminal=false"
    echo "*:sun.max:* $weather | md=true bash=true terminal=false"
  fi
fi

echo "---"
echo "Wind: wttr.in (${WIND_PLACE:-Unknown}) | href=https://wttr.in/${WIND_PLACE_ENCODED}"
echo "Tides: tidetimes.org.uk (${selected_title:-Unknown}) | href=https://www.tidetimes.org.uk/${selected_slug}-tide-times"
echo "Shipping Forecast: Met Office (${selected_shipping_area}) | href=https://www.metoffice.gov.uk/public/data/CoreProductCache/ShippingForecast/Latest"
echo "Fetched: $(date +"%Y-%m-%d %H:%M:%S")"
echo "---"
echo "Refresh | refresh=true"