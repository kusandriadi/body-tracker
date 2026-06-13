#!/bin/bash
# weekly-report.sh - Generate weekly body tracker report with suggestions
# Usage: weekly-report.sh [YYYY-MM-DD]
#   No arg  -> the PREVIOUS completed week (last Mon–Sun).
#   With arg-> the week (Mon–Sun) containing that date.
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:/home/kusa/bin:$PATH"

DATA_DIR="${DATA_DIR:-/home/kusa/data/openclaw/body-tracker}"
DATE="${1:-$(date -d '7 days ago' '+%Y-%m-%d')}"

DATA_DIR="$DATA_DIR" DATE="$DATE" python3 << 'PYEOF'
import json, os, datetime

data_dir = os.environ.get('DATA_DIR', '/home/kusa/data/openclaw/body-tracker')
date_str = os.environ.get('DATE', datetime.date.today().isoformat())

d = datetime.datetime.strptime(date_str, '%Y-%m-%d').date()
start = d - datetime.timedelta(days=d.weekday())
end = start + datetime.timedelta(days=6)

lines = [f'📊 *Laporan Mingguan Body Tracker*', f'*{start.strftime("%d %b")} - {end.strftime("%d %b %Y")}*', '']

# Load profile
pfile = os.path.join(data_dir, 'profile.json')
profile = {}
if os.path.exists(pfile):
    with open(pfile) as f:
        profile = json.load(f)

# Collect daily data
days_data = []
daily_summaries = []
skipped = 0
for i in range(7):
    day = (start + datetime.timedelta(days=i))
    fpath = os.path.join(data_dir, f'{day.isoformat()}.json')
    if os.path.exists(fpath):
        try:
            with open(fpath) as f:
                data = json.load(f)
        except (json.JSONDecodeError, ValueError):
            skipped += 1
            continue
        days_data.append(data)
        daily_summaries.append({
            'date': day.isoformat(),
            'day': day.strftime('%a'),
            'cal_in': data['daily_summary']['total_calories_in'],
            'cal_out': data['daily_summary']['total_calories_out'],
            'net': data['daily_summary']['net_calories'],
            'protein': data['daily_summary']['protein_g'],
            'carbs': data['daily_summary']['carbs_g'],
            'fat': data['daily_summary']['fat_g'],
            'meals': len(data.get('meals', [])),
            'activities': len(data.get('activities', [])),
            'weight': data.get('weight', {}).get('value'),
        })

if not days_data:
    lines.append('Tidak ada data minggu ini.' + (f' ({skipped} file rusak dilewati)' if skipped else ''))
    print('\n'.join(lines))
    exit()

# Per-day breakdown
lines.append('*Detail Harian:*')
for s in daily_summaries:
    w_str = f' | ⚖️{s["weight"]}kg' if s['weight'] else ''
    m_str = f' | P{round(s["protein"])}/K{round(s["carbs"])}/L{round(s["fat"])}g'
    lines.append(f'  {s["day"]} {s["date"][8:]}: +{s["cal_in"]} / -{s["cal_out"]} kcal (net: {s["net"]}){m_str}{w_str}')

lines.append('')

# Aggregates
total_in = sum(s['cal_in'] for s in daily_summaries)
total_out = sum(s['cal_out'] for s in daily_summaries)
avg_in = round(total_in / len(daily_summaries))
avg_out = round(total_out / len(daily_summaries))
avg_protein = round(sum(s['protein'] for s in daily_summaries) / len(daily_summaries), 0)
avg_carbs = round(sum(s['carbs'] for s in daily_summaries) / len(daily_summaries), 0)
avg_fat = round(sum(s['fat'] for s in daily_summaries) / len(daily_summaries), 0)

lines.append('*Ringkasan:*')
lines.append(f'  🔥 Rata-rata kalori masuk: *{avg_in} kcal/hari*')
lines.append(f'  💨 Rata-rata kalori keluar: *{avg_out} kcal/hari*')
lines.append(f'  📊 Net kalori rata-rata: *{round((total_in - total_out) / len(daily_summaries))} kcal/hari*')

# Target comparison
if profile:
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

# Weight trend
weights = [s['weight'] for s in daily_summaries if s['weight']]
if len(weights) >= 2:
    w_start = weights[0]
    w_end = weights[-1]
    diff = w_end - w_start
    arrow = '📉' if diff < 0 else '📈' if diff > 0 else '➡️'
    lines.append('')
    lines.append(f'*Berat Badan:*')
    lines.append(f'  {arrow} {w_start} → {w_end} kg ({diff:+.1f} kg)')
elif len(weights) == 1:
    lines.append('')
    lines.append(f'⚖️ Berat tercatat: {weights[0]} kg (hanya 1x timbang)')

# Suggestions
lines.append('')
lines.append('*💡 Saran:*')

suggestions = []

# Weight-based suggestions
if weights and len(weights) >= 2:
    if diff > 0:
        suggestions.append('Berat naik minggu ini. Coba kurangi porsi makan 10-15% atau tambah olahraga 15 menit/hari.')
    elif diff < -0.8:
        suggestions.append(f'Turun {abs(diff):.1f} kg — bagus! Tapi jangan terlalu ekstrem, pastikan tetap makan cukup.')
    elif diff < 0:
        suggestions.append(f'Turun {abs(diff):.1f} kg — progress stabil, pertahankan!')

# Calorie-based suggestions
if profile:
    tdee = profile.get('tdee', 0)
    target_cal = profile.get('daily_calorie_target', 0)
    if avg_in > tdee:
        suggestions.append(f'Rata-rata kalori masuk ({avg_in}) melebihi TDEE ({tdee}). Perlu dikurangi.')
    elif avg_in > target_cal + 200:
        suggestions.append(f'Kalori masih di atas target ({target_cal}). Coba ganti snack dengan buah/protein.')
    
    # Protein check
    # Use the profile's canonical protein target (set at init-profile); fall back to 1.6 g/kg target weight
    min_protein = profile.get('protein_target_g') or profile.get('target_kg', 70) * 1.6
    if avg_protein < min_protein:
        suggestions.append(f'Protein kurang ({avg_protein}g vs target {min_protein:.0f}g). Tambah telur, ayam, atau protein shake.')

# Activity-based suggestions
total_activities = sum(s['activities'] for s in daily_summaries)
if total_activities == 0:
    suggestions.append('Tidak ada olahraga minggu ini! Mulai dari jalan kaki 30 menit/hari.')
elif total_activities < 3:
    suggestions.append(f'Hanya {total_activities}x olahraga. Idealnya 3-5x per minggu.')

if not suggestions:
    suggestions.append('Minggu ini bagus! Pertahankan pola makan dan olahraga yang konsisten. 💪')

for i, s in enumerate(suggestions, 1):
    lines.append(f'  {i}. {s}')

if skipped:
    lines.append('')
    lines.append(f'⚠️ {skipped} file harian rusak dilewati (tidak ikut dihitung).')

print('\n'.join(lines))
PYEOF
