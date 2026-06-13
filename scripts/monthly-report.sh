#!/bin/bash
# monthly-report.sh - Generate monthly body tracker report with suggestions.
# Usage: monthly-report.sh [YYYY-MM | YYYY-MM-DD]
#   No arg  -> the PREVIOUS completed month.
#   With arg-> the month containing that date.
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:/home/kusa/bin:$PATH"

DATA_DIR="${DATA_DIR:-/home/kusa/data/openclaw/body-tracker}"
ARG="${1:-}"
if [ -n "$ARG" ]; then
    MONTH="${ARG:0:7}"
else
    MONTH=$(date -d "$(date +%Y-%m-01) -1 day" '+%Y-%m')
fi

DATA_DIR="$DATA_DIR" MONTH="$MONTH" python3 << 'PYEOF'
import json, os, datetime

data_dir = os.environ['DATA_DIR']
month_key = os.environ['MONTH']
year, mon = int(month_key[:4]), int(month_key[5:7])

first = datetime.date(year, mon, 1)
if mon == 12:
    nxt = datetime.date(year + 1, 1, 1)
else:
    nxt = datetime.date(year, mon + 1, 1)
days_in_month = (nxt - first).days
month_name = first.strftime('%B %Y')

lines = [f'📊 *Laporan Bulanan Body Tracker*', f'*{month_name}*', '']

# Load profile
pfile = os.path.join(data_dir, 'profile.json')
profile = {}
if os.path.exists(pfile):
    with open(pfile) as f:
        profile = json.load(f)

# Collect daily data
days_data = []
skipped = 0
for day in range(1, days_in_month + 1):
    d = datetime.date(year, mon, day)
    fpath = os.path.join(data_dir, f'{d.isoformat()}.json')
    if os.path.exists(fpath):
        try:
            with open(fpath) as f:
                data = json.load(f)
        except (json.JSONDecodeError, ValueError):
            skipped += 1
            continue
        s = data.get('daily_summary', {})
        days_data.append({
            'date': d,
            'cal_in': s.get('total_calories_in', 0),
            'cal_out': s.get('total_calories_out', 0),
            'net': s.get('net_calories', 0),
            'protein': s.get('protein_g', 0),
            'carbs': s.get('carbs_g', 0),
            'fat': s.get('fat_g', 0),
            'meals': len(data.get('meals', [])),
            'activities': len(data.get('activities', [])),
            'weight': data.get('weight', {}).get('value'),
        })

if not days_data:
    lines.append(f'Tidak ada data untuk {month_name}.' + (f' ({skipped} file rusak dilewati)' if skipped else ''))
    print('\n'.join(lines))
    raise SystemExit

n = len(days_data)

# Per-week (ISO week) breakdown
lines.append('*Per Minggu:*')
weeks = {}
for s in days_data:
    wk = s['date'].isocalendar()[1]
    weeks.setdefault(wk, []).append(s)
for wk in sorted(weeks):
    ws = weeks[wk]
    wi = round(sum(x['cal_in'] for x in ws) / len(ws))
    wo = round(sum(x['cal_out'] for x in ws) / len(ws))
    wp = round(sum(x['protein'] for x in ws) / len(ws))
    wc = round(sum(x['carbs'] for x in ws) / len(ws))
    wf = round(sum(x['fat'] for x in ws) / len(ws))
    d0 = ws[0]['date'].strftime('%d %b')
    d1 = ws[-1]['date'].strftime('%d %b')
    lines.append(f'  {d0}–{d1}: avg +{wi} / -{wo} kcal | P{wp}/K{wc}/L{wf}g ({len(ws)} hari)')
lines.append('')

# Aggregates
total_in = sum(s['cal_in'] for s in days_data)
total_out = sum(s['cal_out'] for s in days_data)
avg_in = round(total_in / n)
avg_out = round(total_out / n)
avg_net = round((total_in - total_out) / n)
avg_protein = round(sum(s['protein'] for s in days_data) / n)
avg_carbs = round(sum(s['carbs'] for s in days_data) / n)
avg_fat = round(sum(s['fat'] for s in days_data) / n)
total_meals = sum(s['meals'] for s in days_data)
total_acts = sum(s['activities'] for s in days_data)

lines.append('*Ringkasan:*')
lines.append(f'  📅 Hari tercatat: *{n}/{days_in_month}*')
lines.append(f'  🔥 Rata-rata kalori masuk: *{avg_in} kcal/hari*')
lines.append(f'  💨 Rata-rata kalori keluar: *{avg_out} kcal/hari*')
lines.append(f'  📊 Net kalori rata-rata: *{avg_net} kcal/hari*')
lines.append(f'  🍱 Total makan: {total_meals}x | 🏋️ Total olahraga: {total_acts}x')

# Target comparison
target_cal = profile.get('daily_calorie_target', 0)
tdee = profile.get('tdee', 0)
if target_cal:
    diff = avg_in - target_cal
    emoji = '✅' if diff <= 50 else '⚠️'
    lines.append(f'  {emoji} Target harian: {target_cal} kcal (rata-rata {diff:+d} kcal)')
if tdee:
    # Estimasi defisit aktual vs TDEE (1 kg lemak ~ 7700 kkal)
    est_def = round(tdee + avg_out - avg_in)
    status = 'defisit' if est_def > 0 else 'surplus'
    emoji2 = '✅' if est_def > 0 else '⚠️'
    lines.append(f'  {emoji2} Estimasi {status} vs TDEE: {est_def:+d} kkal/hari (≈ {est_def * 7 / 7700:+.2f} kg/minggu)')
lines.append(f'  🥩 Protein: {avg_protein}g | 🍞 Karbo: {avg_carbs}g | 🧈 Lemak: {avg_fat}g')

# Weight trend + progress vs goal
weights = [s['weight'] for s in days_data if s['weight']]
diff = None
if len(weights) >= 2:
    w_start, w_end = weights[0], weights[-1]
    diff = w_end - w_start
    arrow = '📉' if diff < 0 else '📈' if diff > 0 else '➡️'
    lines.append('')
    lines.append('*Berat Badan:*')
    lines.append(f'  {arrow} {w_start} → {w_end} kg ({diff:+.1f} kg bulan ini)')
    if profile.get('target_kg') and profile.get('height_cm'):
        target = profile['target_kg']
        height = profile['height_cm']
        bmi = round(w_end / ((height / 100) ** 2), 1)
        left = w_end - target
        lines.append(f'  📏 BMI: {bmi} | 🎯 Target: {target} kg (sisa {left:+.1f} kg)')
elif len(weights) == 1:
    lines.append('')
    lines.append(f'⚖️ Berat tercatat: {weights[0]} kg (hanya 1x timbang)')

# Suggestions
lines.append('')
lines.append('*💡 Saran Bulan Depan:*')
suggestions = []

if diff is not None:
    if diff > 0.5:
        suggestions.append(f'Berat naik {diff:.1f} kg. Kencangkan defisit: kurangi porsi 10–15% & tambah olahraga.')
    elif diff < -2:
        suggestions.append(f'Turun {abs(diff):.1f} kg — pesat! Jangan terlalu ekstrem, jaga asupan protein biar otot aman.')
    elif diff < 0:
        suggestions.append(f'Turun {abs(diff):.1f} kg — progress sehat & stabil, pertahankan ritmenya.')
    else:
        suggestions.append('Berat stagnan. Variasikan olahraga atau audit ulang porsi makan.')

if tdee and avg_in > tdee:
    suggestions.append(f'Rata-rata kalori masuk ({avg_in}) di atas TDEE ({tdee}) — masih surplus, perlu dikurangi.')
elif target_cal and avg_in > target_cal + 200:
    suggestions.append(f'Kalori masih di atas target ({target_cal}). Ganti snack tinggi gula dengan buah/protein.')

if profile.get('target_kg'):
    # Use the profile's canonical protein target (set at init-profile); fall back to 1.6 g/kg target weight
    min_protein = profile.get('protein_target_g') or profile['target_kg'] * 1.6
    if avg_protein < min_protein:
        suggestions.append(f'Protein kurang ({avg_protein}g vs ~{min_protein:.0f}g). Tambah telur, ayam, ikan, atau protein shake.')

if total_acts == 0:
    suggestions.append('Sebulan tanpa olahraga tercatat! Mulai jalan kaki 30 menit/hari.')
elif total_acts < 12:
    suggestions.append(f'Olahraga {total_acts}x/bulan. Naikkan ke 3–5x/minggu (≥12–20/bulan).')

if n < days_in_month * 0.6:
    suggestions.append(f'Cuma {n}/{days_in_month} hari tercatat. Konsisten log makan & berat biar data akurat.')

if not suggestions:
    suggestions.append('Bulan ini solid! Pola makan & olahraga konsisten — lanjutkan. 💪')

for i, s in enumerate(suggestions, 1):
    lines.append(f'  {i}. {s}')

if skipped:
    lines.append('')
    lines.append(f'⚠️ {skipped} file harian rusak dilewati (tidak ikut dihitung).')

print('\n'.join(lines))
PYEOF
