USE stock_trading_db;

INSERT INTO sectors (sector_name) VALUES
('Technology'), ('Healthcare'), ('Banking & Finance'), ('Energy'), ('Consumer Goods');

INSERT INTO stocks (symbol, company_name, sector_id) VALUES
('TCS',        'Tata Consultancy Services', 1),
('INFY',       'Infosys Limited',           1),
('WIPRO',      'Wipro Limited',             1),
('SUNPHARMA',  'Sun Pharmaceutical',        2),
('DRREDDY',    'Dr. Reddy''s Laboratories', 2),
('HDFCBANK',   'HDFC Bank',                 3),
('ICICIBANK',  'ICICI Bank',                3),
('SBIN',       'State Bank of India',       3),
('RELIANCE',   'Reliance Industries',       4),
('ONGC',       'Oil & Natural Gas Corp',    4),
('ITC',        'ITC Limited',               5),
('HINDUNILVR', 'Hindustan Unilever',        5);

INSERT INTO users (username, email, cash_balance) VALUES
('arjun_trader',  'arjun@example.com',  100000.00),
('priya_invests', 'priya@example.com',  100000.00),
('rohan_hodler',  'rohan@example.com',  100000.00),
('neha_quant',    'neha@example.com',   100000.00);

-- One opening price per stock (stock_id order matches the list above)
INSERT INTO price_history (stock_id, price, volume, recorded_at) VALUES
(1, 3900.50, 1500, NOW()), (2, 1480.00, 2500, NOW()), (3,  460.00, 3000, NOW()),
(4, 1150.00,  800, NOW()), (5, 6100.00,  400, NOW()), (6, 1620.00, 3000, NOW()),
(7, 1100.00, 2800, NOW()), (8,  780.00, 3500, NOW()), (9, 2800.00, 1000, NOW()),
(10, 260.00, 4000, NOW()), (11, 430.00, 5000, NOW()), (12,2400.00,  900, NOW());

-- Copy the opening prices into the "current price" table
INSERT INTO latest_prices (stock_id, price, updated_at)
SELECT stock_id, price, recorded_at FROM price_history;