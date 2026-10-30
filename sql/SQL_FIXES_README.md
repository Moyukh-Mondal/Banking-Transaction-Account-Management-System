# Corrected PostgreSQL SQL pack

These files implement the SQL fixes for the uploaded Banking Transaction & Account Management System.

## Execution order (fresh development database)

1. `00_tables_fixed.sql` — creates the schema and supporting indexes. Run only on an empty database.
2. `01_triggers_fixed.sql` — installs corrected triggers; safe to re-run on the same schema because triggers are dropped before recreation.
3. `02_procedures_fixed.sql` — installs backend-compatible procedures.
4. `03_dummy_data_fixed.sql` — optional seed data. Run exactly once, only in an empty/disposable database.
5. `04_verify_fixed.sql` — read-only integrity checks.

## Existing database

If the tables already exist, do **not** run `00_tables_fixed.sql`. Back up first, then run `05_migrate_existing_schema.sql`, `01_triggers_fixed.sql`, `02_procedures_fixed.sql`, and `04_verify_fixed.sql` in that order. Run the dummy seed only if the tables are empty.

The scripts are not intended to be run against a live/production banking database. Do not run the schema file over existing tables. Back up any database before applying migrations.

## Fixes included

- `LOAN.Employee_ID` is nullable while a loan is awaiting a decision; it is assigned by the approval/rejection procedure.
- IFSC, MICR, PIN, PAN, Aadhaar-shaped identifier and loan-date checks are added to the schema. Seed identifiers are fictional and must not be treated as real banking identifiers.
- Supporting indexes are added for foreign keys, account transaction history, loan lookups, and audit chronology.
- Audit JSON uses PostgreSQL's actual lowercase keys for unquoted columns and excludes `password_hash` from audit data.
- Trigger installation is repeatable without duplicate-trigger errors.
- Deposit/withdrawal/transfer/loan-payment procedures do not directly update account balances; the transaction trigger is the single balance writer. This avoids double updates.
- Transfers lock source and destination accounts in a consistent order, insert both ledger rows, and create the transfer record in one atomic procedure call.
- Account-opening records its opening funds as a deposit transaction rather than inserting a non-zero balance without a ledger row.
- Loan type/account type IDs use the schema's `VARCHAR` IDs. Loan applications can await review without an employee assigned. Approval follows the legal status path `Applied -> Approved -> Active`; rejection follows `Applied -> Rejected`.
- Loan payments lock the active loan and use the transaction/payment triggers for balance and principal updates.
- Original read procedures (`sp_check_balance`, `sp_get_transaction_history`, `sp_generate_account_statement`) are retained with consistent identifier casing.

## Important validation caveat

Python syntax was checked earlier, but a PostgreSQL server/client was not available in this environment. These SQL files have been corrected by static review and have **not** been executed against a live PostgreSQL instance. Run them in a disposable database first and review the output from `04_verify_fixed.sql`.

The dummy login rows intentionally use placeholder password strings. Replace them with valid Argon2 hashes before testing API login.
