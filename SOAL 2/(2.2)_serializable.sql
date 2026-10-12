-- PERSIAPAN: jalankan bagian ini sekali saja sebelum membuka dua sesi.
-- Ini menghapus penjualan tes lama agar sale_count berikutnya hanya menghitung tes baru.
-- DELETE FROM public.inventory_transactions WHERE item_id = 'TST002';
-- INSERT INTO public.inventory_items (item_id, item_name, stock_qty, unit_cost)
-- VALUES ('TST002', 'Tes SERIALIZABLE', 1, 1000)
-- ON CONFLICT (item_id) DO UPDATE SET stock_qty = 1;
--
-- TES: salin mulai dari BEGIN sampai COMMIT ke masing-masing dua query tab.
-- Jalankan tab A, lalu segera tab B. Jangan jalankan blok persiapan bersamaan.
BEGIN;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

DO $$
DECLARE
    v_stock_qty INT;
BEGIN
    SELECT stock_qty
    INTO v_stock_qty
    FROM public.inventory_items
    WHERE item_id = 'TST002';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Item TST002 tidak ditemukan';
    END IF;

    IF v_stock_qty < 1 THEN
        RAISE EXCEPTION 'Stok TST002 tidak cukup. Stok tersedia: %', v_stock_qty;
    END IF;

    -- Memberi kesempatan sesi kedua membaca snapshot stok yang sama.
    PERFORM pg_sleep(5);

    INSERT INTO public.inventory_transactions (item_id, trx_type, qty)
    VALUES ('TST002', 'SALE', 1);
END;
$$;

COMMIT;

-- Jika mendapat SQLSTATE 40001, rollback bila perlu; retry aplikasi harus mengulang dari BEGIN.
-- Jalankan pemeriksaan berikut setelah kedua sesi selesai.
SELECT item_id, stock_qty
FROM public.inventory_items
WHERE item_id = 'TST002';

SELECT COUNT(*) AS sale_count
FROM public.inventory_transactions
WHERE item_id = 'TST002'
  AND trx_type = 'SALE';
-- Hasil yang diharapkan setelah reset: stock_qty = 0 dan sale_count = 1.
