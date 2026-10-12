USE stock_trading_db;

-- What each user owns, valued at the current price
CREATE OR REPLACE VIEW portfolio_summary AS
SELECT h.user_id, u.username, s.stock_id, s.symbol, s.company_name, s.sector_id,
       h.quantity, h.average_buy_price, lp.price AS current_price,
       ROUND(h.quantity * h.average_buy_price, 2)                           AS total_investment,
       ROUND(h.quantity * lp.price, 2)                                      AS current_value,
       ROUND((lp.price - h.average_buy_price) * h.quantity, 2)              AS unrealized_pnl,
       ROUND((lp.price - h.average_buy_price) / h.average_buy_price * 100, 2) AS return_percentage
FROM holdings h
JOIN users u         ON u.user_id  = h.user_id
JOIN stocks s        ON s.stock_id = h.stock_id
JOIN latest_prices lp ON lp.stock_id = h.stock_id
WHERE h.quantity > 0;

-- Net worth = cash + stock value; ranked with a window function
CREATE OR REPLACE VIEW leaderboard AS
SELECT u.user_id, u.username, u.cash_balance,
       COALESCE(v.stock_value, 0) AS stock_portfolio_value,
       ROUND(u.cash_balance + COALESCE(v.stock_value, 0), 2) AS total_net_worth,
       ROUND((u.cash_balance + COALESCE(v.stock_value, 0) - 100000) / 100000 * 100, 2) AS return_pct,
       DENSE_RANK() OVER (ORDER BY u.cash_balance + COALESCE(v.stock_value, 0) DESC) AS `rank`
FROM users u
LEFT JOIN (SELECT user_id, SUM(current_value) AS stock_value
           FROM portfolio_summary GROUP BY user_id) v ON v.user_id = u.user_id;

-- Today's open / high / low / current / volume per stock
CREATE OR REPLACE VIEW stock_statistics AS
SELECT s.stock_id, s.symbol, s.company_name,
       lp.price AS current_price,
       COALESCE((SELECT p.price FROM price_history p
                 WHERE p.stock_id = s.stock_id AND p.recorded_at >= CURDATE()
                 ORDER BY p.recorded_at, p.price_id LIMIT 1), lp.price) AS today_open,
       COALESCE(d.today_high, lp.price) AS today_high,
       COALESCE(d.today_low,  lp.price) AS today_low,
       COALESCE(d.total_volume, 0)      AS total_volume
FROM stocks s
JOIN latest_prices lp ON lp.stock_id = s.stock_id
LEFT JOIN (SELECT stock_id, MAX(price) AS today_high, MIN(price) AS today_low,
                  SUM(volume) AS total_volume
           FROM price_history WHERE recorded_at >= CURDATE()
           GROUP BY stock_id) d ON d.stock_id = s.stock_id;