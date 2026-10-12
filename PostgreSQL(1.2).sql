-- ENUM types
CREATE TYPE normal_balance_enum AS ENUM ('D', 'K');
CREATE TYPE report_class_enum AS ENUM (
    'ASET',
    'LIABILITAS',
    'EKUITAS',
    'PENDAPATAN',
    'BEBAN'
);
CREATE TYPE posting_status_enum AS ENUM ('DRAFT', 'POSTED', 'VOID');

-- Chart of accounts table
CREATE TABLE chart_of_accounts (
    account_id SERIAL PRIMARY KEY,
    account_code VARCHAR(20) NOT NULL UNIQUE,
    account_name VARCHAR(100) NOT NULL,
    normal_balance normal_balance_enum NOT NULL,
    report_classification report_class_enum NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Journal headers table
CREATE TABLE journal_headers (
    header_id SERIAL PRIMARY KEY,
    transaction_date DATE NOT NULL,
    reference_number VARCHAR(50) NOT NULL UNIQUE,
    description TEXT,
    status_posting posting_status_enum NOT NULL DEFAULT 'DRAFT',
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Journal lines table and row-level debit-credit constraints
CREATE TABLE journal_lines (
    line_id SERIAL PRIMARY KEY,
    header_id INTEGER NOT NULL,
    account_id INTEGER NOT NULL,
    debit NUMERIC(18,2) NOT NULL DEFAULT 0,
    credit NUMERIC(18,2) NOT NULL DEFAULT 0,
    CONSTRAINT fk_jl_header
        FOREIGN KEY (header_id)
        REFERENCES journal_headers (header_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    CONSTRAINT fk_jl_account
        FOREIGN KEY (account_id)
        REFERENCES chart_of_accounts (account_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    CONSTRAINT chk_jl_debit_nonnegative CHECK (debit >= 0),
    CONSTRAINT chk_jl_credit_nonnegative CHECK (credit >= 0),
    CONSTRAINT chk_jl_has_amount CHECK (debit > 0 OR credit > 0),
    CONSTRAINT chk_jl_one_sided_amount CHECK (
        (debit > 0 AND credit = 0)
        OR (credit > 0 AND debit = 0)
    )
);

-- Indexes for journal line and header lookups
CREATE INDEX idx_jl_header ON journal_lines (header_id);
CREATE INDEX idx_jl_account ON journal_lines (account_id);
CREATE INDEX idx_jh_date ON journal_headers (transaction_date);
CREATE INDEX idx_jh_status ON journal_headers (status_posting);

-- Deferred journal balance validation function
CREATE FUNCTION fn_check_journal_balanced()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_header_id INTEGER;
    v_debit_total NUMERIC(18,2);
    v_credit_total NUMERIC(18,2);
BEGIN
    IF TG_OP = 'UPDATE' THEN
        PERFORM header_id
        FROM journal_headers
        WHERE header_id IN (OLD.header_id, NEW.header_id)
        ORDER BY header_id
        FOR UPDATE;

        FOR v_header_id IN
            SELECT DISTINCT candidate.header_id
            FROM unnest(ARRAY[OLD.header_id, NEW.header_id]) AS candidate(header_id)
            ORDER BY candidate.header_id
        LOOP
            SELECT COALESCE(SUM(debit), 0), COALESCE(SUM(credit), 0)
            INTO v_debit_total, v_credit_total
            FROM journal_lines
            WHERE header_id = v_header_id;

            IF v_debit_total <> v_credit_total THEN
                RAISE EXCEPTION
                    'Journal header % is unbalanced: debit total %, credit total %',
                    v_header_id, v_debit_total, v_credit_total
                    USING ERRCODE = '23514';
            END IF;
        END LOOP;

        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        v_header_id := OLD.header_id;
    ELSE
        v_header_id := NEW.header_id;
    END IF;

    PERFORM header_id
    FROM journal_headers
    WHERE header_id = v_header_id
    FOR UPDATE;

    SELECT COALESCE(SUM(debit), 0), COALESCE(SUM(credit), 0)
    INTO v_debit_total, v_credit_total
    FROM journal_lines
    WHERE header_id = v_header_id;

    IF v_debit_total <> v_credit_total THEN
        RAISE EXCEPTION
            'Journal header % is unbalanced: debit total %, credit total %',
            v_header_id, v_debit_total, v_credit_total
            USING ERRCODE = '23514';
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

-- Deferred constraint trigger for journal balance validation
CREATE CONSTRAINT TRIGGER trg_journal_balanced
AFTER INSERT OR UPDATE OR DELETE ON journal_lines
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION fn_check_journal_balanced();
