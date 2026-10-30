-- ========================================
-- DEPOSTIE
-- ========================================
CREATE OR REPLACE PROCEDURE sp_deposit(
    IN p_transaction_id VARCHAR(20),
    IN p_account_no VARCHAR(20),
    IN p_amount NUMERIC(14,5),
    IN p_channel VARCHAR(20),
    IN p_employee_id VARCHAR(20) DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_balance NUMERIC(14,5);
BEGIN
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Deposit amount must be positive';
    END IF;

    IF p_channel NOT IN (
        'Branch', 'ATM', 'Online_Banking', 'UPI',
        'POS', 'Cheque', 'NEFT', 'RTGS', 'IMPS'
    ) THEN
        RAISE EXCEPTION 'Invalid transaction channel';
    END IF;

    SELECT Current_Balance
    INTO v_balance
    FROM ACCOUNT
    WHERE Account_No = p_account_no
      AND Status = 'Active'
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Account does not exist or is not active';
    END IF;

    UPDATE ACCOUNT
    SET Current_Balance = Current_Balance + p_amount
    WHERE Account_No = p_account_no
    RETURNING Current_Balance INTO v_balance;

    INSERT INTO "TRANSACTION" (
        Transaction_ID, Account_No, Employee_ID,
        Transaction_Type, Amount, Balance_After,
        Channel, Status
    )
    VALUES (
        p_transaction_id, p_account_no, p_employee_id,
        'Deposit', p_amount, v_balance,
        p_channel, 'Completed'
    );
END;
$$;
-- ==============================================
--         WITHDRAW
-- ===========================================

CREATE OR REPLACE PROCEDURE sp_withdraw(
    IN p_transaction_id VARCHAR(20),
    IN p_account_no VARCHAR(20),
    IN p_amount NUMERIC(14,5),
    IN p_channel VARCHAR(20),
    IN p_employee_id VARCHAR(20) DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_balance NUMERIC(14,5);
BEGIN
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Withdrawal amount must be positive';
    END IF;

    IF p_channel NOT IN (
        'Branch', 'ATM', 'Online_Banking', 'UPI',
        'POS', 'Cheque', 'NEFT', 'RTGS', 'IMPS'
    ) THEN
        RAISE EXCEPTION 'Invalid transaction channel';
    END IF;

    SELECT Current_Balance
    INTO v_balance
    FROM ACCOUNT
    WHERE Account_No = p_account_no
      AND Status = 'Active'
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Account does not exist or is not active';
    END IF;

    IF v_balance < p_amount THEN
        RAISE EXCEPTION 'Insufficient balance';
    END IF;

    UPDATE ACCOUNT
    SET Current_Balance = Current_Balance - p_amount
    WHERE Account_No = p_account_no
    RETURNING Current_Balance INTO v_balance;

    INSERT INTO "TRANSACTION" (
        Transaction_ID, Account_No, Employee_ID,
        Transaction_Type, Amount, Balance_After,
        Channel, Status
    )
    VALUES (
        p_transaction_id, p_account_no, p_employee_id,
        'Withdrawal', p_amount, v_balance,
        p_channel, 'Completed'
    );
END;
$$;

-- ===========================================
--				FUND TRANSFER
--=============================================

CREATE OR REPLACE PROCEDURE sp_fund_transfer(
    IN p_debit_transaction_id VARCHAR(20),
    IN p_credit_transaction_id VARCHAR(20),
    IN p_from_account VARCHAR(20),
    IN p_to_account VARCHAR(20),
    IN p_amount NUMERIC(14,5),
    IN p_transfer_mode VARCHAR(20),
    IN p_reference_no VARCHAR(30),
    IN p_employee_id VARCHAR(20) DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_from_balance NUMERIC(14,5);
    v_to_balance NUMERIC(14,5);
    v_channel VARCHAR(20);
BEGIN
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Transfer amount must be positive';
    END IF;

    IF p_from_account = p_to_account THEN
        RAISE EXCEPTION 'Source and destination accounts must differ';
    END IF;

    IF p_debit_transaction_id = p_credit_transaction_id THEN
        RAISE EXCEPTION 'Debit and credit transaction IDs must differ';
    END IF;

    IF p_transfer_mode NOT IN
       ('UPI','Internal_Transfer','Cheque','NEFT','RTGS','IMPS') THEN
        RAISE EXCEPTION 'Invalid transfer mode';
    END IF;

    v_channel := CASE
        WHEN p_transfer_mode = 'Internal_Transfer' THEN 'Online_Banking'
        ELSE p_transfer_mode
    END;

    -- Lock accounts in a consistent order
    PERFORM 1
    FROM ACCOUNT
    WHERE Account_No IN (p_from_account, p_to_account)
    ORDER BY Account_No
    FOR UPDATE;

    IF (SELECT COUNT(*)
        FROM ACCOUNT
        WHERE Account_No IN (p_from_account, p_to_account)
          AND Status = 'Active') <> 2 THEN
        RAISE EXCEPTION 'Both accounts must exist and be active';
    END IF;

    SELECT Current_Balance INTO v_from_balance
    FROM ACCOUNT WHERE Account_No = p_from_account;

    IF v_from_balance < p_amount THEN
        RAISE EXCEPTION 'Insufficient balance';
    END IF;

    UPDATE ACCOUNT
    SET Current_Balance = Current_Balance - p_amount
    WHERE Account_No = p_from_account
    RETURNING Current_Balance INTO v_from_balance;

    UPDATE ACCOUNT
    SET Current_Balance = Current_Balance + p_amount
    WHERE Account_No = p_to_account
    RETURNING Current_Balance INTO v_to_balance;

    INSERT INTO "TRANSACTION"(
        Transaction_ID, Account_No, Employee_ID,
        Transaction_Type, Amount, Balance_After, Channel, Status
    )
    VALUES
    (p_debit_transaction_id, p_from_account, p_employee_id,
     'Transfer_Out', p_amount, v_from_balance, v_channel, 'Completed'),
    (p_credit_transaction_id, p_to_account, p_employee_id,
     'Transfer_In', p_amount, v_to_balance, v_channel, 'Completed');

    INSERT INTO FUND_TRANSFER(
        Transaction_ID, From_Account_No, To_Account_No,
        Transfer_Mode, Reference_No,
        Debit_Transaction_ID, Credit_Transaction_ID
    )
    VALUES (
        p_debit_transaction_id, p_from_account, p_to_account,
        p_transfer_mode, p_reference_no,
        p_debit_transaction_id, p_credit_transaction_id
    );
END;
$$;

-- ===================================
--  OPEN ACCOUNT
-- =====================================

CREATE OR REPLACE PROCEDURE sp_open_account(
    IN p_account_no VARCHAR(20),
    IN p_cif VARCHAR(20),
    IN p_ifsc VARCHAR(20),
    IN p_nominee VARCHAR(100),
    IN p_account_type_id INTEGER,
    IN p_initial_balance NUMERIC(14,5)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_min_balance NUMERIC(14,5);
BEGIN
    IF p_initial_balance IS NULL OR p_initial_balance < 0 THEN
        RAISE EXCEPTION 'Initial balance cannot be negative';
    END IF;

    SELECT Minimum_Balance INTO v_min_balance
    FROM ACCOUNT_TYPE
    WHERE Account_Type_ID = p_account_type_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Account type does not exist';
    END IF;

    IF p_initial_balance < v_min_balance THEN
        RAISE EXCEPTION 'Initial balance is below the minimum required';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM CUSTOMER
        WHERE CIF = p_cif AND Status = 'Active'
    ) THEN
        RAISE EXCEPTION 'Customer does not exist or is inactive';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM BRANCH
        WHERE IFSC = p_ifsc AND Status = 'Active'
    ) THEN
        RAISE EXCEPTION 'Branch does not exist or is inactive';
    END IF;

    INSERT INTO ACCOUNT(
        Account_No, CIF, IFSC, Nominee, Account_Type_ID,
        Opening_Date, Status, Current_Balance
    )
    VALUES (
        p_account_no, p_cif, p_ifsc, p_nominee, p_account_type_id,
        CURRENT_DATE, 'Active', p_initial_balance
    );
END;
$$;

-- =============================
--  CHECK BALANCE
-- ==============================

CREATE OR REPLACE PROCEDURE sp_check_balance(
    IN p_account_no VARCHAR(20),
    OUT p_current_balance NUMERIC(14,5),
    OUT p_account_status VARCHAR(20)
)
LANGUAGE plpgsql
AS $$
BEGIN
    SELECT Current_Balance, Status
    INTO p_current_balance, p_account_status
    FROM ACCOUNT
    WHERE Account_No = p_account_no;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Account not found';
    END IF;
END;
$$;

-- ==================================
--   LOAN APPLY
-- ====================================

CREATE OR REPLACE PROCEDURE sp_apply_loan(
    IN p_loan_id VARCHAR(20),
    IN p_cif VARCHAR(20),
    IN p_account_no VARCHAR(20),
    IN p_loan_type_id INTEGER,
    IN p_employee_id VARCHAR(20),
    IN p_principal NUMERIC(14,5),
    IN p_interest_rate NUMERIC(7,4),
    IN p_tenure_months INTEGER,
    IN p_emi NUMERIC(14,5),
    IN p_start_date DATE,
    IN p_end_date DATE
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_principal IS NULL OR p_principal <= 0
       OR p_interest_rate IS NULL OR p_interest_rate < 0
       OR p_tenure_months IS NULL OR p_tenure_months <= 0
       OR p_emi IS NULL OR p_emi <= 0 THEN
        RAISE EXCEPTION 'Invalid loan amount, interest rate, tenure, or EMI';
    END IF;

    IF p_end_date <= p_start_date THEN
        RAISE EXCEPTION 'End date must be after start date';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM ACCOUNT
        WHERE Account_No = p_account_no
          AND CIF = p_cif
          AND Status = 'Active'
    ) THEN
        RAISE EXCEPTION 'Customer does not own an active account';
    END IF;

    INSERT INTO LOAN(
        Loan_ID, CIF, Account_No, Loan_Type_ID, Employee_ID,
        Principal_Amount, Interest_Rate, Tenure_Months, EMI_Amount,
        Remaining_Amount, Start_Date, End_Date, Loan_Status
    )
    VALUES (
        p_loan_id, p_cif, p_account_no, p_loan_type_id, p_employee_id,
        p_principal, p_interest_rate, p_tenure_months, p_emi,
        p_principal, p_start_date, p_end_date, 'Applied'
    );
END;
$$;

-- =====================================
--   LOAN APPROVE
-- =====================================

CREATE OR REPLACE PROCEDURE sp_approve_loan(
    IN p_loan_id VARCHAR(20),
    IN p_employee_id VARCHAR(20),
    IN p_decision VARCHAR(20)
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_decision NOT IN ('Approved', 'Rejected') THEN
        RAISE EXCEPTION 'Decision must be Approved or Rejected';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM EMPLOYEE
        WHERE Employee_ID = p_employee_id
          AND Status = 'Active'
          AND Role IN ('Manager', 'Admin')
    ) THEN
        RAISE EXCEPTION 'An active manager or admin is required';
    END IF;

    UPDATE LOAN
    SET Loan_Status = CASE
            WHEN p_decision = 'Approved' THEN 'Active'
            ELSE 'Rejected'
        END,
        Employee_ID = p_employee_id
    WHERE Loan_ID = p_loan_id
      AND Loan_Status = 'Applied';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Loan not found or not awaiting approval';
    END IF;
END;
$$;

-- =====================================
--  LOAN PAYMENT
-- =======================================


CREATE OR REPLACE PROCEDURE sp_loan_payment(
    IN p_payment_id VARCHAR(20),
    IN p_transaction_id VARCHAR(20),
    IN p_loan_id VARCHAR(20),
    IN p_principal_paid NUMERIC(14,5),
    IN p_interest_paid NUMERIC(14,5),
    IN p_payment_method VARCHAR(20),
    IN p_employee_id VARCHAR(20) DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_account_no VARCHAR(20);
    v_remaining NUMERIC(14,5);
    v_balance NUMERIC(14,5);
    v_total NUMERIC(14,5);
    v_channel VARCHAR(20);
BEGIN
    IF p_principal_paid IS NULL OR p_interest_paid IS NULL
       OR p_principal_paid < 0 OR p_interest_paid < 0
       OR p_principal_paid + p_interest_paid <= 0 THEN
        RAISE EXCEPTION 'Invalid payment amounts';
    END IF;

    IF p_payment_method NOT IN
       ('UPI','Internal_Transfer','Cheque','NEFT','RTGS','IMPS') THEN
        RAISE EXCEPTION 'Invalid payment method';
    END IF;

    v_total := p_principal_paid + p_interest_paid;

    v_channel := CASE
        WHEN p_payment_method = 'Internal_Transfer' THEN 'Online_Banking'
        ELSE p_payment_method
    END;

    SELECT Account_No, Remaining_Amount
    INTO v_account_no, v_remaining
    FROM LOAN
    WHERE Loan_ID = p_loan_id
      AND Loan_Status = 'Active'
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Active loan not found';
    END IF;

    IF p_principal_paid > v_remaining THEN
        RAISE EXCEPTION 'Principal payment exceeds remaining loan amount';
    END IF;

    SELECT Current_Balance INTO v_balance
    FROM ACCOUNT
    WHERE Account_No = v_account_no
      AND Status = 'Active'
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Loan account is not active';
    END IF;

    IF v_balance < v_total THEN
        RAISE EXCEPTION 'Insufficient account balance';
    END IF;

    UPDATE ACCOUNT
    SET Current_Balance = Current_Balance - v_total
    WHERE Account_No = v_account_no
    RETURNING Current_Balance INTO v_balance;

    INSERT INTO "TRANSACTION"(
        Transaction_ID, Account_No, Employee_ID,
        Transaction_Type, Amount, Balance_After, Channel, Status
    )
    VALUES (
        p_transaction_id, v_account_no, p_employee_id,
        'Loan_Payment', v_total, v_balance, v_channel, 'Completed'
    );

    UPDATE LOAN
    SET Remaining_Amount = Remaining_Amount - p_principal_paid,
        Loan_Status = CASE
            WHEN Remaining_Amount - p_principal_paid = 0 THEN 'Closed'
            ELSE 'Active'
        END
    WHERE Loan_ID = p_loan_id;

    SELECT Remaining_Amount INTO v_remaining
    FROM LOAN
    WHERE Loan_ID = p_loan_id;

    INSERT INTO LOAN_PAYMENT(
        Payment_ID, Loan_ID, Transaction_ID, Payment_Method,
        Payment_Status, Principal_Paid, Interest_Paid, Remaining_Balance
    )
    VALUES (
        p_payment_id, p_loan_id, p_transaction_id, p_payment_method,
        'Completed', p_principal_paid, p_interest_paid, v_remaining
    );
END;
$$;

-- ===============================
--  TRANSACTION HISTORY
-- ===============================

CREATE OR REPLACE PROCEDURE sp_get_transaction_history(
    IN p_account_no VARCHAR(20),
    INOUT p_result REFCURSOR
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ACCOUNT WHERE Account_No = p_account_no
    ) THEN
        RAISE EXCEPTION 'Account not found';
    END IF;

    OPEN p_result FOR
        SELECT Transaction_ID, Transaction_Type, Amount,
               Transaction_Date_Time, Balance_After, Channel, Status
        FROM "TRANSACTION"
        WHERE Account_No = p_account_no
        ORDER BY Transaction_Date_Time DESC;
END;
$$;

-- ====================================
--  ACCOUNT STATEMENT GENERATE
-- ====================================


CREATE OR REPLACE PROCEDURE sp_generate_account_statement(
    IN p_account_no VARCHAR(20),
    IN p_start_date DATE,
    IN p_end_date DATE,
    INOUT p_result REFCURSOR
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_start_date IS NULL OR p_end_date IS NULL
       OR p_start_date > p_end_date THEN
        RAISE EXCEPTION 'Invalid statement date range';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM ACCOUNT WHERE Account_No = p_account_no
    ) THEN
        RAISE EXCEPTION 'Account not found';
    END IF;

    OPEN p_result FOR
        SELECT Transaction_ID, Transaction_Type, Amount,
               Transaction_Date_Time, Balance_After, Channel, Status
        FROM "TRANSACTION"
        WHERE Account_No = p_account_no
          AND Transaction_Date_Time >= p_start_date
          AND Transaction_Date_Time < p_end_date + INTERVAL '1 day'
        ORDER BY Transaction_Date_Time;
END;
$$;


