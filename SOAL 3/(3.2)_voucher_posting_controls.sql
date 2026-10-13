-- SHA-256 support for posted voucher checksums.
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- Voucher header; authenticated users can create only DRAFT vouchers.
CREATE TABLE IF NOT EXISTS public.vouchers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    voucher_no TEXT NOT NULL UNIQUE,
    voucher_date DATE NOT NULL,
    payee TEXT NOT NULL,
    memo TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'DRAFT'
        CHECK (status IN ('DRAFT', 'POSTED')),
    reverses_id UUID UNIQUE REFERENCES public.vouchers(id),
    created_by UUID NOT NULL DEFAULT auth.uid()
        REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    hash_checksum TEXT,
    CONSTRAINT voucher_posting_checksum_check CHECK (
        (status = 'DRAFT' AND hash_checksum IS NULL)
        OR (status = 'POSTED' AND hash_checksum IS NOT NULL)
    )
);

-- Lines require exactly one positive side: debit or credit.
CREATE TABLE IF NOT EXISTS public.voucher_lines (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    voucher_id UUID NOT NULL REFERENCES public.vouchers(id),
    account_code TEXT NOT NULL,
    description TEXT,
    debit NUMERIC(18, 2) NOT NULL DEFAULT 0 CHECK (debit >= 0),
    credit NUMERIC(18, 2) NOT NULL DEFAULT 0 CHECK (credit >= 0),
    CONSTRAINT voucher_line_one_side_check CHECK (
        (debit = 0) <> (credit = 0)
    )
);

CREATE INDEX IF NOT EXISTS voucher_lines_voucher_id_idx
    ON public.voucher_lines(voucher_id);

-- Append-only audit trail.
CREATE TABLE IF NOT EXISTS public.audit_log (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    voucher_id UUID REFERENCES public.vouchers(id),
    action TEXT NOT NULL,
    actor UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
    at TIMESTAMPTZ NOT NULL DEFAULT now(),
    detail JSONB
);

-- Hash a stable, explicit serialization of the voucher and ordered lines.
CREATE OR REPLACE FUNCTION public.voucher_checksum(p_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, extensions, auth, pg_temp
AS $$
DECLARE
    v_payload JSONB;
BEGIN
    SELECT jsonb_build_object(
        'id', v.id,
        'voucher_no', v.voucher_no,
        'voucher_date', v.voucher_date,
        'payee', v.payee,
        'memo', v.memo,
        'status', 'POSTED',
        'reverses_id', v.reverses_id,
        'created_by', v.created_by,
        'created_at_utc',
            to_char(v.created_at AT TIME ZONE 'UTC',
                    'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'lines', COALESCE(
            (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'id', l.id,
                        'account_code', l.account_code,
                        'description', l.description,
                        'debit', l.debit,
                        'credit', l.credit
                    )
                    ORDER BY l.id
                )
                FROM public.voucher_lines AS l
                WHERE l.voucher_id = v.id
            ),
            '[]'::JSONB
        )
    )
    INTO v_payload
    FROM public.vouchers AS v
    WHERE v.id = p_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Voucher % tidak ditemukan', p_id;
    END IF;

    RETURN encode(
        extensions.digest(convert_to(v_payload::TEXT, 'UTF8'), 'sha256'),
        'hex'
    );
END;
$$;

-- Enforce voucher audit fields, posting validation, and header immutability.
CREATE OR REPLACE FUNCTION public.guard_voucher_header()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, extensions, auth, pg_temp
AS $$
DECLARE
    v_line_count BIGINT;
    v_debit NUMERIC(18, 2);
    v_credit NUMERIC(18, 2);
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF auth.uid() IS NULL THEN
            RAISE EXCEPTION 'Pengguna terautentikasi diperlukan';
        END IF;

        IF NEW.status <> 'DRAFT' OR NEW.hash_checksum IS NOT NULL THEN
            RAISE EXCEPTION 'Voucher harus dibuat sebagai DRAFT tanpa checksum';
        END IF;

        IF NEW.reverses_id IS NOT NULL
           AND current_setting('app.reverse_voucher', TRUE) IS DISTINCT FROM 'on' THEN
            RAISE EXCEPTION 'Voucher pembalik harus dibuat melalui reverse_voucher()';
        END IF;

        NEW.created_by := auth.uid();
        NEW.created_at := clock_timestamp();
        RETURN NEW;
    END IF;

    IF TG_OP = 'DELETE' THEN
        IF OLD.status = 'POSTED' THEN
            RAISE EXCEPTION
                'Voucher POSTED tidak dapat dihapus; gunakan jurnal pembalik';
        END IF;
        RETURN OLD;
    END IF;

    IF OLD.status = 'POSTED' THEN
        RAISE EXCEPTION
            'Voucher POSTED tidak dapat diubah; gunakan jurnal pembalik';
    END IF;

    IF NEW.created_by IS DISTINCT FROM OLD.created_by
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
       OR NEW.reverses_id IS DISTINCT FROM OLD.reverses_id THEN
        RAISE EXCEPTION 'Field audit dan referensi pembalik tidak dapat diubah';
    END IF;

    IF NEW.status IS DISTINCT FROM OLD.status THEN
        IF NEW.status <> 'POSTED'
           OR current_setting('app.post_voucher', TRUE) IS DISTINCT FROM 'on' THEN
            RAISE EXCEPTION 'Perubahan status hanya dapat dilakukan melalui post_voucher()';
        END IF;

        SELECT COUNT(*), COALESCE(SUM(debit), 0), COALESCE(SUM(credit), 0)
        INTO v_line_count, v_debit, v_credit
        FROM public.voucher_lines
        WHERE voucher_id = OLD.id;

        IF v_line_count < 2 THEN
            RAISE EXCEPTION 'Voucher harus memiliki minimal dua baris';
        END IF;

        IF v_debit <= 0 OR v_debit <> v_credit THEN
            RAISE EXCEPTION
                'Voucher tidak seimbang: debit %, kredit %',
                v_debit, v_credit;
        END IF;

        NEW.hash_checksum := public.voucher_checksum(OLD.id);

        INSERT INTO public.audit_log (voucher_id, action, actor, detail)
        VALUES (
            OLD.id,
            'POSTED',
            auth.uid(),
            jsonb_build_object('hash_checksum', NEW.hash_checksum)
        );
    ELSIF NEW.hash_checksum IS DISTINCT FROM OLD.hash_checksum THEN
        RAISE EXCEPTION 'Checksum hanya dapat dibuat saat posting';
    END IF;

    RETURN NEW;
END;
$$;

-- Lock the parent voucher while editing lines, preventing races with posting.
CREATE OR REPLACE FUNCTION public.guard_voucher_line()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
    v_status TEXT;
    v_voucher_id UUID;
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.voucher_id IS DISTINCT FROM OLD.voucher_id THEN
        RAISE EXCEPTION 'Baris tidak dapat dipindahkan ke voucher lain';
    END IF;

    v_voucher_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.voucher_id
                         ELSE NEW.voucher_id END;

    SELECT status
    INTO v_status
    FROM public.vouchers
    WHERE id = v_voucher_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Voucher % tidak ditemukan', v_voucher_id;
    END IF;

    IF v_status = 'POSTED' THEN
        RAISE EXCEPTION
            'Baris voucher POSTED tidak dapat ditambah, diubah, atau dihapus';
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

-- The audit log can only be appended; row changes and deletion are forbidden.
CREATE OR REPLACE FUNCTION public.block_audit_log_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'Audit log bersifat append-only';
END;
$$;

DROP TRIGGER IF EXISTS vouchers_guard
    ON public.vouchers;
CREATE TRIGGER vouchers_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.vouchers
FOR EACH ROW
EXECUTE FUNCTION public.guard_voucher_header();

DROP TRIGGER IF EXISTS voucher_lines_guard
    ON public.voucher_lines;
CREATE TRIGGER voucher_lines_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.voucher_lines
FOR EACH ROW
EXECUTE FUNCTION public.guard_voucher_line();

DROP TRIGGER IF EXISTS audit_log_append_only
    ON public.audit_log;
CREATE TRIGGER audit_log_append_only
BEFORE UPDATE OR DELETE ON public.audit_log
FOR EACH ROW
EXECUTE FUNCTION public.block_audit_log_mutation();

-- Post a balanced DRAFT voucher. Header row lock serializes edits and posting.
CREATE OR REPLACE FUNCTION public.post_voucher(p_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, extensions, auth, pg_temp
AS $$
DECLARE
    v_voucher public.vouchers%ROWTYPE;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Pengguna terautentikasi diperlukan';
    END IF;

    SELECT *
    INTO v_voucher
    FROM public.vouchers
    WHERE id = p_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Voucher % tidak ditemukan', p_id;
    END IF;

    IF v_voucher.created_by <> auth.uid() THEN
        RAISE EXCEPTION 'Tidak berwenang mem-posting voucher ini';
    END IF;

    IF v_voucher.status <> 'DRAFT' THEN
        RAISE EXCEPTION 'Hanya voucher DRAFT yang dapat diposting';
    END IF;

    PERFORM set_config('app.post_voucher', 'on', TRUE);

    UPDATE public.vouchers
    SET status = 'POSTED'
    WHERE id = p_id;

    PERFORM set_config('app.post_voucher', 'off', TRUE);

    RETURN (
        SELECT hash_checksum
        FROM public.vouchers
        WHERE id = p_id
    );
END;
$$;

-- Reverse a POSTED voucher by creating and posting a new voucher with sides swapped.
CREATE OR REPLACE FUNCTION public.reverse_voucher(p_id UUID, p_reason TEXT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, extensions, auth, pg_temp
AS $$
DECLARE
    v_original public.vouchers%ROWTYPE;
    v_reversal_id UUID;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Pengguna terautentikasi diperlukan';
    END IF;

    IF NULLIF(btrim(p_reason), '') IS NULL THEN
        RAISE EXCEPTION 'Alasan pembalik wajib diisi';
    END IF;

    SELECT *
    INTO v_original
    FROM public.vouchers
    WHERE id = p_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Voucher % tidak ditemukan', p_id;
    END IF;

    IF v_original.created_by <> auth.uid() THEN
        RAISE EXCEPTION 'Tidak berwenang membalik voucher ini';
    END IF;

    IF v_original.status <> 'POSTED' OR v_original.reverses_id IS NOT NULL THEN
        RAISE EXCEPTION 'Hanya voucher POSTED asli yang dapat dibalik';
    END IF;

    IF v_original.hash_checksum IS DISTINCT FROM public.voucher_checksum(p_id) THEN
        RAISE EXCEPTION 'Checksum voucher % tidak valid', p_id;
    END IF;

    PERFORM set_config('app.reverse_voucher', 'on', TRUE);

    INSERT INTO public.vouchers (
        voucher_no, voucher_date, payee, memo, reverses_id
    )
    VALUES (
        'STORNO-' || v_original.voucher_no,
        CURRENT_DATE,
        v_original.payee,
        'Pembalik: ' || btrim(p_reason),
        p_id
    )
    RETURNING id INTO v_reversal_id;

    PERFORM set_config('app.reverse_voucher', 'off', TRUE);

    INSERT INTO public.voucher_lines (
        voucher_id, account_code, description, debit, credit
    )
    SELECT
        v_reversal_id,
        account_code,
        description,
        credit,
        debit
    FROM public.voucher_lines
    WHERE voucher_id = p_id
    ORDER BY id;

    PERFORM public.post_voucher(v_reversal_id);

    INSERT INTO public.audit_log (voucher_id, action, actor, detail)
    VALUES (
        p_id,
        'REVERSED',
        auth.uid(),
        jsonb_build_object(
            'reversal_voucher_id', v_reversal_id,
            'reason', btrim(p_reason)
        )
    );

    RETURN v_reversal_id;
END;
$$;

-- Verify the saved checksum against the current canonical voucher contents.
CREATE OR REPLACE FUNCTION public.verify_voucher_checksum(p_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, extensions, auth, pg_temp
AS $$
DECLARE
    v_voucher public.vouchers%ROWTYPE;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Pengguna terautentikasi diperlukan';
    END IF;

    SELECT *
    INTO v_voucher
    FROM public.vouchers
    WHERE id = p_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Voucher % tidak ditemukan', p_id;
    END IF;

    IF v_voucher.created_by <> auth.uid() THEN
        RAISE EXCEPTION 'Tidak berwenang memverifikasi voucher ini';
    END IF;

    RETURN v_voucher.status = 'POSTED'
       AND v_voucher.hash_checksum = public.voucher_checksum(p_id);
END;
$$;

-- RLS: users may read and edit their own DRAFTs; posted rows are read-only.
ALTER TABLE public.vouchers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.voucher_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS vouchers_select_own
    ON public.vouchers;
CREATE POLICY vouchers_select_own
ON public.vouchers FOR SELECT TO authenticated
USING (created_by = auth.uid());

DROP POLICY IF EXISTS vouchers_insert_own_draft
    ON public.vouchers;
CREATE POLICY vouchers_insert_own_draft
ON public.vouchers FOR INSERT TO authenticated
WITH CHECK (
    created_by = auth.uid()
    AND status = 'DRAFT'
    AND hash_checksum IS NULL
    AND reverses_id IS NULL
);

DROP POLICY IF EXISTS vouchers_update_own_draft
    ON public.vouchers;
CREATE POLICY vouchers_update_own_draft
ON public.vouchers FOR UPDATE TO authenticated
USING (created_by = auth.uid() AND status = 'DRAFT')
WITH CHECK (
    created_by = auth.uid()
    AND status = 'DRAFT'
    AND hash_checksum IS NULL
);

DROP POLICY IF EXISTS vouchers_delete_own_draft
    ON public.vouchers;
CREATE POLICY vouchers_delete_own_draft
ON public.vouchers FOR DELETE TO authenticated
USING (created_by = auth.uid() AND status = 'DRAFT');

DROP POLICY IF EXISTS voucher_lines_select_own
    ON public.voucher_lines;
CREATE POLICY voucher_lines_select_own
ON public.voucher_lines FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.vouchers AS v
        WHERE v.id = voucher_lines.voucher_id
          AND v.created_by = auth.uid()
    )
);

DROP POLICY IF EXISTS voucher_lines_insert_own_draft
    ON public.voucher_lines;
CREATE POLICY voucher_lines_insert_own_draft
ON public.voucher_lines FOR INSERT TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.vouchers AS v
        WHERE v.id = voucher_lines.voucher_id
          AND v.created_by = auth.uid()
          AND v.status = 'DRAFT'
    )
);

DROP POLICY IF EXISTS voucher_lines_update_own_draft
    ON public.voucher_lines;
CREATE POLICY voucher_lines_update_own_draft
ON public.voucher_lines FOR UPDATE TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.vouchers AS v
        WHERE v.id = voucher_lines.voucher_id
          AND v.created_by = auth.uid()
          AND v.status = 'DRAFT'
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.vouchers AS v
        WHERE v.id = voucher_lines.voucher_id
          AND v.created_by = auth.uid()
          AND v.status = 'DRAFT'
    )
);

DROP POLICY IF EXISTS voucher_lines_delete_own_draft
    ON public.voucher_lines;
CREATE POLICY voucher_lines_delete_own_draft
ON public.voucher_lines FOR DELETE TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.vouchers AS v
        WHERE v.id = voucher_lines.voucher_id
          AND v.created_by = auth.uid()
          AND v.status = 'DRAFT'
    )
);

DROP POLICY IF EXISTS audit_log_select_own
    ON public.audit_log;
CREATE POLICY audit_log_select_own
ON public.audit_log FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.vouchers AS v
        WHERE v.id = audit_log.voucher_id
          AND v.created_by = auth.uid()
    )
);

GRANT SELECT, INSERT, UPDATE, DELETE
ON public.vouchers, public.voucher_lines
TO authenticated;
GRANT SELECT ON public.audit_log TO authenticated;

REVOKE ALL ON public.audit_log FROM anon, authenticated;
GRANT SELECT ON public.audit_log TO authenticated;
REVOKE EXECUTE ON FUNCTION public.voucher_checksum(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.post_voucher(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.reverse_voucher(UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.verify_voucher_checksum(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.post_voucher(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reverse_voucher(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.verify_voucher_checksum(UUID) TO authenticated;
