-- FINANCIAL ARCHITECTURE: ADMIN-CONTROLLED BALANCE SYSTEM

-- Users table - HAS DIRECT BALANCE COLUMN (editable by admin)
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  email VARCHAR(255) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  balance DECIMAL(15, 2) DEFAULT 0.00,
  status VARCHAR(50) DEFAULT 'pending',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  last_login_at TIMESTAMP
);

-- Customer Profiles
CREATE TABLE customer_profiles (
  id SERIAL PRIMARY KEY,
  user_id INTEGER UNIQUE NOT NULL REFERENCES users(id),
  first_name VARCHAR(255) NOT NULL,
  last_name VARCHAR(255) NOT NULL,
  date_of_birth DATE NOT NULL,
  country VARCHAR(2) NOT NULL,
  address TEXT NOT NULL,
  phone VARCHAR(20),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- KYC Verifications
CREATE TABLE kyc_verifications (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id),
  status VARCHAR(50) DEFAULT 'pending',
  provider VARCHAR(100),
  verification_reference VARCHAR(255),
  reviewed_by INTEGER REFERENCES users(id),
  reviewed_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Financial Accounts
CREATE TABLE financial_accounts (
  id SERIAL PRIMARY KEY,
  user_id INTEGER UNIQUE NOT NULL REFERENCES users(id),
  currency VARCHAR(3) DEFAULT 'USD',
  account_type VARCHAR(50) DEFAULT 'primary',
  status VARCHAR(50) DEFAULT 'active',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- TRANSACTION LEDGER - tracks all history (for reference only)
CREATE TABLE ledger_transactions (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id),
  transaction_type VARCHAR(50) NOT NULL,
  amount DECIMAL(15, 2) NOT NULL,
  currency VARCHAR(3) DEFAULT 'USD',
  reference_id VARCHAR(255),
  status VARCHAR(50) DEFAULT 'completed',
  description TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- DEPOSIT SYSTEM
CREATE TABLE deposits (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id),
  amount DECIMAL(15, 2) NOT NULL,
  currency VARCHAR(3) DEFAULT 'USD',
  method VARCHAR(50),
  provider_name VARCHAR(100),
  provider_reference VARCHAR(255),
  status VARCHAR(50) DEFAULT 'pending',
  confirmed_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- CRYPTO INVESTMENT PLANS
CREATE TABLE investment_plans (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id),
  plan_name VARCHAR(100) NOT NULL,
  category VARCHAR(50) NOT NULL, -- crypto, stocks, gold, trading, real_estate
  amount DECIMAL(15, 2) NOT NULL,
  status VARCHAR(50) DEFAULT 'active',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- CRYPTO POSITIONS - actual holdings
CREATE TABLE crypto_positions (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id),
  asset VARCHAR(50) NOT NULL,
  quantity DECIMAL(20, 8) NOT NULL,
  average_acquisition_price DECIMAL(15, 8) NOT NULL,
  total_acquisition_cost DECIMAL(15, 2) NOT NULL,
  custody_reference VARCHAR(255),
  status VARCHAR(50) DEFAULT 'active',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT positive_quantity CHECK (quantity > 0)
);

-- REALIZED P/L TRACKING
CREATE TABLE realized_pnl (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id),
  asset VARCHAR(50) NOT NULL,
  quantity_sold DECIMAL(20, 8) NOT NULL,
  sale_price DECIMAL(15, 8) NOT NULL,
  average_cost_per_unit DECIMAL(15, 8) NOT NULL,
  gross_proceeds DECIMAL(15, 2) NOT NULL,
  gross_cost DECIMAL(15, 2) NOT NULL,
  realized_pnl DECIMAL(15, 2) NOT NULL,
  order_reference VARCHAR(255),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- MARKET PRICES
CREATE TABLE market_prices (
  id SERIAL PRIMARY KEY,
  asset VARCHAR(50) NOT NULL,
  currency VARCHAR(3) DEFAULT 'USD',
  current_price DECIMAL(15, 8) NOT NULL,
  price_source VARCHAR(100),
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(asset, currency)
);

-- CRYPTO PORTFOLIO VALUATION (calculated real-time)
CREATE VIEW portfolio_valuation AS
SELECT 
  cp.user_id,
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
WHERE cp.status = 'active';

-- WITHDRAWALS
CREATE TABLE withdrawals (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id),
  amount DECIMAL(15, 2) NOT NULL,
  currency VARCHAR(3) DEFAULT 'USD',
  destination_id VARCHAR(255),
  status VARCHAR(50) DEFAULT 'pending',
  two_factor_verified BOOLEAN DEFAULT FALSE,
  kyc_status VARCHAR(50),
  aml_risk_level VARCHAR(50),
  balance_available BOOLEAN DEFAULT FALSE,
  approved_by INTEGER REFERENCES users(id),
  approved_at TIMESTAMP,
  provider_reference VARCHAR(255),
  provider_name VARCHAR(100),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  completed_at TIMESTAMP
);

-- AUDIT LOG - tracks all admin balance changes
CREATE TABLE audit_logs (
  id SERIAL PRIMARY KEY,
  admin_id INTEGER REFERENCES users(id),
  action VARCHAR(255) NOT NULL,
  entity_type VARCHAR(50),
  entity_id INTEGER,
  old_value TEXT,
  new_value TEXT,
  reason TEXT,
  ip_address VARCHAR(50),
  timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT audit_immutable CHECK (timestamp IS NOT NULL)
);

-- Investment Products
CREATE TABLE investment_products (
  id SERIAL PRIMARY KEY,
  category VARCHAR(50) NOT NULL,
  name VARCHAR(255) NOT NULL,
  description TEXT,
  minimum_amount DECIMAL(15, 2) NOT NULL,
  maximum_amount DECIMAL(15, 2),
  status VARCHAR(50) DEFAULT 'draft',
  risk_level VARCHAR(50),
  liquidity_terms VARCHAR(255),
  fees DECIMAL(5, 2),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Admin Roles
CREATE TABLE admin_roles (
  id SERIAL PRIMARY KEY,
  user_id INTEGER UNIQUE NOT NULL REFERENCES users(id),
  role VARCHAR(50) NOT NULL,
  permissions JSONB,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2FA Setup
CREATE TABLE two_factor_auth (
  id SERIAL PRIMARY KEY,
  user_id INTEGER UNIQUE NOT NULL REFERENCES users(id),
  secret VARCHAR(255),
  enabled BOOLEAN DEFAULT FALSE,
  backup_codes TEXT[],
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_balance ON users(balance);
CREATE INDEX idx_ledger_user_id ON ledger_transactions(user_id);
CREATE INDEX idx_crypto_positions_user_id ON crypto_positions(user_id);
CREATE INDEX idx_crypto_positions_asset ON crypto_positions(asset);
CREATE INDEX idx_withdrawals_user_id ON withdrawals(user_id);
CREATE INDEX idx_withdrawals_status ON withdrawals(status);
CREATE INDEX idx_deposits_user_id ON deposits(user_id);
CREATE INDEX idx_audit_logs_admin_id ON audit_logs(admin_id);
CREATE INDEX idx_audit_logs_entity ON audit_logs(entity_type, entity_id);
CREATE INDEX idx_market_prices_asset ON market_prices(asset);
