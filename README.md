# Body Tracker

A Claude Code / agent **skill** for tracking body weight, calorie intake (from food/drink
photos or text), and physical activity (from fitness-app/smartwatch screenshots) — with a
scientifically-grounded calorie-deficit engine.

It is designed to be driven by an AI agent: the user sends a food photo, a scale photo, or a
fitness screenshot, the agent extracts the data with a vision model, and these scripts store
it and produce daily/weekly/monthly recaps with personalized suggestions.

## Features

- **Food logging with full macros** — every calorie figure is always reported together with
  **protein, carbohydrate, and fat** (grams).
- **Activity logging** — type, duration, calories burned, distance.
- **Weight logging** — manual number or scale photo.
- **Calorie-deficit engine** based on the most widely used and trusted methods:
  - **BMR** via the **Mifflin-St Jeor** equation (recommended by the Academy of Nutrition
    & Dietetics).
  - **TDEE** = BMR × activity factor.
  - Deficit rates `mild` (250 kcal/day ≈ 0.23 kg/week), `moderate` (500 ≈ 0.45 kg/week,
    the default and most-recommended), `aggressive` (750 ≈ 0.68 kg/week).
  - Safety floors (never below 1200 kcal women / 1500 kcal men), max ~1% bodyweight/week,
    protein target 1.6–2.2 g/kg to preserve muscle, and weeks-to-goal estimates.
- **Recaps** — daily, weekly, and monthly summaries, plus progress vs. goal and BMI.
- **Undo** — remove the last mis-logged meal or activity.
- **Optional weekly cron report** delivered through a notifier command you configure.

## Requirements

- `bash` and `python3` (standard library only — no pip installs).
- An agent/host with a vision-capable image tool for photo analysis (the skill references a
  model id in `SKILL.md`; swap it for whatever your host provides).

## Usage

The agent reads `SKILL.md` for the full workflow. The scripts can also be used directly:

```bash
# Create your profile (height_cm weight_kg age target_kg [gender] [activity_level] [deficit_rate])
bash scripts/body-tracker.sh init-profile 170 85 30 70 male moderate moderate

# Log a meal (JSON of detected items)
bash scripts/body-tracker.sh log-meal '{"type":"lunch","time":"12:30","items":[{"name":"Nasi Padang","calories":650,"protein":25,"carbs":80,"fat":28}]}'

# Log activity / weight
bash scripts/body-tracker.sh log-activity '{"type":"running","time":"06:30","duration_min":30,"calories_burned":250,"distance_km":5}'
bash scripts/body-tracker.sh log-weight 84.5

# Undo the last entry if it was mis-detected
bash scripts/body-tracker.sh remove-last meal

# Recaps
bash scripts/body-tracker.sh daily
bash scripts/body-tracker.sh weekly
bash scripts/body-tracker.sh monthly
bash scripts/body-tracker.sh progress

# Richer weekly/monthly reports with suggestions
bash scripts/weekly-report.sh
bash scripts/monthly-report.sh
```

Data is stored as one JSON file per day under `~/.body-tracker/`, with the
profile in `profile.json`. Override the location with the `DATA_DIR` environment variable.

## Weekly cron report (optional)

```bash
BODY_TRACKER_NOTIFY_CMD="$HOME/bin/your-sender.sh" \
BODY_TRACKER_RECIPIENT="<your handle/number>" \
bash scripts/setup-cron.sh
```

This installs a Monday-08:00 (server local time) cron job that builds the weekly report and
passes it to your notifier command. Without configuration it just writes to a log file.

## Notes

The language of user-facing messages is **Bahasa Indonesia** (the skill was built for an
Indonesian user); calculations and structure are language-agnostic. This repository contains
no personal data — configure your own data directory and notifier.

## License

MIT — see [LICENSE](LICENSE).
