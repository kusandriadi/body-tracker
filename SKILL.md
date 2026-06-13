---
name: body-tracker
description: >
  Track body weight, calorie intake from food/drink photos, and exercise/activity from
  fitness app or smartwatch screenshots. Use when the user sends a photo of food/drinks
  (analyze calories & nutrition), a screenshot of a fitness app or smartwatch (extract
  activity data), a photo of a weighing scale or types their weight (log weight), asks
  for a daily/weekly/monthly recap of their tracking data, asks about nutrition or
  exercise progress, or asks to set up or update their body profile (height, weight, age,
  target weight). Also triggers on the /body-tracker and /weight commands.
---

# Body Tracker

Track weight, calorie intake (via food photos), and physical activity (via fitness screenshots).

> **🔑 Aturan Makro (WAJIB):** Setiap kali kamu menyebut atau menjawab angka **kalori** —
> apa pun bentuknya (catat makanan, jawab "berapa kalori X", "udah makan apa aja hari ini",
> rekap harian/mingguan/bulanan, perkiraan satu menu) — kamu **HARUS** sekalian sebut
> **protein, karbohidrat, dan lemak** (dalam gram). Kalori tanpa makro = jawaban belum lengkap.
> Format ringkas: `🔥 350 kcal | 🥩 P 10g · 🍞 K 45g · 🧈 L 15g`.

## Commands

Triggered via `/weight <subcommand>`. `add-food` / `add-activity` usually come
with an **image** but may be plain text; the optional `<text>` is the user's
note/caption.

| Command | What to do |
|---------|------------|
| `/weight add-food [text]` | Log a meal/drink. If an image is attached, analyze it with the `image` tool (`zai/glm-4.6v`) per **Step 2 (food)**, then `body-tracker.sh log-meal '<json>'`. If text-only (e.g. "nasi goreng + es teh"), estimate calories/macros yourself and log. Confirm with detected items + calories **+ protein/karbo/lemak (g)** + time (WIB). |
| `/weight add-activity [text]` | Log exercise. Image → analyze per **Step 2 (fitness)**; text-only (e.g. "lari 5km 30 menit") → estimate and log via `body-tracker.sh log-activity '<json>'`. Confirm type + calories burned + time. |
| `/weight undo [makan\|olahraga]` | Batalkan entri terakhir yang salah dicatat: `body-tracker.sh remove-last meal` atau `remove-last activity`. Tambah tanggal opsional (mis. salah catat kemarin): `remove-last meal 2026-06-12`. Konfirmasi apa yang dihapus. |
| `/weight weekly-report` | Run `bash scripts/weekly-report.sh` (no arg = **previous** completed week, Mon–Sun). Show the full report incl. suggestions. Add "minggu ini"? pass today's date: `weekly-report.sh $(date +%F)`. |
| `/weight monthly-report` | Run `bash scripts/monthly-report.sh` (no arg = **previous** completed month). Show the full report incl. suggestions. "Bulan ini"? pass current month: `monthly-report.sh $(date +%Y-%m)`. |
| `/weight help` | Explain the commands (see **Help text** below). |

Bare `/weight` or `/body-tracker` with a photo and no subcommand: infer intent —
food/drink → add-food, fitness/smartwatch → add-activity, scale/number → log-weight.

### Help text

When the user runs `/weight help`, explain in Bahasa Indonesia:
- `/weight add-food [teks]` — catat makanan/minuman (kirim foto, atau ketik teksnya).
- `/weight add-activity [teks]` — catat olahraga/aktivitas (foto smartwatch/app atau teks).
- `/weight undo` — batalkan catatan makan/olahraga terakhir kalau salah deteksi.
- `/weight weekly-report` — laporan minggu lalu (Sen–Min) lengkap + saran.
- `/weight monthly-report` — laporan bulan lalu (tgl 1–akhir) lengkap + saran.
- Bisa juga langsung kirim foto timbangan/makanan/olahraga tanpa command — otomatis terdeteksi.

## Model Routing

**Image analysis (vision):** Always use `zai/glm-4.6v` via the `image` tool.

**Reasoning/processing:** After getting image results, the agent reasons with the default model (`zai/glm-5.1`). This happens automatically.

Flow:
```
User sends photo → image tool (glm-4.6v) → agent reasons & logs (glm-5.1) → reply to user
```

## Data Location

```
Daily logs:   ~/.body-tracker/YYYY-MM-DD.json
User profile: ~/.body-tracker/profile.json
```

## Ilmu Defisit Kalori

Skill ini memakai metode yang paling banyak dipakai & paling tepercaya (CDC, Mayo Clinic,
Academy of Nutrition & Dietetics). Gunakan ilmu ini saat menjawab pertanyaan user soal
diet, target, atau progres — jangan asal angka.

**Konsep inti:** turun berat = **defisit kalori** → kalori masuk < kalori keluar (TDEE).
Tidak ada makanan "ajaib"; yang menentukan adalah neraca kalori total.

**Rumus yang dipakai skill (otomatis di `init-profile`):**
1. **BMR — Mifflin-St Jeor** (persamaan paling akurat untuk orang umum, direkomendasikan ADA):
   - Pria: `10·berat(kg) + 6.25·tinggi(cm) − 5·umur + 5`
   - Wanita: `10·berat(kg) + 6.25·tinggi(cm) − 5·umur − 161`
2. **TDEE = BMR × faktor aktivitas** (1.2 sedentary → 1.9 very_active). Ini total kalori
   yang dibakar per hari.
3. **Target asupan = TDEE − defisit harian.**

**Laju aman (acuan emas):**
- `1 kg lemak ≈ 7700 kkal`. Jadi defisit harian → laju turun berat:
  - **mild** 250/hari → ~0.23 kg/minggu (paling gampang dijaga)
  - **moderate** 500/hari → ~0.45 kg/minggu (**default, paling direkomendasikan** CDC/Mayo)
  - **aggressive** 750/hari → ~0.68 kg/minggu (cepat, butuh disiplin)
- Rekomendasi umum: **0.5–1 kg/minggu**. Jangan lebih dari **~1% berat badan/minggu**.

**Batas aman (jangan dilanggar):**
- Asupan jangan di bawah **1200 kkal (wanita) / 1500 kkal (pria)** — skill otomatis menjaga
  lantai ini meski defisit penuh melewatinya.
- Hindari makan di bawah **BMR** dalam jangka panjang (metabolisme melambat, kehilangan otot).
- Defisit terlalu agresif → otot hilang, lemas, gampang yo-yo. Konsistensi > ekstrem.

**Protein saat defisit:** target **1.6–2.2 g/kg berat badan** (skill pakai ~1.8 g/kg) untuk
**menjaga massa otot** — ini bagian terpenting biar yang turun lemak, bukan otot.

**Neraca energi harian (rekap `daily`):** ditampilkan `TDEE + olahraga − asupan`. Positif =
defisit (menuju turun), negatif = surplus. Catatan: TDEE sudah memuat aktivitas umum sesuai
`activity_level`, jadi kalau user menyetel level tinggi **dan** rajin mencatat olahraga,
angka olahraga bisa sedikit dobel-hitung — sampaikan ini sebagai estimasi, bukan angka mutlak.

**Cara menjawab user:** kalau user tanya "kenapa belum turun?", "boleh makan ini?", atau
minta saran — rujuk angka di profilnya (TDEE, target, defisit aktual) dan prinsip di atas.
Bandingkan rata-rata asupan vs target, cek protein, dan ingat batas laju aman.

## How to Use

### Step 1: Load profile

Always read profile first: `cat ~/.body-tracker/profile.json`

If profile doesn't exist or user wants to update, run:
```bash
bash scripts/body-tracker.sh init-profile <height_cm> <weight_kg> <age> <target_kg> [gender] [activity_level] [deficit_rate]
```
Activity levels: `sedentary` | `light` | `moderate` | `active` | `very_active`
Deficit rate: `mild` (250/hari) | `moderate` (500/hari, **default**) | `aggressive` (750/hari) — lihat **Ilmu Defisit Kalori**.

The profile output reports BMR, TDEE, daily calorie target, protein target, weekly
loss estimate, and weeks-to-goal. Relay these to the user and explain the deficit briefly.

### Step 2: Process user input

**Food/drink photo** → Use the `image` tool with `model: zai/glm-4.6v`:

```
Prompt: "Analyze this food/drink photo. Estimate: 1) Food name, 2) Calories (kcal), 
3) Protein (g), 4) Carbs (g), 5) Fat (g), 6) Portion size. Be specific with Indonesian 
food names. Give realistic calorie estimates for Indonesian portions. Format as JSON array."
```

Then log with:
```bash
bash scripts/body-tracker.sh log-meal '<JSON>'
# JSON: {"type":"breakfast|lunch|dinner|snack","time":"09:20","items":[{"name":"...","calories":350,"protein":10,"carbs":45,"fat":15,"portion":"1 piring","estimated":true}]}
```
**Important:** Always include `"time":"HH:MM"` (current time in WIB) in every log-meal and log-activity JSON.

**Fitness/smartwatch screenshot** → Use the `image` tool with `model: zai/glm-4.6v`:

```
Prompt: "Extract fitness data from this screenshot. Find: 1) Activity type (running, walking, 
cycling, gym, swimming, other), 2) Duration in minutes, 3) Calories burned, 4) Distance in km 
(if applicable), 5) Any other metrics (heart rate, steps, pace). Format as JSON."
```

Then log with:
```bash
bash scripts/body-tracker.sh log-activity '<JSON>'
# JSON: {"type":"running","time":"06:30","duration_min":30,"calories_burned":250,"distance_km":5.0,"notes":"Morning jog"}
```
**Important:** Always include `"time":"HH:MM"` (current time in WIB) in every log-meal and log-activity JSON.

**Weight input** (text like "75.5" or "berat 75.5" or photo of scale):

```bash
bash scripts/body-tracker.sh log-weight <weight_kg>
```
Timestamp is recorded automatically. When confirming to user, always show the time (e.g. "⚖️ Berat: 88.3 kg (09:20 WIB)").

For scale photos, use `image` tool with `model: zai/glm-4.6v`:
```
Prompt: "Read the weight displayed on this scale. Return only the number in kg."
```

### Step 3: Recaps

```bash
bash scripts/body-tracker.sh daily [YYYY-MM-DD]       # Today's recap
bash scripts/body-tracker.sh weekly [YYYY-MM-DD]       # Weekly summary
bash scripts/body-tracker.sh monthly [YYYY-MM-DD]      # Monthly summary
bash scripts/body-tracker.sh progress                   # Progress vs target
```

### Weekly / Monthly Report

```bash
bash scripts/weekly-report.sh  [YYYY-MM-DD]   # no arg = previous completed week (Mon–Sun)
bash scripts/monthly-report.sh [YYYY-MM]       # no arg = previous completed month
```

Both generate a full report with calorie trends, macro averages, weight change,
progress vs target, and personalized suggestions. The weekly report is sent
automatically every Monday 08:00 WIB via cron (covers the week that just ended).

> Prefer these over `body-tracker.sh weekly|monthly` — those are quick
> current-period summaries without suggestions.

## Daily Log Format

Each day is stored in `YYYY-MM-DD.json`:
```json
{
  "date": "2026-06-06",
  "weight": { "value": null, "unit": "kg", "ts": null },
  "meals": [],
  "activities": [],
  "daily_summary": {
    "total_calories_in": 0,
    "total_calories_out": 0,
    "net_calories": 0,
    "protein_g": 0,
    "carbs_g": 0,
    "fat_g": 0
  }
}
```

## Response Style

- Bahasa Indonesia, santai
- **Kalori selalu ditemani makro.** Lihat **Aturan Makro** di atas: tiap angka kalori
  yang kamu sebut wajib disertai protein, karbohidrat, dan lemak (gram). Berlaku juga
  untuk pertanyaan lepas seperti "berapa kalori nasi padang?" atau "hari ini udah makan
  apa aja?" — jawab kalorinya **dan** rincian makronya.
- When logging food: confirm what was detected + calorie estimate + **protein/karbo/lemak (g)** + **time**
- When logging activity: confirm type + calories burned + **time**
- When logging weight: confirm + **time**
- For recaps: show concise summary with emoji, include time for each entry
- For weekly reports: include actionable suggestions based on their target
- Always include WIB time in all confirmations (e.g. " dicatat pukul 09:20 WIB")
