DROP DATABASE IF EXISTS stock_trading_db;
CREATE DATABASE stock_trading_db;
USE stock_trading_db;

CREATE TABLE users (
    user_id      INT AUTO_INCREMENT PRIMARY KEY,
    username     VARCHAR(50)  NOT NULL UNIQUE,
    email        VARCHAR(100) NOT NULL UNIQUE,
    cash_balance DECIMAL(15,2) NOT NULL DEFAULT 100000.00 CHECK (cash_balance >= 0),
    created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE sectors (
    sector_id   INT AUTO_INCREMENT PRIMARY KEY,
    sector_name VARCHAR(50) NOT NULL UNIQUE
) ENGINE=InnoDB;

CREATE TABLE stocks (
    stock_id     INT AUTO_INCREMENT PRIMARY KEY,
    symbol       VARCHAR(15)  NOT NULL UNIQUE,
    company_name VARCHAR(100) NOT NULL,
    sector_id    INT NOT NULL,
    CONSTRAINT fk_stocks_sector FOREIGN KEY (sector_id)
        REFERENCES sectors(sector_id) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- Every price tick ever recorded (grows quickly)
CREATE TABLE price_history (
    price_id    BIGINT AUTO_INCREMENT PRIMARY KEY,
    stock_id    INT NOT NULL,
    price       DECIMAL(10,2) NOT NULL,
    volume      INT DEFAULT 0,
    recorded_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_price_stock FOREIGN KEY (stock_id)
        REFERENCES stocks(stock_id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE INDEX idx_price_stock_time ON price_history (stock_id, recorded_at);

-- Exactly one row per stock: the current price (fast lookups)
CREATE TABLE latest_prices (
    stock_id   INT PRIMARY KEY,
    price      DECIMAL(10,2) NOT NULL,
    updated_at DATETIME NOT NULL,
    CONSTRAINT fk_latest_stock FOREIGN KEY (stock_id) REFERENCES stocks(stock_id)
) ENGINE=InnoDB;

CREATE TABLE trades (
    trade_id        BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id         INT NOT NULL,
    stock_id        INT NOT NULL,
    trade_type      ENUM('BUY','SELL') NOT NULL,
    quantity        INT NOT NULL CHECK (quantity > 0),
    execution_price DECIMAL(10,2) NOT NULL,
    realized_pnl    DECIMAL(15,2) NULL,          -- filled only for SELL trades
    executed_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_trades_user  FOREIGN KEY (user_id)  REFERENCES users(user_id)   ON DELETE CASCADE,
    CONSTRAINT fk_trades_stock FOREIGN KEY (stock_id) REFERENCES stocks(stock_id) ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE holdings (
    user_id           INT NOT NULL,
    stock_id          INT NOT NULL,
    quantity          INT NOT NULL CHECK (quantity >= 0),
    average_buy_price DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (user_id, stock_id),
    CONSTRAINT fk_holdings_user  FOREIGN KEY (user_id)  REFERENCES users(user_id)   ON DELETE CASCADE,
    CONSTRAINT fk_holdings_stock FOREIGN KEY (stock_id) REFERENCES stocks(stock_id) ON DELETE RESTRICT
) ENGINE=InnoDB;