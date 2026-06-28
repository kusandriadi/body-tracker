#!/bin/bash
# setup-cron.sh - Set up body tracker report cron jobs
#   - Weekly  report: every Monday    08:00 WIB
#   - Monthly report: every 1st of month 08:00 WIB (covers the month that just ended)
# Both sent via the configured notification channel/targets.
# NOTE: this server's timezone is Asia/Jakarta (WIB), so cron runs in WIB —
# the schedules below are WIB local time, NOT a UTC offset.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPORTER="$SCRIPT_DIR/weekly-report.sh"
SENDER="/home/kusa/bin/send-reminder.sh"
LOG_FILE="/home/kusa/data/openclaw/logs/body-tracker.log"
ENV_FILE="$SCRIPT_DIR/../../../skill.env"

mkdir -p "$(dirname "$LOG_FILE")"

# Create the cron sender script
CATALYZER="/home/kusa/bin/body-tracker-weekly.sh"
cat > "$CATALYZER" << 'SENDER_EOF'
#!/bin/bash
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:/home/kusa/bin:$PATH"

LOG_FILE="/home/kusa/data/openclaw/logs/body-tracker.log"
ENV_FILE="/home/kusa/.openclaw/workspace/skill.env"
NOTIFY_CHANNEL="whatsapp"
NOTIFY_TARGETS=""
# shellcheck disable=SC1090
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

# Generate report for the previous completed week (no date arg = last Mon–Sun)
REPORT=$(bash /home/kusa/.openclaw/workspace/skills/body-tracker/scripts/weekly-report.sh 2>&1)

if [ -n "$REPORT" ] && [ -n "${NOTIFY_TARGETS:-}" ]; then
    # shellcheck disable=SC2086
    /home/kusa/bin/send-reminder.sh "$REPORT" "$NOTIFY_CHANNEL" $NOTIFY_TARGETS
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 📊 Weekly report sent" >> "$LOG_FILE"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️ Weekly report empty or no notify target configured" >> "$LOG_FILE"
fi
SENDER_EOF

chmod +x "$CATALYZER"

# Create the monthly cron sender script
CATALYZER_M="/home/kusa/bin/body-tracker-monthly.sh"
cat > "$CATALYZER_M" << 'SENDER_EOF'
#!/bin/bash
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:/home/kusa/bin:$PATH"

LOG_FILE="/home/kusa/data/openclaw/logs/body-tracker.log"
ENV_FILE="/home/kusa/.openclaw/workspace/skill.env"
NOTIFY_CHANNEL="whatsapp"
NOTIFY_TARGETS=""
# shellcheck disable=SC1090
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

# Generate report for the previous completed month (no arg = last month)
REPORT=$(bash /home/kusa/.openclaw/workspace/skills/body-tracker/scripts/monthly-report.sh 2>&1)

if [ -n "$REPORT" ] && [ -n "${NOTIFY_TARGETS:-}" ]; then
    # shellcheck disable=SC2086
    /home/kusa/bin/send-reminder.sh "$REPORT" "$NOTIFY_CHANNEL" $NOTIFY_TARGETS
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 📊 Monthly report sent" >> "$LOG_FILE"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️ Monthly report empty or no notify target configured" >> "$LOG_FILE"
fi
SENDER_EOF

chmod +x "$CATALYZER_M"

# Add cron entries (WIB; server TZ = Asia/Jakarta, so cron uses WIB)
crontab -l > /tmp/cron_body.tmp 2>/dev/null || true

# Remove old entries if exist
grep -v -e "body-tracker-weekly" -e "body-tracker-monthly" /tmp/cron_body.tmp > /tmp/cron_body.tmp2 2>/dev/null || true

echo "# Body Tracker Weekly Report - Every Monday 08:00 WIB" >> /tmp/cron_body.tmp2
echo "0 8 * * 1 /home/kusa/bin/body-tracker-weekly.sh" >> /tmp/cron_body.tmp2
echo "# Body Tracker Monthly Report - 1st of month 08:00 WIB" >> /tmp/cron_body.tmp2
echo "0 8 1 * * /home/kusa/bin/body-tracker-monthly.sh" >> /tmp/cron_body.tmp2

crontab /tmp/cron_body.tmp2
rm -f /tmp/cron_body.tmp /tmp/cron_body.tmp2

echo "✅ Cron jobs set up:"
echo "   - Weekly  report: Senin 08:00 WIB        ($CATALYZER)"
echo "   - Monthly report: tgl 1 jam 08:00 WIB    ($CATALYZER_M)"
crontab -l | grep body-tracker
