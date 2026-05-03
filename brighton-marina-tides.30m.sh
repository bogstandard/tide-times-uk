#!/bin/bash
# <xbar.title>Brighton Marina Tide Times</xbar.title>
# <xbar.refreshTime>30m</xbar.refreshTime>
# <xbar.desc>Shows today's tide times for Brighton Marina from tidetimes.org.uk</xbar.desc>

RSS_URL="https://www.tidetimes.org.uk/brighton-marina-tide-times.rss"

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


# Show all upcoming tide events, one per line, rounded and cleaned, with color for readability
echo "$upcoming_lines" | while IFS= read -r line; do
  echo "$(round_depth_and_clean "$line")"
done

echo "---"
echo "Source: tidetimes.org.uk"
echo "$RSS_URL"