USE stock_trading_db;
DELIMITER $$

CREATE PROCEDURE execute_buy_order(
    IN  p_user_id  INT,
    IN  p_stock_id INT,
    IN  p_quantity INT,
    OUT p_status   VARCHAR(80)
)
proc: BEGIN
    DECLARE v_cash    DECIMAL(15,2);
    DECLARE v_price   DECIMAL(10,2);
    DECLARE v_cost    DECIMAL(15,2);
    DECLARE v_old_qty INT DEFAULT 0;
    DECLARE v_old_avg DECIMAL(10,2) DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_status = 'ERROR: transaction rolled back';
    END;

    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        SET p_status = 'FAILED: Quantity must be positive';
        LEAVE proc;
    END IF;

    START TRANSACTION;

    -- 1. Lock the user's row first: this serializes all orders from the same user
    SET v_cash = NULL;
    SELECT cash_balance INTO v_cash FROM users WHERE user_id = p_user_id FOR UPDATE;
    IF v_cash IS NULL THEN
        ROLLBACK; SET p_status = 'FAILED: Unknown user'; LEAVE proc;
    END IF;

    -- 2. Current price
    SET v_price = NULL;
    SELECT price INTO v_price FROM latest_prices WHERE stock_id = p_stock_id;
    IF v_price IS NULL THEN
        ROLLBACK; SET p_status = 'FAILED: No price available'; LEAVE proc;
    END IF;

    SET v_cost = v_price * p_quantity;

    -- 3. Enough cash?
    IF v_cash < v_cost THEN
        ROLLBACK; SET p_status = 'FAILED: Insufficient funds'; LEAVE proc;
    END IF;

    -- 4. Deduct cash, write ledger row
    UPDATE users SET cash_balance = cash_balance - v_cost WHERE user_id = p_user_id;
    INSERT INTO trades (user_id, stock_id, trade_type, quantity, execution_price)
    VALUES (p_user_id, p_stock_id, 'BUY', p_quantity, v_price);

    -- 5. Create or grow the position (weighted average buy price)
    SELECT quantity, average_buy_price INTO v_old_qty, v_old_avg
    FROM holdings WHERE user_id = p_user_id AND stock_id = p_stock_id FOR UPDATE;

    IF v_old_qty = 0 THEN
        INSERT INTO holdings (user_id, stock_id, quantity, average_buy_price)
        VALUES (p_user_id, p_stock_id, p_quantity, v_price)
        ON DUPLICATE KEY UPDATE quantity = p_quantity, average_buy_price = v_price;
    ELSE
        UPDATE holdings
        SET average_buy_price = (v_old_qty * v_old_avg + v_cost) / (v_old_qty + p_quantity),
            quantity = v_old_qty + p_quantity
        WHERE user_id = p_user_id AND stock_id = p_stock_id;
    END IF;

    COMMIT;
    SET p_status = 'SUCCESS';
END$$

CREATE PROCEDURE execute_sell_order(
    IN  p_user_id  INT,
    IN  p_stock_id INT,
    IN  p_quantity INT,
    OUT p_status   VARCHAR(80)
)
proc: BEGIN
    DECLARE v_cash     DECIMAL(15,2);
    DECLARE v_qty      INT DEFAULT 0;
    DECLARE v_avg      DECIMAL(10,2) DEFAULT 0;
    DECLARE v_price    DECIMAL(10,2);
    DECLARE v_proceeds DECIMAL(15,2);
    DECLARE v_pnl      DECIMAL(15,2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_status = 'ERROR: transaction rolled back';
    END;

    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        SET p_status = 'FAILED: Quantity must be positive';
        LEAVE proc;
    END IF;

    START TRANSACTION;

    -- Same lock order as the buy procedure (user first), so they can't deadlock
    SET v_cash = NULL;
    SELECT cash_balance INTO v_cash FROM users WHERE user_id = p_user_id FOR UPDATE;
    IF v_cash IS NULL THEN
        ROLLBACK; SET p_status = 'FAILED: Unknown user'; LEAVE proc;
    END IF;

    SELECT quantity, average_buy_price INTO v_qty, v_avg
    FROM holdings WHERE user_id = p_user_id AND stock_id = p_stock_id FOR UPDATE;

    IF v_qty < p_quantity THEN
        ROLLBACK; SET p_status = 'FAILED: Not enough shares'; LEAVE proc;
    END IF;

    SET v_price = NULL;
    SELECT price INTO v_price FROM latest_prices WHERE stock_id = p_stock_id;
    IF v_price IS NULL THEN
        ROLLBACK; SET p_status = 'FAILED: No price available'; LEAVE proc;
    END IF;

    SET v_proceeds = v_price * p_quantity;
    SET v_pnl      = (v_price - v_avg) * p_quantity;      -- realized profit or loss

    UPDATE users SET cash_balance = cash_balance + v_proceeds WHERE user_id = p_user_id;
    INSERT INTO trades (user_id, stock_id, trade_type, quantity, execution_price, realized_pnl)
    VALUES (p_user_id, p_stock_id, 'SELL', p_quantity, v_price, v_pnl);

    IF v_qty = p_quantity THEN
        DELETE FROM holdings WHERE user_id = p_user_id AND stock_id = p_stock_id;
    ELSE
        UPDATE holdings SET quantity = quantity - p_quantity
        WHERE user_id = p_user_id AND stock_id = p_stock_id;
    END IF;

    COMMIT;
    SET p_status = 'SUCCESS';
END$$

DELIMITER ;