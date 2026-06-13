#!/bin/bash
# setup-cron.sh - Set up the weekly body-tracker report cron job.
# Generates a small runner script and installs a crontab entry that delivers the
# weekly report every Monday at 08:00 (server local time).
#
# Configure delivery via environment variables before running:
#   BODY_TRACKER_NOTIFY_CMD  Command that delivers the report. It is called as:
#                              "$NOTIFY_CMD" "<report text>" whatsapp "<recipient>"
#                            Provide your own sender (e.g. a WhatsApp/Telegram bridge).
#                            Default: `echo` (just writes to the cron log).
#   BODY_TRACKER_RECIPIENT   Optional recipient handle/number passed to the notify cmd.
#
# Example:
#   BODY_TRACKER_NOTIFY_CMD="$HOME/bin/send-reminder.sh" \
#   BODY_TRACKER_RECIPIENT="+62XXXXXXXXXX" \
#   bash scripts/setup-cron.sh
#
# NOTE: cron uses the server's local timezone. Make sure the server TZ matches yours,
# or adjust the "0 8 * * 1" schedule below.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPORTER="$SCRIPT_DIR/weekly-report.sh"
BIN_DIR="$HOME/bin"
LOG_FILE="$HOME/.body-tracker/logs/body-tracker.log"
CATALYZER="$BIN_DIR/body-tracker-weekly.sh"

NOTIFY_CMD="${BODY_TRACKER_NOTIFY_CMD:-echo}"
RECIPIENT="${BODY_TRACKER_RECIPIENT:-}"

mkdir -p "$BIN_DIR" "$(dirname "$LOG_FILE")"

# Generate the cron runner. Values known now are injected; runtime refs are escaped (\$).
cat > "$CATALYZER" << SENDER_EOF
#!/bin/bash
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:$HOME/bin:\$PATH"

LOG_FILE="$LOG_FILE"

# Generate the report for the previous completed week (no date arg = last Mon-Sun)
REPORT=\$(bash "$REPORTER" 2>&1)

if [ -n "\$REPORT" ]; then
    "$NOTIFY_CMD" "\$REPORT" whatsapp "$RECIPIENT"
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Weekly report sent" >> "\$LOG_FILE"
else
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Weekly report empty" >> "\$LOG_FILE"
fi
SENDER_EOF

chmod +x "$CATALYZER"

# Install/refresh the crontab entry (Monday 08:00 server local time)
crontab -l > /tmp/cron_body.tmp 2>/dev/null || true
grep -v "body-tracker-weekly" /tmp/cron_body.tmp > /tmp/cron_body.tmp2 2>/dev/null || true
echo "# Body Tracker Weekly Report - Every Monday 08:00 (server local time)" >> /tmp/cron_body.tmp2
echo "0 8 * * 1 $CATALYZER" >> /tmp/cron_body.tmp2
crontab /tmp/cron_body.tmp2
rm -f /tmp/cron_body.tmp /tmp/cron_body.tmp2

echo "✅ Cron job set up: weekly report every Monday 08:00 (server local time)"
echo "   Runner: $CATALYZER"
crontab -l | grep body-tracker
