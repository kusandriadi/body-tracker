#!/bin/bash
# setup-cron.sh - Set up the body-tracker report cron jobs.
# Generates small runner scripts and installs crontab entries that deliver:
#   - the WEEKLY report  every Monday      at 08:00 (server local time)
#   - the MONTHLY report on the 1st of the month at 08:00 (server local time)
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
# or adjust the schedules below.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WEEKLY_REPORTER="$SCRIPT_DIR/weekly-report.sh"
MONTHLY_REPORTER="$SCRIPT_DIR/monthly-report.sh"
BIN_DIR="$HOME/bin"
LOG_FILE="$HOME/.body-tracker/logs/body-tracker.log"
CATALYZER_W="$BIN_DIR/body-tracker-weekly.sh"
CATALYZER_M="$BIN_DIR/body-tracker-monthly.sh"

NOTIFY_CMD="${BODY_TRACKER_NOTIFY_CMD:-echo}"
RECIPIENT="${BODY_TRACKER_RECIPIENT:-}"

mkdir -p "$BIN_DIR" "$(dirname "$LOG_FILE")"

# Generate a cron runner. Values known now are injected; runtime refs are escaped (\$).
# $1 = output path, $2 = reporter script, $3 = label (Weekly|Monthly)
make_runner() {
    local out="$1" reporter="$2" label="$3"
    cat > "$out" << SENDER_EOF
#!/bin/bash
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:$HOME/bin:\$PATH"

LOG_FILE="$LOG_FILE"

# Generate the report for the previous completed period (no date arg)
REPORT=\$(bash "$reporter" 2>&1)

if [ -n "\$REPORT" ]; then
    "$NOTIFY_CMD" "\$REPORT" whatsapp "$RECIPIENT"
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] $label report sent" >> "\$LOG_FILE"
else
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] $label report empty" >> "\$LOG_FILE"
fi
SENDER_EOF
    chmod +x "$out"
}

make_runner "$CATALYZER_W" "$WEEKLY_REPORTER" "Weekly"
make_runner "$CATALYZER_M" "$MONTHLY_REPORTER" "Monthly"

# Install/refresh the crontab entries (server local time)
crontab -l > /tmp/cron_body.tmp 2>/dev/null || true
grep -v -e "body-tracker-weekly" -e "body-tracker-monthly" /tmp/cron_body.tmp > /tmp/cron_body.tmp2 2>/dev/null || true
echo "# Body Tracker Weekly Report - Every Monday 08:00 (server local time)" >> /tmp/cron_body.tmp2
echo "0 8 * * 1 $CATALYZER_W" >> /tmp/cron_body.tmp2
echo "# Body Tracker Monthly Report - 1st of month 08:00 (server local time)" >> /tmp/cron_body.tmp2
echo "0 8 1 * * $CATALYZER_M" >> /tmp/cron_body.tmp2
crontab /tmp/cron_body.tmp2
rm -f /tmp/cron_body.tmp /tmp/cron_body.tmp2

echo "✅ Cron jobs set up (server local time):"
echo "   - Weekly  report: Monday 08:00       ($CATALYZER_W)"
echo "   - Monthly report: 1st of month 08:00 ($CATALYZER_M)"
crontab -l | grep body-tracker
