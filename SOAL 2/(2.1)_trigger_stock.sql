-- Membuat function untuk memperbarui stok setelah transaksi persediaan baru.
CREATE OR REPLACE FUNCTION trg_update_stock_and_journal()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_stock_qty inventory_items.stock_qty%TYPE;
BEGIN
    -- Memperbarui stok secara atomik dan mencegah transaksi SALE menghasilkan stok negatif.
    UPDATE inventory_items
    SET stock_qty = stock_qty +
        CASE NEW.trx_type
            WHEN 'PURCHASE' THEN NEW.qty
            WHEN 'SALE' THEN -NEW.qty
            WHEN 'ADJUSTMENT' THEN NEW.qty
        END
    WHERE item_id = NEW.item_id
      AND (
          NEW.trx_type <> 'SALE'
          OR (stock_qty - NEW.qty) >= 0
      );

    -- Menolak transaksi jika item tidak ditemukan atau stok SALE tidak mencukupi.
    IF NOT FOUND THEN
        SELECT stock_qty
        INTO v_stock_qty
        FROM inventory_items
        WHERE item_id = NEW.item_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Item % tidak ditemukan', NEW.item_id;
        END IF;

        RAISE EXCEPTION
            'Stok tidak mencukupi untuk item %. Stok tersedia: %. Sisa stok jika transaksi diterapkan: %',
            NEW.item_id, v_stock_qty, v_stock_qty - NEW.qty;
    END IF;

    -- Mengembalikan baris transaksi yang baru dimasukkan.
    RETURN NEW;
END;
$$;

-- Menjalankan function untuk setiap transaksi persediaan yang baru dimasukkan.
DROP TRIGGER IF EXISTS update_stock_after_inventory_transaction
ON inventory_transactions;

CREATE TRIGGER update_stock_after_inventory_transaction
AFTER INSERT ON inventory_transactions
FOR EACH ROW
EXECUTE FUNCTION trg_update_stock_and_journal();
