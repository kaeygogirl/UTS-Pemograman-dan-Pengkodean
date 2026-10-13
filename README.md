# Ujian Tengah Semester — Pemrograman / Coding
**Inka Muzalifa (12030124120013)**

## 🔗 Tautan Penting

| Artefak | Tautan |
|---|---|
| **Demo Gemini Canvas (Purwarupa UI Voucher Kas Keluar)** | **https://share.gemini.google/fOyeJDJEzWHs** |

---

---

## 📘 SOAL 1 — Desain Arsitektur Data, Normalisasi & Penegakan Asas Berpasangan

### 1.1 Perancangan Skema Relasional (ERD)
- Entitas: `chart_of_accounts`, `journal_headers`, `journal_lines`.
- Relasi 1:N antara COA → journal_lines dan journal_headers → journal_lines.

### 1.2 Kekangan Integritas (DDL PostgreSQL)
- Primary Key, Foreign Key dengan `ON DELETE RESTRICT`.
- CHECK: `debit >= 0`, `credit >= 0`, tidak keduanya nol, hanya satu sisi terisi.
- Trigger deferred untuk `SUM(debit) = SUM(credit)` per header.
  
### 1.3 Analisis Audit & Keamanan Finansial
- Perbandingan Header-Line vs Flat Journal Table (audit trail, 3NF, keamanan).

---

## 📗 SOAL 2 — Otomasi Bisnis, Stored Procedures & Database Trigger Persediaan

### 2.1 Otomatisasi Mutasi via Database Trigger
- Function `trg_update_stock_and_journal()` memperbarui `stock_qty` setiap INSERT pada `inventory_transactions`.
- `RAISE EXCEPTION` jika `SALE` menyebabkan stok negatif (anti-negative inventory prevention).

### 2.2 Penanganan Concurrency (Race Condition)
- Teknik: `SELECT ... FOR UPDATE`, Serializable Isolation, Optimistic Locking, Advisory Lock.
- Rekomendasi: `SELECT ... FOR UPDATE` pada baris `inventory_items` sebelum validasi stok.

---

## 📙 SOAL 3 — Integrasi Purwarupa Web Full-Stack & Orkestrasi AI Tools

### 3.1 Orkestrasi AI Tools

**3.1.a Gemini Canvas — Formulir Entri Jurnal Dinamis**
- Komponen React + Tailwind CSS dengan live balanced indicator.
- Tombol Submit otomatis nonaktif jika Total Debit ≠ Total Kredit.
- 🎨 **Demo Aplikasi:** **https://share.gemini.google/fOyeJDJEzWHs**

**3.1.b NotebookLM — Verifikasi Kepatuhan PSAK**
- Verifikasi logika kode terhadap PSAK 2 (Laporan Arus Kas) terkait pengakuan kas dan setara kas.

### 3.2 Mekanisme Jejak Audit (Audit Trail & Immutability)
- Transaksi `POSTED` dikunci di level database: trigger menolak `UPDATE` dan `DELETE`.
- Koreksi hanya melalui jurnal pembalik (storno) dengan prefix `STORNO-` dan referensi `reverses_id`.
- Field audit:
  - `created_by` — dari `auth.uid()` (JWT Supabase).
  - `created_at` — waktu server (`clock_timestamp()`).
  - `hash_checksum` — SHA-256 dari representasi kanonis header dan baris voucher.
- Verifikasi integritas: `verify_voucher_checksum(voucher_id)`.

---

## 📄 Lisensi

Artefak ujian tengah semester — Departemen Akuntansi FEB Universitas Diponegoro.
