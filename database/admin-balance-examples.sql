-- ADMIN BALANCE CONTROL EXAMPLES

-- Example 1: Admin adds $5,000 to user's balance
SELECT * FROM users WHERE id = 1;
-- Before: balance = $2,450.00

UPDATE users SET balance = 7450.00 WHERE id = 1;
-- After: balance = $7,450.00

INSERT INTO ledger_transactions (user_id, transaction_type, amount, currency, reference_id, status, description)
VALUES (1, 'admin_add', 5000.00, 'USD', 'admin-42', 'completed', 'Customer deposit verified');

INSERT INTO audit_logs (admin_id, action, entity_type, entity_id, old_value, new_value, reason, ip_address, timestamp)
VALUES (42, 'balance_added', 'user', 1, '2450.00', '7450.00', 'Customer deposit verified', '192.168.1.100', CURRENT_TIMESTAMP);

---

-- Example 2: Admin sets balance to exact amount
UPDATE users SET balance = 10000.00 WHERE id = 2;

INSERT INTO audit_logs (admin_id, action, entity_type, entity_id, old_value, new_value, reason, ip_address, timestamp)
VALUES (42, 'balance_set', 'user', 2, '5230.50', '10000.00', 'Correction for failed transaction', '192.168.1.100', CURRENT_TIMESTAMP);

---

-- Example 3: Admin deducts balance (withdrawal processing)
SELECT * FROM users WHERE id = 1;
-- balance = $7,450.00

UPDATE users SET balance = 6450.00 WHERE id = 1;
-- balance = $6,450.00

INSERT INTO ledger_transactions (user_id, transaction_type, amount, currency, reference_id, status, description)
VALUES (1, 'admin_deduct', 1000.00, 'USD', 'withdrawal-123', 'completed', 'Withdrawal WD-123 processed');

INSERT INTO audit_logs (admin_id, action, entity_type, entity_id, old_value, new_value, reason, ip_address, timestamp)
VALUES (42, 'balance_deducted', 'user', 1, '7450.00', '6450.00', 'Withdrawal WD-123 to bank account', '192.168.1.100', CURRENT_TIMESTAMP);

---

-- Example 4: View all balance changes for a customer
SELECT * FROM audit_logs WHERE entity_type = 'user' AND entity_id = 1 ORDER BY timestamp DESC;

-- Result:
-- ID   | Admin | Action          | Old Value | New Value | Reason                           | IP
-- 1001 | 42    | balance_added   | 2450.00   | 7450.00   | Customer deposit verified        | 192.168.1.100
-- 1002 | 42    | balance_deducted| 7450.00   | 6450.00   | Withdrawal WD-123 to bank        | 192.168.1.100
-- 1003 | 42    | balance_set     | 6450.00   | 5450.00   | Correction for duplicate charge  | 192.168.1.100

---

-- Example 5: View transaction ledger for customer
SELECT * FROM ledger_transactions WHERE user_id = 1 ORDER BY created_at DESC;

-- Result:
-- ID | User | Type            | Amount  | Reference | Description
-- 1  | 1    | admin_add       | 5000.00 | admin-42  | Customer deposit verified
-- 2  | 1    | admin_deduct    | 1000.00 | withdrawal-123 | Withdrawal WD-123 processed

---

-- Example 6: Admin views pending withdrawals and approves/rejects
SELECT id, user_id, amount, status, created_at FROM withdrawals WHERE status = 'pending' ORDER BY created_at ASC;

-- Admin approves withdrawal
UPDATE withdrawals SET approved_by = 42, approved_at = CURRENT_TIMESTAMP, status = 'approved' WHERE id = 1;

INSERT INTO audit_logs (admin_id, action, entity_type, entity_id, new_value, ip_address, timestamp)
VALUES (42, 'withdrawal_approved', 'withdrawal', 1, 'approved', '192.168.1.100', CURRENT_TIMESTAMP);

-- Admin completes withdrawal (deducts balance)
UPDATE users SET balance = balance - 1000.00 WHERE id = 1;  -- Quick deduction

UPDATE withdrawals SET status = 'completed', provider_reference = 'ACH-654321', completed_at = CURRENT_TIMESTAMP WHERE id = 1;

INSERT INTO ledger_transactions (user_id, transaction_type, amount, currency, reference_id, status, description)
VALUES (1, 'withdrawal', 1000.00, 'USD', 1, 'completed', 'Withdrawal completed');

INSERT INTO audit_logs (admin_id, action, entity_type, entity_id, old_value, new_value, reason, ip_address, timestamp)
VALUES (42, 'withdrawal_completed', 'user', 1, '7450.00', '6450.00', 'Withdrawal WD-1 processed', '192.168.1.100', CURRENT_TIMESTAMP);

---

-- Example 7: Admin rejects withdrawal
UPDATE withdrawals SET approved_by = 42, approved_at = CURRENT_TIMESTAMP, status = 'rejected' WHERE id = 2;

INSERT INTO audit_logs (admin_id, action, entity_type, entity_id, new_value, reason, ip_address, timestamp)
VALUES (42, 'withdrawal_rejected', 'withdrawal', 2, 'rejected', 'KYC verification incomplete', '192.168.1.100', CURRENT_TIMESTAMP);

---

-- Example 8: Admin confirms deposit
SELECT * FROM deposits WHERE id = 1;
-- status = 'pending'

UPDATE users SET balance = balance + 5000.00 WHERE id = 1;  -- Add deposit amount

UPDATE deposits SET status = 'confirmed', confirmed_at = CURRENT_TIMESTAMP WHERE id = 1;

INSERT INTO ledger_transactions (user_id, transaction_type, amount, currency, reference_id, status, description)
VALUES (1, 'deposit', 5000.00, 'USD', 1, 'completed', 'Deposit confirmed');

INSERT INTO audit_logs (admin_id, action, entity_type, entity_id, new_value, reason, ip_address, timestamp)
VALUES (42, 'deposit_confirmed', 'deposit', 1, '+5000.00', 'Deposit payment confirmed', '192.168.1.100', CURRENT_TIMESTAMP);

---

-- Example 9: Full withdrawal process flow
-- Step 1: Customer requests withdrawal
INSERT INTO withdrawals (user_id, amount, currency, destination_id, status) 
VALUES (1, 1000.00, 'USD', 'bank-xxx', 'pending');

-- Step 2: 2FA verification
UPDATE withdrawals SET two_factor_verified = TRUE, status = '2fa_verified' WHERE id = 1;

-- Step 3: KYC check
UPDATE withdrawals SET kyc_status = 'verified', status = 'kyc_checked' WHERE id = 1;

-- Step 4: AML screening
UPDATE withdrawals SET aml_risk_level = 'low', status = 'aml_screened' WHERE id = 1;

-- Step 5: Balance verification
UPDATE withdrawals SET balance_available = TRUE, status = 'balance_verified' WHERE id = 1;

-- Step 6: Ready for admin review
-- Status = 'balance_verified' (waiting for admin approval)

-- Step 7: Admin approves
UPDATE withdrawals SET approved_by = 42, approved_at = CURRENT_TIMESTAMP, status = 'approved' WHERE id = 1;

-- Step 8: Admin processes withdrawal (completes and deducts balance)
UPDATE users SET balance = balance - 1000.00 WHERE id = 1;
UPDATE withdrawals SET status = 'completed', provider_reference = 'ACH-123', completed_at = CURRENT_TIMESTAMP WHERE id = 1;

INSERT INTO ledger_transactions (user_id, transaction_type, amount, currency, reference_id, status, description)
VALUES (1, 'withdrawal', 1000.00, 'USD', 1, 'completed', 'Withdrawal WD-1 completed');

INSERT INTO audit_logs (admin_id, action, entity_type, entity_id, old_value, new_value, reason, ip_address, timestamp)
VALUES (42, 'withdrawal_completed', 'user', 1, '6450.00', '5450.00', 'Withdrawal WD-1 to bank', '192.168.1.100', CURRENT_TIMESTAMP);

-- After 4 business days, withdrawal is considered complete
