#!/bin/bash
# body-tracker.sh - Manage body tracking data
# Usage:
#   body-tracker.sh init-profile <height_cm> <weight_kg> <age> <target_kg> [gender] [activity_level] [deficit_rate]
#   body-tracker.sh log-weight <weight_kg> [YYYY-MM-DD]
#   body-tracker.sh log-meal '<json>' [YYYY-MM-DD]
#   body-tracker.sh log-activity '<json>' [YYYY-MM-DD]
#   body-tracker.sh remove-last <meal|activity> [YYYY-MM-DD]
#   body-tracker.sh daily [YYYY-MM-DD]
#   body-tracker.sh weekly [YYYY-MM-DD]
#   body-tracker.sh monthly [YYYY-MM-DD]
#   body-tracker.sh progress
#
# Notes:
#   - All values that come from the agent (food JSON, notes, names) are passed to
#     Python via ENVIRONMENT VARIABLES (never string-interpolated), so apostrophes
#     and special characters are safe.
#   - All writes are atomic (temp file + os.replace), so concurrent logs can't
#     corrupt a daily file.
#   - Time is pinned to WIB (Asia/Jakarta) regardless of the server timezone.
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:$HOME/bin:$PATH"
export TZ="Asia/Jakarta"

DATA_DIR="${DATA_DIR:-$HOME/data/openclaw/body-tracker}"
mkdir -p "$DATA_DIR"

CMD="${1:-}"
shift || true

now_iso=$(date -Iseconds)
today=$(date '+%Y-%m-%d')

get_daily_file() {
    local d="${1:-$today}"
    echo "$DATA_DIR/${d}.json"
}

# ensure_daily <file> <date> — create an empty daily file stamped with the TARGET date
ensure_daily() {
    local f="$1"
    local d="${2:-$today}"
    if [ ! -f "$f" ]; then
        FILE="$f" DAY="$d" python3 << 'PYEOF'
import json, os
f = os.environ['FILE']
obj = {
    'date': os.environ['DAY'],
    'weight': {'value': None, 'unit': 'kg', 'ts': None},
    'meals': [],
    'activities': [],
    'daily_summary': {
        'total_calories_in': 0,
        'total_calories_out': 0,
        'net_calories': 0,
        'protein_g': 0,
        'carbs_g': 0,
        'fat_g': 0,
    },
}
tmp = f + '.tmp'
with open(tmp, 'w') as fh:
    json.dump(obj, fh, indent=2, ensure_ascii=False)
os.replace(tmp, f)
PYEOF
    fi
}

recalc_summary() {
    FILE="$1" python3 << 'PYEOF'
import json, os
f = os.environ['FILE']
with open(f) as fh:
    data = json.load(fh)

cal_in = sum(m.get('total_calories', 0) for m in data.get('meals', []))
cal_out = sum(a.get('calories_burned', 0) for a in data.get('activities', []))
protein = sum(it.get('protein', 0) for m in data.get('meals', []) for it in m.get('items', []))
carbs = sum(it.get('carbs', 0) for m in data.get('meals', []) for it in m.get('items', []))
fat = sum(it.get('fat', 0) for m in data.get('meals', []) for it in m.get('items', []))

data['daily_summary'] = {
    'total_calories_in': cal_in,
    'total_calories_out': cal_out,
    'net_calories': cal_in - cal_out,
    'protein_g': round(protein, 1),
    'carbs_g': round(carbs, 1),
    'fat_g': round(fat, 1),
}

tmp = f + '.tmp'
with open(tmp, 'w') as fh:
    json.dump(data, fh, indent=2, ensure_ascii=False)
os.replace(tmp, f)
PYEOF
}

case "$CMD" in
    init-profile)
        H="${1:?height_cm}" W="${2:?weight_kg}" A="${3:?age}" T="${4:?target_kg}"
        GENDER="${5:-male}" ACTIVITY="${6:-moderate}" RATE="${7:-moderate}"
        H="$H" W="$W" A="$A" T="$T" GENDER="$GENDER" ACTIVITY="$ACTIVITY" RATE="$RATE" \
        NOW_ISO="$now_iso" PROFILE="$DATA_DIR/profile.json" python3 << 'PYEOF'
import json, os
H = int(float(os.environ['H']))
A = int(float(os.environ['A']))
W = float(os.environ['W'])
T = float(os.environ['T'])
G, ACT, RATE = os.environ['GENDER'], os.environ['ACTIVITY'], os.environ['RATE']
ppath = os.environ['PROFILE']
now = os.environ['NOW_ISO']

# Preserve original created_at on update
created = now
if os.path.exists(ppath):
    try:
        with open(ppath) as fh:
            created = json.load(fh).get('created_at', now)
    except Exception:
        pass

profile = {
    'height_cm': H, 'weight_kg': W, 'age': A, 'target_kg': T,
    'gender': G, 'activity_level': ACT, 'deficit_rate': RATE,
    'created_at': created, 'updated_at': now,
}

# --- BMR: Mifflin-St Jeor (paling akurat & direkomendasikan Academy of Nutrition & Dietetics) ---
if G == 'male':
    bmr = 10 * W + 6.25 * H - 5 * A + 5
else:
    bmr = 10 * W + 6.25 * H - 5 * A - 161

# --- TDEE = BMR x faktor aktivitas ---
multipliers = {'sedentary': 1.2, 'light': 1.375, 'moderate': 1.55, 'active': 1.725, 'very_active': 1.9}
tdee = bmr * multipliers.get(ACT, 1.55)

# --- Defisit kalori (1 kg lemak ~ 7700 kkal) ---
deficit_map = {'mild': 250, 'moderate': 500, 'aggressive': 750}
deficit = deficit_map.get(RATE, 500)
floor = 1500 if G == 'male' else 1200  # batas aman asupan minimum

losing = T < W
warnings = []
if losing:
    raw_target = tdee - deficit
    target_intake = max(round(raw_target), floor)
    actual_deficit = round(tdee - target_intake)
    if raw_target < floor:
        warnings.append(f'Defisit penuh {deficit}/hari akan menjatuhkan asupan di bawah batas aman {floor} kkal — target dijaga di {floor} kkal.')
    if target_intake < bmr:
        warnings.append(f'Target asupan ({target_intake}) di bawah BMR ({round(bmr)}). Aman sesekali, tapi jangan berkepanjangan.')
else:
    target_intake = round(tdee)  # target >= berat sekarang -> maintenance
    actual_deficit = 0
    warnings.append('Target >= berat sekarang, jadi diset ke MAINTENANCE (tanpa defisit).')

weekly_loss = round(actual_deficit * 7 / 7700, 2)
to_lose = round(W - T, 1)
est_weeks = round(to_lose / weekly_loss, 1) if (weekly_loss > 0 and to_lose > 0) else None
if weekly_loss > W * 0.01:
    warnings.append(f'Laju {weekly_loss} kg/minggu melebihi ~1% berat badan/minggu — risiko kehilangan otot.')

protein_target = round(W * 1.8)  # 1.6-2.2 g/kg untuk jaga otot saat defisit

profile['bmr'] = round(bmr)
profile['tdee'] = round(tdee)
profile['daily_calorie_target'] = target_intake
profile['daily_deficit'] = actual_deficit
profile['weekly_loss_kg_est'] = weekly_loss
profile['est_weeks_to_target'] = est_weeks
profile['protein_target_g'] = protein_target

tmp = ppath + '.tmp'
with open(tmp, 'w') as fh:
    json.dump(profile, fh, indent=2, ensure_ascii=False)
os.replace(tmp, ppath)

print('✅ Profil tersimpan!')
print(f'Tinggi: {H} cm | Berat: {W} kg | Umur: {A} | Target: {T} kg | Kelamin: {G}')
print(f'🔥 BMR: {round(bmr)} kkal (kalori basal istirahat)')
print(f'⚡ TDEE: {round(tdee)} kkal (total kalori terbakar/hari, aktivitas: {ACT})')
print(f'🎯 Target asupan: {target_intake} kkal/hari (defisit {actual_deficit} kkal, mode: {RATE})')
print(f'🥩 Target protein: {protein_target} g/hari (jaga otot saat defisit)')
if est_weeks:
    print(f'📉 Estimasi: ~{weekly_loss} kg/minggu -> turun {to_lose} kg dalam ~{est_weeks} minggu')
if warnings:
    print('⚠️ Catatan:')
    for w in warnings:
        print(f'   - {w}')
PYEOF
        ;;

    log-weight)
        WEIGHT="${1:?weight_kg}"
        DATE="${2:-$today}"
        FILE=$(get_daily_file "$DATE")
        ensure_daily "$FILE" "$DATE"
        FILE="$FILE" WEIGHT="$WEIGHT" NOW_ISO="$now_iso" python3 << 'PYEOF'
import json, os
f = os.environ['FILE']
with open(f) as fh:
    data = json.load(fh)
data['weight'] = {'value': float(os.environ['WEIGHT']), 'unit': 'kg', 'ts': os.environ['NOW_ISO']}
tmp = f + '.tmp'
with open(tmp, 'w') as fh:
    json.dump(data, fh, indent=2, ensure_ascii=False)
os.replace(tmp, f)
print(f"⚖️ Berat badan dicatat: {data['weight']['value']} kg")
PYEOF
        ;;

    log-meal)
        MEAL_JSON="${1:?meal json}"
        DATE="${2:-$today}"
        FILE=$(get_daily_file "$DATE")
        ensure_daily "$FILE" "$DATE"
        FILE="$FILE" MEAL_JSON="$MEAL_JSON" NOW_ISO="$now_iso" python3 << 'PYEOF'
import json, os
meal = json.loads(os.environ['MEAL_JSON'])
meal['ts'] = os.environ['NOW_ISO']
meal.setdefault('source', 'manual')
meal.setdefault('notes', '')
items = meal.get('items', [])
total = sum(it.get('calories', 0) for it in items)
protein = round(sum(it.get('protein', 0) for it in items), 1)
carbs = round(sum(it.get('carbs', 0) for it in items), 1)
fat = round(sum(it.get('fat', 0) for it in items), 1)
meal['total_calories'] = total

f = os.environ['FILE']
with open(f) as fh:
    data = json.load(fh)
data['meals'].append(meal)
tmp = f + '.tmp'
with open(tmp, 'w') as fh:
    json.dump(data, fh, indent=2, ensure_ascii=False)
os.replace(tmp, f)
print(json.dumps({'logged': meal, 'total_calories': total, 'protein_g': protein, 'carbs_g': carbs, 'fat_g': fat}, ensure_ascii=False))
PYEOF
        recalc_summary "$FILE"
        ;;

    log-activity)
        ACT_JSON="${1:?activity json}"
        DATE="${2:-$today}"
        FILE=$(get_daily_file "$DATE")
        ensure_daily "$FILE" "$DATE"
        FILE="$FILE" ACT_JSON="$ACT_JSON" NOW_ISO="$now_iso" python3 << 'PYEOF'
import json, os
act = json.loads(os.environ['ACT_JSON'])
act['ts'] = os.environ['NOW_ISO']
act.setdefault('source', 'manual')
act.setdefault('notes', '')

f = os.environ['FILE']
with open(f) as fh:
    data = json.load(fh)
data['activities'].append(act)
tmp = f + '.tmp'
with open(tmp, 'w') as fh:
    json.dump(data, fh, indent=2, ensure_ascii=False)
os.replace(tmp, f)
print(json.dumps({'logged': act}, ensure_ascii=False))
PYEOF
        recalc_summary "$FILE"
        ;;

    remove-last)
        KIND="${1:-}"
        DATE="${2:-$today}"
        FILE=$(get_daily_file "$DATE")
        if [ ! -f "$FILE" ]; then
            echo "📋 Tidak ada data untuk $DATE"
            exit 0
        fi
        FILE="$FILE" KIND="$KIND" python3 << 'PYEOF'
import json, os
f = os.environ['FILE']
kind = os.environ['KIND'].lower()
if kind in ('meal', 'makan', 'food', 'makanan'):
    key, label = 'meals', 'makanan'
elif kind in ('activity', 'aktivitas', 'olahraga', 'exercise'):
    key, label = 'activities', 'aktivitas'
else:
    print('❌ Pakai: remove-last meal|activity [tanggal]')
    raise SystemExit(0)

with open(f) as fh:
    data = json.load(fh)
arr = data.get(key, [])
if not arr:
    print(f'📋 Tidak ada {label} untuk dihapus di tanggal ini.')
    raise SystemExit(0)

removed = arr.pop()
tmp = f + '.tmp'
with open(tmp, 'w') as fh:
    json.dump(data, fh, indent=2, ensure_ascii=False)
os.replace(tmp, f)

if key == 'meals':
    nm = ', '.join(it.get('name', '?') for it in removed.get('items', [])) or '?'
    print(f"🗑️ Dihapus: {removed.get('type', 'makan')} — {nm} ({removed.get('total_calories', 0)} kkal)")
else:
    print(f"🗑️ Dihapus: {removed.get('type', 'aktivitas')} ({removed.get('calories_burned', 0)} kkal)")
PYEOF
        recalc_summary "$FILE"
        ;;

    daily)
        DATE="${1:-$today}"
        FILE=$(get_daily_file "$DATE")
        if [ ! -f "$FILE" ]; then
            echo "📋 Tidak ada data untuk $DATE"
            exit 0
        fi
        FILE="$FILE" DATE="$DATE" DATA_DIR="$DATA_DIR" python3 << 'PYEOF'
import json, os
with open(os.environ['FILE']) as f:
    data = json.load(f)
date = os.environ['DATE']

s = data.get('daily_summary', {})
w = data.get('weight', {})
lines = [f'📋 Rekap Harian: {date}', '']

if w.get('value'):
    lines.append(f"⚖️ Berat: {w['value']} kg")
else:
    lines.append('⚖️ Berat: belum dicatat')

meals = data.get('meals', [])
if meals:
    lines.append(f"🍽️ Makan: {len(meals)}x | {s.get('total_calories_in', 0)} kcal")
    for m in meals:
        items_str = ', '.join(it['name'] for it in m.get('items', []))
        t = m.get('time', m.get('ts', '?')[11:16] if m.get('ts') else '?')
        mp = round(sum(it.get('protein', 0) for it in m.get('items', [])), 1)
        mc = round(sum(it.get('carbs', 0) for it in m.get('items', [])), 1)
        mf = round(sum(it.get('fat', 0) for it in m.get('items', [])), 1)
        lines.append(f"   [{t}] {m.get('type', '?')}: {items_str} ({m.get('total_calories', 0)} kcal | P{mp}g K{mc}g L{mf}g)")
else:
    lines.append('🍽️ Makan: belum ada data')

acts = data.get('activities', [])
if acts:
    lines.append(f"🏃 Aktivitas: {len(acts)}x | -{s.get('total_calories_out', 0)} kcal")
    for a in acts:
        t = a.get('time', a.get('ts', '?')[11:16] if a.get('ts') else '?')
        extra = f", {a['distance_km']} km" if a.get('distance_km') else ''
        lines.append(f"   [{t}] {a.get('type', '?')}: {a.get('duration_min', '?')} min, -{a.get('calories_burned', 0)} kcal{extra}")
else:
    lines.append('🏃 Aktivitas: belum ada data')

lines.append('')
lines.append(f"🔥 Kalori masuk: {s.get('total_calories_in', 0)} kcal")
lines.append(f"💨 Kalori keluar: {s.get('total_calories_out', 0)} kcal")
lines.append(f"📊 Net kalori: {s.get('net_calories', 0)} kcal")
lines.append(f"🥩 Protein: {s.get('protein_g', 0)}g | 🍞 Karbo: {s.get('carbs_g', 0)}g | 🧈 Lemak: {s.get('fat_g', 0)}g")

pfile = os.path.join(os.environ['DATA_DIR'], 'profile.json')
if os.path.exists(pfile):
    with open(pfile) as f:
        p = json.load(f)
    cal_in = s.get('total_calories_in', 0)
    cal_out = s.get('total_calories_out', 0)
    target = p.get('daily_calorie_target', 0)
    diff = cal_in - target
    emoji = '✅' if diff <= 0 else '⚠️'
    deficit = p.get('daily_deficit', 0)
    def_str = f" — target ini sudah defisit {deficit} kkal dari TDEE {p.get('tdee', 0)}" if deficit else ''
    lines.append(f"{emoji} Target kalori: {target} kcal (selisih: {'+' if diff > 0 else ''}{diff} kcal){def_str}")

    pt = p.get('protein_target_g')
    if pt:
        pnow = s.get('protein_g', 0)
        pemoji = '✅' if pnow >= pt else '⚠️'
        lines.append(f"{pemoji} Target protein: {pt} g (baru {pnow}g) — penting biar otot aman saat defisit")

    tdee = p.get('tdee')
    if tdee:
        bal = int(round(tdee + cal_out - cal_in))
        bemoji = '✅' if bal > 0 else '⚠️'
        status = 'defisit' if bal > 0 else 'surplus'
        lines.append(f"{bemoji} Estimasi neraca energi hari ini: {bal:+d} kkal ({status})")
        lines.append(f"   = TDEE {tdee} + olahraga {cal_out} − asupan {cal_in}")

print('\n'.join(lines))
PYEOF
        ;;

    weekly)
        DATE="${1:-$today}"
        DATE="$DATE" DATA_DIR="$DATA_DIR" python3 << 'PYEOF'
import json, os, datetime
data_dir = os.environ['DATA_DIR']
d = datetime.datetime.strptime(os.environ['DATE'], '%Y-%m-%d').date()
start = d - datetime.timedelta(days=d.weekday())

lines = ['📊 Rekap Mingguan', f"{start.strftime('%d %b')} - {(start + datetime.timedelta(days=6)).strftime('%d %b %Y')}", '']

days_data = []
for i in range(7):
    day = start + datetime.timedelta(days=i)
    fpath = os.path.join(data_dir, f'{day.isoformat()}.json')
    if os.path.exists(fpath):
        with open(fpath) as f:
            days_data.append(json.load(f))

if not days_data:
    lines.append('Tidak ada data minggu ini.')
    print('\n'.join(lines))
    raise SystemExit(0)

n = len(days_data)
total_in = sum(x['daily_summary']['total_calories_in'] for x in days_data)
total_out = sum(x['daily_summary']['total_calories_out'] for x in days_data)
weights = [x['weight']['value'] for x in days_data if x.get('weight', {}).get('value')]

avg_in = round(total_in / n)
avg_out = round(total_out / n)
avg_protein = round(sum(x['daily_summary'].get('protein_g', 0) for x in days_data) / n, 1)
avg_carbs = round(sum(x['daily_summary'].get('carbs_g', 0) for x in days_data) / n, 1)
avg_fat = round(sum(x['daily_summary'].get('fat_g', 0) for x in days_data) / n, 1)

lines.append(f'🍽️ Rata-rata kalori masuk: {avg_in} kcal/hari')
lines.append(f'🏃 Rata-rata kalori keluar: {avg_out} kcal/hari')
lines.append(f'🔥 Total net kalori: {total_in - total_out} kcal ({round((total_in - total_out) / n)}/hari)')
lines.append(f'🥩 Rata-rata makro/hari: Protein {avg_protein}g | 🍞 Karbo {avg_carbs}g | 🧈 Lemak {avg_fat}g')

if weights:
    lines.append(f'⚖️ Berat: {weights[0]} → {weights[-1]} kg')
    if len(weights) > 1:
        diff = weights[-1] - weights[0]
        arrow = '📉' if diff < 0 else '📈' if diff > 0 else '➡️'
        lines.append(f'   {arrow} Perubahan: {diff:+.1f} kg')

lines.append(f'📅 Hari tercatat: {n}/7')
print('\n'.join(lines))
PYEOF
        ;;

    monthly)
        DATE="${1:-$today}"
        DATE="$DATE" DATA_DIR="$DATA_DIR" python3 << 'PYEOF'
import json, os, datetime
data_dir = os.environ['DATA_DIR']
month_key = os.environ['DATE'][:7]
year, mon = int(month_key[:4]), int(month_key[5:7])
if mon == 12:
    days_in_month = 31
else:
    days_in_month = (datetime.date(year, mon + 1, 1) - datetime.date(year, mon, 1)).days

lines = [f'📊 Rekap Bulanan: {month_key}', '']

days_data = []
for day in range(1, days_in_month + 1):
    fpath = os.path.join(data_dir, f'{month_key}-{day:02d}.json')
    if os.path.exists(fpath):
        with open(fpath) as f:
            days_data.append(json.load(f))

if not days_data:
    lines.append('Tidak ada data bulan ini.')
    print('\n'.join(lines))
    raise SystemExit(0)

n = len(days_data)
total_in = sum(x['daily_summary']['total_calories_in'] for x in days_data)
total_out = sum(x['daily_summary']['total_calories_out'] for x in days_data)
weights = [x['weight']['value'] for x in days_data if x.get('weight', {}).get('value')]
total_meals = sum(len(x.get('meals', [])) for x in days_data)
total_acts = sum(len(x.get('activities', [])) for x in days_data)

avg_in = round(total_in / n)
avg_out = round(total_out / n)
avg_protein = round(sum(x['daily_summary'].get('protein_g', 0) for x in days_data) / n, 1)
avg_carbs = round(sum(x['daily_summary'].get('carbs_g', 0) for x in days_data) / n, 1)
avg_fat = round(sum(x['daily_summary'].get('fat_g', 0) for x in days_data) / n, 1)

lines.append(f'📅 Hari tercatat: {n}/{days_in_month}')
lines.append(f'🍽️ Rata-rata kalori masuk: {avg_in} kcal/hari')
lines.append(f'🏃 Rata-rata kalori keluar: {avg_out} kcal/hari')
lines.append(f'🔥 Total net kalori: {total_in - total_out} kcal')
lines.append(f'🥩 Rata-rata makro/hari: Protein {avg_protein}g | 🍞 Karbo {avg_carbs}g | 🧈 Lemak {avg_fat}g')
lines.append(f'🍱 Total makan tercatat: {total_meals}x')
lines.append(f'🏋️ Total aktivitas: {total_acts}x')

if weights:
    lines.append(f'⚖️ Berat: {weights[0]} → {weights[-1]} kg')
    diff = weights[-1] - weights[0]
    arrow = '📉' if diff < 0 else '📈' if diff > 0 else '➡️'
    lines.append(f'   {arrow} Perubahan: {diff:+.1f} kg')

print('\n'.join(lines))
PYEOF
        ;;

    progress)
        DATA_DIR="$DATA_DIR" python3 << 'PYEOF'
import json, os, glob
data_dir = os.environ['DATA_DIR']
pfile = os.path.join(data_dir, 'profile.json')
if not os.path.exists(pfile):
    print('❌ Profile belum dibuat. Jalankan: body-tracker.sh init-profile')
    raise SystemExit(0)

with open(pfile) as f:
    p = json.load(f)

start_w = p['weight_kg']
target = p['target_kg']
height = p['height_cm']

files = sorted(f for f in glob.glob(os.path.join(data_dir, '*.json')) if not f.endswith('profile.json'))
latest_w = None
latest_date = None
for f in reversed(files):
    with open(f) as fh:
        d = json.load(fh)
    if d.get('weight', {}).get('value'):
        latest_w = d['weight']['value']
        latest_date = d['date']
        break

current = latest_w or start_w
losing = start_w >= target
# Sisa berat menuju target (positif selama belum sampai); arah loss vs gain
to_go = (current - target) if losing else (target - current)
reached = to_go <= 0
progress_pct = round((start_w - current) / (start_w - target) * 100) if start_w != target else 100
progress_pct = max(0, min(100, progress_pct))
bmi = round(current / ((height / 100) ** 2), 1)

lines = ['📊 Progress Menuju Target', '']
lines.append(f'🎯 Target: {start_w} → {target} kg')
lines.append(f'⚖️ Berat sekarang: {current} kg' + (f' (terakhir: {latest_date})' if latest_w else ' (dari profile)'))
lines.append(f'📏 BMI: {bmi}')
lines.append(f"{'📉 Sudah turun' if losing else '📈 Sudah naik'}: {abs(start_w - current):.1f} kg")
lines.append(f'📋 Sisa: {max(0.0, to_go):.1f} kg')
lines.append(f'📊 Progress: {progress_pct}%')

if reached:
    lines.append('')
    lines.append('🎉 Target tercapai!')

print('\n'.join(lines))
PYEOF
        ;;

    *)
        echo "Usage: body-tracker.sh <command> [args]"
        echo "Commands: init-profile, log-weight, log-meal, log-activity, remove-last, daily, weekly, monthly, progress"
        ;;
esac
