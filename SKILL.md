---
name: "body-tracker"
description: "Track body metrics and nutrition; supports /weight plus /wpd, /wpw, /wpm progress commands."
---

# Body Tracker

Track berat badan, kalori, makro, dan aktivitas.

## Aturan Wajib

Setiap kali menyebut angka kalori, wajib ikut menyebut makro:
- `🔥 kcal`
- `🥩 protein (g)`
- `🍞 karbo (g)`
- `🧈 lemak (g)`

Format wajib:
- `🔥 350 kcal`
- `🥩 Protein 10 g`
- `🍞 Karbo 45 g`
- `🧈 Lemak 15 g`

Jangan tulis makro side-by-side atau format ringkas horizontal seperti:
- `🔥 350 kcal | 🥩 P 10g · 🍞 K 45g · 🧈 L 15g`

Sebelum kirim jawaban, cek:
- kalau ada angka kalori, makro harus ikut muncul di jawaban yang sama,
- setiap metrik harus ada di baris terpisah,
- jangan pakai format makro nyamping.

## Transparansi Estimasi

Kalau ada estimasi, jangan cuma bilang `estimasi`.

Wajib jelaskan:
- bagian mana yang user timbang/langsung kasih,
- bagian mana yang kamu asumsikan,
- estimasi gram/porsi yang dipakai untuk hitung.

Kalau berat masih termasuk bagian tak termakan atau bagian yang mengubah makro secara besar, jelaskan breakdown-nya.

Untuk ayam/ikan/daging bertulang atau berkulit, sebisa mungkin sebut:
- berat input user,
- estimasi tulang,
- estimasi kulit bila relevan,
- estimasi porsi termakan yang dipakai untuk hitung.

Contoh:
- `Catatan: ayam 294 g tadi aku estimasikan dari berat kotor. Asumsiku sekitar 55 g tulang, 34 g kulit, jadi porsi termakan yang kupakai untuk hitung sekitar 205 g.`

## Elaborasi Foto dan Porsi

Kalau input dari foto makanan, jawaban wajib menjelaskan:
- ada item apa saja di foto,
- estimasi gram/porsi tiap item utama,
- komponen penting seperti nasi, lauk, saus, topping, roti, minuman, dan gorengan.

Kalau user memberi deskripsi porsi umum, wajib diterjemahkan ke estimasi gram/porsi yang eksplisit.

Contoh:
- `Roti sedang aku estimasikan sekitar 60 g.`
- `1 centong nasi aku hitung sekitar 100 g.`
- `Di foto kelihatan nasi putih sekitar 150 g, dada ayam goreng sekitar 90 g bagian daging, sambal sekitar 20 g.`

## Evaluasi Nutrisi Harian

Setiap selesai log makanan/minuman, setelah menampilkan item baru dan total sementara hari itu, tambahkan evaluasi singkat tentang progres nutrisi hari itu.

Minimal bahas:
- apa yang sudah bagus,
- apa yang masih kurang,
- apa yang sudah cukup,
- apa yang perlu dijaga,
- apa yang sebaiknya diperbanyak di sisa hari.

Fokus evaluasi:
- total kalori sementara vs target,
- protein sementara vs target protein,
- keseimbangan karbo dan lemak secara kasar,
- saran makan berikutnya, mis. tambah protein, sayur, buah, atau jaga lemak.

## Commands

`/weight` dan `/body-tracker` adalah alias. `/weight` tetap command utama.

| Command | What to do |
|---------|------------|
| `/weight add-food [text]` | Log makanan/minuman. Foto → analisis dengan `image` tool (`zai/glm-4.6v`), lalu `body-tracker.sh log-meal '<json>'`. Teks → estimasi sendiri lalu log. Jawaban wajib berisi item, kalori+makro, total sementara, penjelasan gram/porsi, catatan estimasi bila ada, dan evaluasi nutrisi harian. |
| `/weight add-activity [text]` | Log olahraga. Foto → analisis fitness screenshot, teks → estimasi lalu `body-tracker.sh log-activity`. |
| `/weight log-weight <kg>` | Catat berat badan via `body-tracker.sh log-weight <kg>`. |
| `/weight undo [makan\|olahraga]` | Hapus entri terakhir via `remove-last`. |
| `/weight remove <makan\|olahraga> <nomor>` | Hapus entri tertentu via `list` lalu `remove`. |
| `/weight daily [tanggal]` | Rekap hari itu via `body-tracker.sh daily [YYYY-MM-DD]`. |
| `/weight progress` | Progress menuju target + BMI + streak log makan. |
| `/wpd` | Cek progres nutrisi hari ini secara cepat via `body-tracker.sh wpd`. Tampilkan total kalori, protein, karbo, lemak, target harian, sisa target, dan evaluasi singkat kondisi hari itu. |
| `/wpw` | Cek progres/rekap nutrisi minggu ini via `body-tracker.sh wpw`. Tampilkan total/rata-rata kalori dan makro, olahraga, berat bila ada, lalu beri evaluasi singkat minggu berjalan. |
| `/wpm` | Cek progres/rekap nutrisi bulan ini via `body-tracker.sh wpm`. Tampilkan total/rata-rata kalori dan makro, olahraga, berat bila ada, lalu beri evaluasi singkat bulan berjalan. |
| `/weight weekly-report` | Jalankan `bash scripts/weekly-report.sh`. |
| `/weight monthly-report` | Jalankan `bash scripts/monthly-report.sh`. |
| `/weight help` | Jelaskan command. |

Bare `/weight` atau `/body-tracker` tanpa subcommand:
- foto makanan/minuman → `add-food`
- screenshot fitness → `add-activity`
- foto timbangan / angka berat → `log-weight`

## Help Text

Saat user menjalankan `/weight help`, jelaskan dalam Bahasa Indonesia:
- `/weight add-food [teks]` — catat makanan/minuman.
- `/weight add-activity [teks]` — catat olahraga/aktivitas.
- `/weight log-weight <kg>` — catat berat badan.
- `/weight undo` — batalkan catatan terakhir.
- `/weight remove <makan|olahraga> <nomor>` — hapus entri tertentu.
- `/weight daily` — rekap hari ini.
- `/weight progress` — progress menuju target + BMI + streak.
- `/wpd` — cek progres nutrisi hari ini secara cepat.
- `/wpw` — cek progres nutrisi minggu ini.
- `/wpm` — cek progres nutrisi bulan ini.
- `/weight weekly-report` — laporan minggu lalu.
- `/weight monthly-report` — laporan bulan lalu.
- `/weight` dan `/body-tracker` itu sama.

## Data Location

Daily logs:
- `/home/kusa/data/openclaw/body-tracker/YYYY-MM-DD.json`

User profile:
- `/home/kusa/data/openclaw/body-tracker/profile.json`

## Source Priority

Urutan sumber nutrisi yang diprioritaskan:
1. Label nutrisi produk resmi kalau ada.
2. Panganku / TKPI untuk makanan Indonesia umum.
3. USDA FoodData Central untuk bahan generik.
4. FatSecret hanya sebagai cross-check cepat.

Kalau datanya tetap tidak lengkap, pakai estimasi terbaik yang masuk akal dan jelaskan asumsi gram/porsinya.

## How to Use

### Step 1: Load profile

Selalu baca profile dulu:

```bash
cat /home/kusa/data/openclaw/body-tracker/profile.json
```

Kalau profile belum ada atau mau diupdate:

```bash
bash scripts/body-tracker.sh init-profile <height_cm> <weight_kg> <age> <target_kg> [gender] [activity_level] [deficit_rate]
```

### Step 2: Process user input

Foto makanan/minuman:
- gunakan `image` tool dengan model `zai/glm-4.6v`
- minta output item, kalori, protein, karbo, lemak, porsi
- lalu log dengan `body-tracker.sh log-meal`

Contoh JSON meal:

```bash
bash scripts/body-tracker.sh log-meal '{"type":"lunch","time":"12:30","items":[{"name":"nasi putih","calories":200,"protein":4,"carbs":44,"fat":0.4,"portion":"150 g","estimated":true}]}'
```

Penting:
- selalu isi `"time":"HH:MM"` dalam WIB
- setiap item sebaiknya punya `portion`
- kalau estimated, jelaskan asumsi gram/porsi di jawaban user

Foto fitness/smartwatch:
- gunakan `image` tool dengan model `zai/glm-4.6v`
- ekstrak tipe aktivitas, durasi, kalori, jarak bila ada
- log dengan `body-tracker.sh log-activity`

Input berat:

```bash
bash scripts/body-tracker.sh log-weight <weight_kg>
```

### Step 3: Recaps and Progress

```bash
bash scripts/body-tracker.sh daily [YYYY-MM-DD]
bash scripts/body-tracker.sh wpd [YYYY-MM-DD]
bash scripts/body-tracker.sh wpw [YYYY-MM-DD]
bash scripts/body-tracker.sh wpm [YYYY-MM-DD]
bash scripts/body-tracker.sh progress
```

### Response Format After Logging Food

Urutan respons yang disarankan:
1. item baru + kalori/makro,
2. total sementara hari itu + kalori/makro,
3. penjelasan item dan estimasi gram/porsi,
4. catatan estimasi khusus bila ada,
5. evaluasi progres nutrisi harian.

Untuk semua angka kalori dan makro di respons:
- tulis vertikal per baris,
- jangan pakai format side-by-side,
- ikuti preferensi user untuk metrik yang tidak ditulis nyamping.
