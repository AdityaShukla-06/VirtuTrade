-- Run ONCE per database (local MySQL and Aiven).
USE stock_trading_db;

ALTER TABLE users ADD COLUMN password_hash VARCHAR(255) NULL;

CREATE TABLE IF NOT EXISTS sessions (
    token CHAR(64) PRIMARY KEY,
    user_id INT NOT NULL,
    expires_at DATETIME NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(user_id)
) ENGINE=InnoDB;