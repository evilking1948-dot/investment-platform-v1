import pool from '../config/database';

/**
 * FINANCIAL ARCHITECTURE:
 * Admin CAN directly edit user.balance
 * All changes are tracked in audit_logs with reason
 */

export class BalanceService {
  /**
   * Get user's current balance
   */
  static async getBalance(userId: number): Promise<number> {
    const result = await pool.query(
      'SELECT balance FROM users WHERE id = $1',
      [userId]
    );
    return parseFloat(result.rows[0]?.balance || 0);
  }

  /**
   * ADMIN: Add balance directly
   * Admin clicks "Add $5,000" button
   * users.balance = $5,000 (or + $5,000)
   */
  static async adminAddBalance(
    adminId: number,
    userId: number,
    amount: number,
    reason: string,
    ipAddress: string
  ) {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      // Get current balance
      const currentResult = await client.query(
        'SELECT balance FROM users WHERE id = $1',
        [userId]
      );
      const oldBalance = parseFloat(currentResult.rows[0]?.balance || 0);
      const newBalance = oldBalance + amount;

      // Update balance
      const updateResult = await client.query(
        'UPDATE users SET balance = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2 RETURNING *',
        [newBalance, userId]
      );

      // Log transaction
      await client.query(
        `INSERT INTO ledger_transactions (user_id, transaction_type, amount, currency, reference_id, status, description)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [userId, 'admin_add', amount, 'USD', `admin-${adminId}`, 'completed', reason]
      );

      // Create audit log
      await client.query(
        `INSERT INTO audit_logs (admin_id, action, entity_type, entity_id, old_value, new_value, reason, ip_address, timestamp)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, CURRENT_TIMESTAMP)`,
        [adminId, 'balance_added', 'user', userId, oldBalance, newBalance, reason, ipAddress]
      );

      await client.query('COMMIT');
      return updateResult.rows[0];
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * ADMIN: Deduct balance directly
   */
  static async adminDeductBalance(
    adminId: number,
    userId: number,
    amount: number,
    reason: string,
    ipAddress: string
  ) {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      // Get current balance
      const currentResult = await client.query(
        'SELECT balance FROM users WHERE id = $1',
        [userId]
      );
      const oldBalance = parseFloat(currentResult.rows[0]?.balance || 0);

      if (oldBalance < amount) {
        throw new Error('Insufficient balance');
      }

      const newBalance = oldBalance - amount;

      // Update balance
      const updateResult = await client.query(
        'UPDATE users SET balance = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2 RETURNING *',
        [newBalance, userId]
      );

      // Log transaction
      await client.query(
        `INSERT INTO ledger_transactions (user_id, transaction_type, amount, currency, reference_id, status, description)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [userId, 'admin_deduct', amount, 'USD', `admin-${adminId}`, 'completed', reason]
      );

      // Create audit log
      await client.query(
        `INSERT INTO audit_logs (admin_id, action, entity_type, entity_id, old_value, new_value, reason, ip_address, timestamp)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, CURRENT_TIMESTAMP)`,
        [adminId, 'balance_deducted', 'user', userId, oldBalance, newBalance, reason, ipAddress]
      );

      await client.query('COMMIT');
      return updateResult.rows[0];
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * ADMIN: Set balance to exact amount
   */
  static async adminSetBalance(
    adminId: number,
    userId: number,
    newBalance: number,
    reason: string,
    ipAddress: string
  ) {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      // Get current balance
      const currentResult = await client.query(
        'SELECT balance FROM users WHERE id = $1',
        [userId]
      );
      const oldBalance = parseFloat(currentResult.rows[0]?.balance || 0);

      // Update balance
      const updateResult = await client.query(
        'UPDATE users SET balance = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2 RETURNING *',
        [newBalance, userId]
      );

      // Log transaction
      const transactionType = newBalance > oldBalance ? 'admin_add' : 'admin_deduct';
      const amount = Math.abs(newBalance - oldBalance);

      await client.query(
        `INSERT INTO ledger_transactions (user_id, transaction_type, amount, currency, reference_id, status, description)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [userId, transactionType, amount, 'USD', `admin-${adminId}`, 'completed', reason]
      );

      // Create audit log
      await client.query(
        `INSERT INTO audit_logs (admin_id, action, entity_type, entity_id, old_value, new_value, reason, ip_address, timestamp)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, CURRENT_TIMESTAMP)`,
        [adminId, 'balance_set', 'user', userId, oldBalance, newBalance, reason, ipAddress]
      );

      await client.query('COMMIT');
      return updateResult.rows[0];
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }
}

/**
 * DEPOSIT SYSTEM
 */
export class DepositService {
  /**
   * Customer initiates deposit
   */
  static async createDepositRequest(
    userId: number,
    amount: number,
    method: string,
    providerName: string
  ) {
    const result = await pool.query(
      `INSERT INTO deposits (user_id, amount, currency, method, provider_name, status, created_at)
       VALUES ($1, $2, $3, $4, $5, $6, CURRENT_TIMESTAMP) RETURNING *`,
      [userId, amount, 'USD', method, providerName, 'pending']
    );
    return result.rows[0];
  }

  /**
   * ADMIN: Confirm deposit and add to balance
   */
  static async adminConfirmDeposit(
    adminId: number,
    depositId: number,
    ipAddress: string
  ) {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      // Get deposit details
      const depositResult = await client.query(
        'SELECT * FROM deposits WHERE id = $1',
        [depositId]
      );
      const deposit = depositResult.rows[0];

      // Add balance to user
      const currentBalance = await this.getUserBalance(deposit.user_id);
      const newBalance = currentBalance + deposit.amount;

      await client.query(
        'UPDATE users SET balance = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2',
        [newBalance, deposit.user_id]
      );

      // Mark deposit as confirmed
      await client.query(
        `UPDATE deposits SET status = $1, confirmed_at = CURRENT_TIMESTAMP WHERE id = $2`,
        ['confirmed', depositId]
      );

      // Log transaction
      await client.query(
        `INSERT INTO ledger_transactions (user_id, transaction_type, amount, currency, reference_id, status, description)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [deposit.user_id, 'deposit', deposit.amount, 'USD', depositId, 'completed', `Deposit confirmed`]
      );

      // Create audit log
      await client.query(
        `INSERT INTO audit_logs (admin_id, action, entity_type, entity_id, new_value, reason, ip_address, timestamp)
         VALUES ($1, $2, $3, $4, $5, $6, $7, CURRENT_TIMESTAMP)`,
        [adminId, 'deposit_confirmed', 'deposit', depositId, `+${deposit.amount}`, 'Deposit payment confirmed', ipAddress]
      );

      await client.query('COMMIT');
      return deposit;
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  private static async getUserBalance(userId: number): Promise<number> {
    const result = await pool.query(
      'SELECT balance FROM users WHERE id = $1',
      [userId]
    );
    return parseFloat(result.rows[0]?.balance || 0);
  }
}

/**
 * WITHDRAWAL SYSTEM
 */
export class WithdrawalService {
  /**
   * Customer requests withdrawal
   */
  static async requestWithdrawal(
    userId: number,
    amount: number,
    destinationId: string
  ) {
    const result = await pool.query(
      `INSERT INTO withdrawals (user_id, amount, currency, destination_id, status, created_at)
       VALUES ($1, $2, $3, $4, $5, CURRENT_TIMESTAMP) RETURNING *`,
      [userId, amount, 'USD', destinationId, 'pending']
    );
    return result.rows[0];
  }

  /**
   * Verify 2FA
   */
  static async verify2FA(withdrawalId: number) {
    const result = await pool.query(
      `UPDATE withdrawals SET two_factor_verified = TRUE, status = $1 WHERE id = $2 RETURNING *`,
      ['2fa_verified', withdrawalId]
    );
    return result.rows[0];
  }

  /**
   * Check KYC status
   */
  static async checkKYCStatus(withdrawalId: number, userId: number) {
    const kycResult = await pool.query(
      'SELECT status FROM kyc_verifications WHERE user_id = $1',
      [userId]
    );
    const kycStatus = kycResult.rows[0]?.status || 'not_verified';

    const result = await pool.query(
      `UPDATE withdrawals SET kyc_status = $1, status = $2 WHERE id = $3 RETURNING *`,
      [kycStatus, kycStatus === 'verified' ? 'kyc_checked' : 'rejected', withdrawalId]
    );
    return result.rows[0];
  }

  /**
   * AML screening
   */
  static async screenAML(withdrawalId: number, riskLevel: string = 'low') {
    const result = await pool.query(
      `UPDATE withdrawals SET aml_risk_level = $1, status = $2 WHERE id = $3 RETURNING *`,
      [riskLevel, riskLevel === 'clear' ? 'aml_screened' : 'rejected', withdrawalId]
    );
    return result.rows[0];
  }

  /**
   * Verify available balance
   */
  static async verifyBalance(withdrawalId: number, userId: number) {
    const withdrawalResult = await pool.query(
      'SELECT amount FROM withdrawals WHERE id = $1',
      [withdrawalId]
    );
    const amount = withdrawalResult.rows[0].amount;

    const balanceResult = await pool.query(
      'SELECT balance FROM users WHERE id = $1',
      [userId]
    );
    const currentBalance = parseFloat(balanceResult.rows[0].balance);

    const isAvailable = currentBalance >= amount;

    const result = await pool.query(
      `UPDATE withdrawals SET balance_available = $1, status = $2 WHERE id = $3 RETURNING *`,
      [isAvailable, isAvailable ? 'balance_verified' : 'rejected', withdrawalId]
    );
    return result.rows[0];
  }

  /**
   * ADMIN: Approve withdrawal
   */
  static async adminApproveWithdrawal(
    adminId: number,
    withdrawalId: number,
    ipAddress: string
  ) {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      const result = await client.query(
        `UPDATE withdrawals SET approved_by = $1, approved_at = CURRENT_TIMESTAMP, status = $2 WHERE id = $3 RETURNING *`,
        [adminId, 'approved', withdrawalId]
      );

      // Create audit log
      await client.query(
        `INSERT INTO audit_logs (admin_id, action, entity_type, entity_id, new_value, ip_address, timestamp)
         VALUES ($1, $2, $3, $4, $5, $6, CURRENT_TIMESTAMP)`,
        [adminId, 'withdrawal_approved', 'withdrawal', withdrawalId, 'approved', ipAddress]
      );

      await client.query('COMMIT');
      return result.rows[0];
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * ADMIN: Reject withdrawal
   */
  static async adminRejectWithdrawal(
    adminId: number,
    withdrawalId: number,
    reason: string,
    ipAddress: string
  ) {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      const result = await client.query(
        `UPDATE withdrawals SET approved_by = $1, approved_at = CURRENT_TIMESTAMP, status = $2 WHERE id = $3 RETURNING *`,
        [adminId, 'rejected', withdrawalId]
      );

      // Create audit log
      await client.query(
        `INSERT INTO audit_logs (admin_id, action, entity_type, entity_id, new_value, reason, ip_address, timestamp)
         VALUES ($1, $2, $3, $4, $5, $6, $7, CURRENT_TIMESTAMP)`,
        [adminId, 'withdrawal_rejected', 'withdrawal', withdrawalId, 'rejected', reason, ipAddress]
      );

      await client.query('COMMIT');
      return result.rows[0];
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * ADMIN: Complete withdrawal (deduct from balance)
   */
  static async adminCompleteWithdrawal(
    adminId: number,
    withdrawalId: number,
    providerReference: string,
    ipAddress: string
  ) {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      // Get withdrawal details
      const withdrawalResult = await client.query(
        'SELECT * FROM withdrawals WHERE id = $1',
        [withdrawalId]
      );
      const withdrawal = withdrawalResult.rows[0];

      // Get current balance
      const balanceResult = await client.query(
        'SELECT balance FROM users WHERE id = $1',
        [withdrawal.user_id]
      );
      const currentBalance = parseFloat(balanceResult.rows[0].balance);
      const newBalance = currentBalance - withdrawal.amount;

      // Update balance
      await client.query(
        'UPDATE users SET balance = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2',
        [newBalance, withdrawal.user_id]
      );

      // Update withdrawal status
      const result = await client.query(
        `UPDATE withdrawals SET status = $1, provider_reference = $2, completed_at = CURRENT_TIMESTAMP WHERE id = $3 RETURNING *`,
        ['completed', providerReference, withdrawalId]
      );

      // Log transaction
      await client.query(
        `INSERT INTO ledger_transactions (user_id, transaction_type, amount, currency, reference_id, status, description)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [withdrawal.user_id, 'withdrawal', withdrawal.amount, 'USD', withdrawalId, 'completed', `Withdrawal completed`]
      );

      // Create audit log
      await client.query(
        `INSERT INTO audit_logs (admin_id, action, entity_type, entity_id, old_value, new_value, reason, ip_address, timestamp)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, CURRENT_TIMESTAMP)`,
        [
          adminId,
          'withdrawal_completed',
          'user',
          withdrawal.user_id,
          currentBalance,
          newBalance,
          `Withdrawal of $${withdrawal.amount} completed`,
          ipAddress,
        ]
      );

      await client.query('COMMIT');
      return result.rows[0];
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }
}

/**
 * CRYPTO PORTFOLIO
 */
export class PortfolioService {
  /**
   * Get portfolio valuation
   */
  static async getPortfolioValuation(userId: number) {
    const result = await pool.query(
      `SELECT 
        cp.asset,
        cp.quantity,
        cp.average_acquisition_price,
        cp.total_acquisition_cost,
        mp.current_price,
        (cp.quantity * mp.current_price) as current_value,
        (cp.quantity * mp.current_price - cp.total_acquisition_cost) as unrealized_pnl,
        ((cp.quantity * mp.current_price - cp.total_acquisition_cost) / cp.total_acquisition_cost * 100) as unrealized_pnl_percent,
        cp.created_at
       FROM crypto_positions cp
       JOIN market_prices mp ON cp.asset = mp.asset
       WHERE cp.user_id = $1 AND cp.status = 'active'`,
      [userId]
    );
    return result.rows;
  }

  /**
   * Get portfolio metrics
   */
  static async getPortfolioMetrics(userId: number) {
    const result = await pool.query(
      `SELECT 
        SUM(cp.quantity * mp.current_price) as total_portfolio_value,
        SUM(cp.total_acquisition_cost) as total_invested,
        SUM(cp.quantity * mp.current_price - cp.total_acquisition_cost) as total_unrealized_pnl,
        (SUM(cp.quantity * mp.current_price - cp.total_acquisition_cost) / SUM(cp.total_acquisition_cost) * 100) as total_pnl_percent
       FROM crypto_positions cp
       JOIN market_prices mp ON cp.asset = mp.asset
       WHERE cp.user_id = $1 AND cp.status = 'active'`,
      [userId]
    );
    return result.rows[0] || {};
  }
}
