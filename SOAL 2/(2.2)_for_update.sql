-- PERSIAPAN: jalankan bagian ini sekali saja sebelum membuka dua sesi.
-- Menghapus penjualan lama membuat sale_count hanya menghitung tes yang baru.
-- DELETE FROM public.inventory_transactions WHERE item_id = 'TST001';
-- INSERT INTO public.inventory_items (item_id, item_name, stock_qty, unit_cost)
-- VALUES ('TST001', 'Tes FOR UPDATE', 1, 1000)
-- ON CONFLICT (item_id) DO UPDATE SET stock_qty = 1;
--
-- TES: salin mulai dari BEGIN sampai COMMIT ke masing-masing dua query tab.
-- Jalankan tab A, lalu segera tab B. Jangan jalankan persiapan bersamaan.
BEGIN;

DO $$
DECLARE
    v_stock_qty INT;
BEGIN
    SELECT stock_qty
    INTO v_stock_qty
    FROM public.inventory_items
    WHERE item_id = 'TST001'
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Item TST001 tidak ditemukan';
    END IF;

    IF v_stock_qty < 1 THEN
        RAISE EXCEPTION 'Stok TST001 tidak cukup. Stok tersedia: %', v_stock_qty;
    END IF;

    -- Menahan lock sesaat agar sesi kedua sempat mencoba mengunci baris yang sama.
    PERFORM pg_sleep(5);

    INSERT INTO public.inventory_transactions (item_id, trx_type, qty)
    VALUES ('TST001', 'SALE', 1);
END;
$$;

COMMIT;

-- Jika blok gagal, jalankan ROLLBACK pada sesi yang gagal.
-- Jalankan pemeriksaan berikut setelah kedua sesi selesai.
SELECT item_id, stock_qty
FROM public.inventory_items
WHERE item_id = 'TST001';

SELECT COUNT(*) AS sale_count
FROM public.inventory_transactions
WHERE item_id = 'TST001'
  AND trx_type = 'SALE';
-- Hasil yang diharapkan setelah reset: stock_qty = 0 dan sale_count = 1.
