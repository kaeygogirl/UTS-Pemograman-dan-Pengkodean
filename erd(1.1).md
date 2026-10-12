# Entity Relationship Diagram — General Ledger

Dokumen ini mendefinisikan skema inti General Ledger ritel. Satu jurnal terdiri
dari satu header dan satu atau lebih baris; setiap baris mengacu ke tepat satu
akun di chart of accounts.

## Definisi tabel

### `chart_of_accounts`

| Kolom | Tipe | Constraint | Keterangan |
|---|---|---|---|
| `account_id` | BIGINT | PK, NOT NULL | ID unik akun. |
| `account_code` | VARCHAR(20) | UNIQUE, NOT NULL | Kode akun yang unik, misalnya `1001`. |
| `account_name` | VARCHAR(150) | NOT NULL | Nama akun. |
| `account_type` | VARCHAR(20) | NOT NULL, CHECK (`ASSET`, `LIABILITY`, `EQUITY`, `REVENUE`, `EXPENSE`) | Kelompok akun. |
| `normal_balance` | VARCHAR(6) | NOT NULL, CHECK (`DEBIT`, `CREDIT`) | Sisi saldo normal akun. |
| `is_active` | BOOLEAN | NOT NULL, DEFAULT TRUE | Menandai akun yang masih dapat digunakan. |
| `created_at` | TIMESTAMP | NOT NULL | Waktu pembuatan akun. |

### `journal_headers`

| Kolom | Tipe | Constraint | Keterangan |
|---|---|---|---|
| `header_id` | BIGINT | PK, NOT NULL | ID unik header jurnal. |
| `reference_number` | VARCHAR(50) | UNIQUE, NOT NULL | Nomor referensi jurnal yang unik. |
| `journal_date` | DATE | NOT NULL | Tanggal pencatatan jurnal. |
| `description` | VARCHAR(255) | NULL | Keterangan umum jurnal. |
| `status` | VARCHAR(10) | NOT NULL, CHECK (`DRAFT`, `POSTED`, `VOID`) | Status jurnal. Jurnal hanya boleh diposting jika seimbang. |
| `created_at` | TIMESTAMP | NOT NULL | Waktu pembuatan jurnal. |

### `journal_lines`

| Kolom | Tipe | Constraint | Keterangan |
|---|---|---|---|
| `line_id` | BIGINT | PK, NOT NULL | ID unik baris jurnal. |
| `header_id` | BIGINT | FK → `journal_headers.header_id`, NOT NULL | Header jurnal pemilik baris. |
| `account_id` | BIGINT | FK → `chart_of_accounts.account_id`, NOT NULL | Akun yang dicatat pada baris ini. |
| `line_number` | INTEGER | NOT NULL, UNIQUE (`header_id`, `line_number`) | Urutan baris dalam satu jurnal. |
| `debit` | DECIMAL(19,2) | NOT NULL, DEFAULT 0, CHECK (`debit` >= 0), CHECK ((`debit` > 0 AND `credit` = 0) OR (`debit` = 0 AND `credit` > 0)) | Nilai debit dalam mata uang fungsional; tepat satu sisi (debit/kredit) pada baris harus bernilai positif. |
| `credit` | DECIMAL(19,2) | NOT NULL, DEFAULT 0, CHECK (`credit` >= 0) | Nilai kredit dalam mata uang fungsional. |
| `memo` | VARCHAR(255) | NULL | Keterangan baris jurnal. |

Saat jurnal berstatus `POSTED`, jumlah debit seluruh baris untuk
`header_id` tersebut harus sama dengan jumlah kreditnya, dan jurnal harus
memiliki minimal dua baris. Kesetaraan lintas baris tidak dapat dijamin oleh
CHECK constraint biasa; validasi wajib dilakukan pada backend saat posting
(atau melalui mekanisme transaksional database seperti trigger/prosedur).
Jangan mengandalkan validasi frontend sebagai pengaman integritas.

## Relasi

```text
chart_of_accounts (1) ----< (N) journal_lines
  Satu akun dapat dipakai pada banyak baris jurnal;
  setiap baris jurnal mengacu ke satu akun.

journal_headers   (1) ----< (N) journal_lines
  Satu header memiliki banyak baris jurnal;
  setiap baris jurnal dimiliki satu header.
```

## Contoh transaksi dummy

Transaksi berikut mencatat penjualan tunai sebesar Rp150.000. Baris debit dan
kredit memakai akun yang sama dengan referensi pada `chart_of_accounts`.

### `journal_headers`

| header_id | reference_number | journal_date | description | status |
|---:|---|---|---|---|
| 501 | GL-2026-0001 | 2026-10-13 | Penjualan tunai | POSTED |

### `journal_lines`

| line_id | header_id | line_number | account_id | account_code | debit (Rp) | credit (Rp) | memo |
|---:|---:|---:|---:|---|---:|---:|---|
| 9001 | 501 | 1 | 101 | 1001 | 150.000,00 | 0,00 | Kas dari penjualan |
| 9002 | 501 | 2 | 401 | 4001 | 0,00 | 150.000,00 | Pendapatan penjualan |
| **Total** |  |  |  |  | **150.000,00** | **150.000,00** | **Seimbang** |

### `chart_of_accounts` (akun yang digunakan)

| account_id | account_code | account_name | account_type | normal_balance |
|---:|---|---|---|---|
| 101 | 1001 | Kas | ASSET | DEBIT |
| 401 | 4001 | Pendapatan Penjualan | REVENUE | CREDIT |
