-- Non-destructive migration for a database where the original tables already exist.
-- Back up first. Run this BEFORE 01_triggers_fixed.sql and 02_procedures_fixed.sql.
-- This does not create tables and does not delete existing rows.
BEGIN;

-- Applications are not assigned to an employee until a manager/admin decides them.
ALTER TABLE loan ALTER COLUMN employee_id DROP NOT NULL;

-- Add identifier/date checks only if they are not already present.
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_branch_ifsc_format') THEN
        ALTER TABLE branch ADD CONSTRAINT ck_branch_ifsc_format
            CHECK (ifsc ~ '^[A-Z]{4}0[A-Z0-9]{6}$') NOT VALID;
        ALTER TABLE branch VALIDATE CONSTRAINT ck_branch_ifsc_format;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_branch_micr_format') THEN
        ALTER TABLE branch ADD CONSTRAINT ck_branch_micr_format
            CHECK (micr ~ '^[0-9]{9}$') NOT VALID;
        ALTER TABLE branch VALIDATE CONSTRAINT ck_branch_micr_format;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_branch_pin_format') THEN
        ALTER TABLE branch ADD CONSTRAINT ck_branch_pin_format
            CHECK (pin ~ '^[0-9]{6}$') NOT VALID;
        ALTER TABLE branch VALIDATE CONSTRAINT ck_branch_pin_format;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_customer_pan_format') THEN
        ALTER TABLE customer ADD CONSTRAINT ck_customer_pan_format
            CHECK (pan ~ '^[A-Z]{5}[0-9]{4}[A-Z]$') NOT VALID;
        ALTER TABLE customer VALIDATE CONSTRAINT ck_customer_pan_format;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_customer_aadhaar_format') THEN
        ALTER TABLE customer ADD CONSTRAINT ck_customer_aadhaar_format
            CHECK (aadhar_no ~ '^[0-9]{12}$') NOT VALID;
        ALTER TABLE customer VALIDATE CONSTRAINT ck_customer_aadhaar_format;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_loan_dates_order') THEN
        ALTER TABLE loan ADD CONSTRAINT ck_loan_dates_order
            CHECK (start_date IS NULL OR end_date IS NULL OR end_date > start_date) NOT VALID;
        ALTER TABLE loan VALIDATE CONSTRAINT ck_loan_dates_order;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_employee_ifsc ON employee(ifsc);
CREATE INDEX IF NOT EXISTS idx_account_cif ON account(cif);
CREATE INDEX IF NOT EXISTS idx_account_ifsc ON account(ifsc);
CREATE INDEX IF NOT EXISTS idx_account_type ON account(account_type_id);
CREATE INDEX IF NOT EXISTS idx_transaction_account_time ON "TRANSACTION"(account_no, transaction_date_time DESC);
CREATE INDEX IF NOT EXISTS idx_transaction_employee ON "TRANSACTION"(employee_id);
CREATE INDEX IF NOT EXISTS idx_fund_transfer_from ON fund_transfer(from_account_no);
CREATE INDEX IF NOT EXISTS idx_fund_transfer_to ON fund_transfer(to_account_no);
CREATE INDEX IF NOT EXISTS idx_loan_cif ON loan(cif);
CREATE INDEX IF NOT EXISTS idx_loan_account ON loan(account_no);
CREATE INDEX IF NOT EXISTS idx_loan_employee ON loan(employee_id);
CREATE INDEX IF NOT EXISTS idx_loan_payment_loan ON loan_payment(loan_id);
CREATE INDEX IF NOT EXISTS idx_login_employee ON login(employee_id);
CREATE INDEX IF NOT EXISTS idx_login_cif ON login(cif);
CREATE INDEX IF NOT EXISTS idx_audit_changed_at ON audit_log(changed_at DESC);

COMMIT;
