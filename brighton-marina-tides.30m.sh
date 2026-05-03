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
LOCATIONS_PAGE_URL="https://www.tidetimes.org.uk/uk-tides"
BASE_URL="https://www.tidetimes.org.uk"
PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tide-times-swiftbar"
SELECTED_FILE="$CONFIG_DIR/selected-location"
LOCATIONS_FILE="$CONFIG_DIR/locations.tsv"

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

case "${1:-}" in
  --set-location)
    if [ -n "${2:-}" ]; then
      echo "$2" > "$SELECTED_FILE"
    fi
    exit 0
    ;;
  --refresh-locations)
    rm -f "$LOCATIONS_FILE"
    build_locations_cache >/dev/null 2>&1 || true
    exit 0
    ;;
esac

if [ ! -s "$LOCATIONS_FILE" ]; then
  build_locations_cache >/dev/null 2>&1 || true
fi

selected_slug="$DEFAULT_SLUG"
if [ -f "$SELECTED_FILE" ]; then
  selected_slug=$(tr -d '\r\n' < "$SELECTED_FILE")
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

# Fetch the RSS feed
data=$(curl -s "$RSS_URL")

# Extract the <description> from the first <item>
desc=$(echo "$data" | awk 'BEGIN{RS="<item>";FS="</item>"} NR==2{print $1}' | grep -o '<description>.*</description>' | sed 's/<\/?description>//g')

# Decode HTML entities and split <br/> to newlines using Perl for robustness
desc=$(echo "$desc" | perl -pe 's/&lt;br\/?&gt;|&lt;br&gt;|<br\/?\s*>/\n/gi; s/&amp;/\&/g; s/&lt;/</g; s/&gt;/>/g; s/&quot;/"/g; s/&#x28;/(/g; s/&#x29;/)/g')

# Remove HTML tags and blank lines
plain=$(echo "$desc" | sed 's/<[^>]*>//g' | sed '/^\s*$/d')


# Get current time in minutes since midnight
now_minutes=$(date +"%H")
now_minutes=$((10#$now_minutes * 60 + 10#$(date +"%M")))

# Filter out past tide events
upcoming_lines=$(echo "$plain" | grep -E '^[0-9]{2}:[0-9]{2}.*' | while IFS= read -r line; do
  tide_time=$(echo "$line" | grep -oE '^[0-9]{2}:[0-9]{2}')
  tide_hour=${tide_time%:*}
  tide_minute=${tide_time#*:}
  tide_minutes=$((10#$tide_hour * 60 + 10#$tide_minute))
  if [ $tide_minutes -ge $now_minutes ]; then
    echo "$line"
  fi
done)


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
    local hours=$((minutes_until / 60))
    if [ $hours -eq 0 ]; then
      time_until="- Soon"
    else
      time_until="- ${hours} hour$( [ $hours -gt 1 ] && echo "s" )"
    fi
  fi

  echo "$(round_depth_and_clean "$line") $time_until"
}

# Show only the first upcoming tide event in the menu bar, rounded and cleaned
topline=$(echo "$upcoming_lines" | head -1)
if [ -n "$topline" ]; then
  topline=$(round_depth_and_clean "$topline")
fi


# Output for xbar/SwiftBar
if [ -n "$topline" ]; then
  echo ":helm: $topline"
else
  echo ":helm: ???"
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

# Show today's date in the menu, with color for readability
echo "*$(date +"%A %-d %B %Y")* | md=true bash=true terminal=false"


# Show all upcoming tide events, one per line, rounded and cleaned, with color for readability
# Also show time until the tide event, e.g. "in 1h 15m" or "in 45m"
echo "$upcoming_lines" | while IFS= read -r line; do
  echo "$(round_depth_and_clean_with_time_until "$line") | bash=true terminal=false" # No action on click, just for formatting with color
done

echo "---"
echo "Source: tidetimes.org.uk | href=https://www.tidetimes.org.uk/${selected_slug}-tide-times"
echo "Fetched: $(date +"%Y-%m-%d %H:%M:%S")"
echo "---"
echo "Refresh | refresh=true"