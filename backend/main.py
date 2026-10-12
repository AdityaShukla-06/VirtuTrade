from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
import mysql.connector

import os, threading
from contextlib import asynccontextmanager
from fastapi.staticfiles import StaticFiles
from simulator_thread import run_simulator

stop_event = threading.Event()
@asynccontextmanager
async def lifespan(app):
    t = threading.Thread(target=run_simulator, args=(stop_event,), daemon=True)
    t.start()
    yield
    stop_event.set()
from db import get_conn


app = FastAPI(title="StockLab DBMS API", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


def run_query(sql, params=None):
    conn = get_conn()
    try:
        cur = conn.cursor(dictionary=True)
        cur.execute(sql, params or ())
        rows = cur.fetchall()
        cur.close()
        return rows
    finally:
        conn.close()


# ---------- basic data (all read from views) ----------
@app.get("/api/users")
def users():
    return run_query("SELECT user_id, username FROM users ORDER BY user_id")
class NewUser(BaseModel):
    username: str = Field(min_length=3, max_length=50, pattern=r"^[A-Za-z0-9_]+$")
    email: str = Field(max_length=100, pattern=r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


@app.post("/api/users")
def create_user(user: NewUser):
    conn = get_conn()
    try:
        cur = conn.cursor()
        try:
            # cash_balance uses the table default of 100000.00
            cur.execute("INSERT INTO users (username, email) VALUES (%s, %s)",
                        (user.username, user.email))
            conn.commit()
        except mysql.connector.IntegrityError:
            raise HTTPException(status_code=400, detail="Username or email already exists")
        return {"user_id": cur.lastrowid, "username": user.username}
    finally:
        conn.close()    


@app.get("/api/stocks")
def stocks():
    return run_query("SELECT * FROM stock_statistics ORDER BY symbol")


@app.get("/api/stocks/{stock_id}/history")
def stock_history(stock_id: int):
    rows = run_query(
        """SELECT price, CAST(TIME(recorded_at) AS CHAR) AS tick_time
           FROM price_history WHERE stock_id = %s
           ORDER BY recorded_at DESC, price_id DESC LIMIT 60""",
        (stock_id,),
    )
    return rows[::-1]          # oldest first, for the chart


@app.get("/api/portfolio/{user_id}")
def portfolio(user_id: int):
    return run_query("SELECT * FROM portfolio_summary WHERE user_id = %s", (user_id,))


@app.get("/api/leaderboard")
def leaderboard():
    return run_query("SELECT * FROM leaderboard ORDER BY `rank`, username")


# ---------- trading: calls the stored procedures ----------
class Order(BaseModel):
    user_id: int
    stock_id: int
    quantity: int = Field(gt=0)


PROCS = {"buy": "execute_buy_order", "sell": "execute_sell_order"}


@app.post("/api/trade/{side}")
def place_order(side: str, order: Order):
    if side not in PROCS:
        raise HTTPException(status_code=404, detail="Unknown order side")
    conn = get_conn()
    try:
        cur = conn.cursor()
        cur.execute(f"CALL {PROCS[side]}(%s, %s, %s, @status)",
                    (order.user_id, order.stock_id, order.quantity))
        cur.execute("SELECT @status")
        status = cur.fetchone()[0]
        if isinstance(status, (bytes, bytearray)):
            status = status.decode()
        conn.commit()
    finally:
        conn.close()
    if not status.startswith("SUCCESS"):
        raise HTTPException(status_code=400, detail=status)
    return {"status": "success", "message": status}


# ---------- advanced analytics ----------
EXPOSURE_SQL = """
SELECT ps.user_id, ps.username, sec.sector_name,
       ROUND(SUM(ps.current_value), 2) AS sector_value,
       ROUND(100 * SUM(ps.current_value) /
             SUM(SUM(ps.current_value)) OVER (PARTITION BY ps.user_id), 2) AS exposure_pct
FROM portfolio_summary ps
JOIN sectors sec ON sec.sector_id = ps.sector_id
GROUP BY ps.user_id, ps.username, sec.sector_name
"""


@app.get("/api/analytics/top-stocks")
def top_stocks():
    return run_query("""
        WITH r AS (
            SELECT stock_id,
                   (price - LAG(price) OVER w) / LAG(price) OVER w AS ret
            FROM price_history
            WINDOW w AS (PARTITION BY stock_id ORDER BY recorded_at, price_id)
        )
        SELECT s.stock_id, s.symbol,
               ROUND(AVG(r.ret) * 100, 5) AS avg_return_pct,
               COUNT(r.ret) AS ticks
        FROM r JOIN stocks s ON s.stock_id = r.stock_id
        WHERE r.ret IS NOT NULL
        GROUP BY s.stock_id, s.symbol
        ORDER BY avg_return_pct DESC
        LIMIT 10""")


@app.get("/api/analytics/active-traders")
def active_traders():
    return run_query("""
        SELECT u.user_id, u.username, COUNT(*) AS total_trades
        FROM trades t JOIN users u ON u.user_id = t.user_id
        GROUP BY u.user_id, u.username
        ORDER BY total_trades DESC
        LIMIT 10""")


@app.get("/api/analytics/sector-exposure/{user_id}")
def sector_exposure(user_id: int):
    return run_query(
        f"SELECT * FROM ({EXPOSURE_SQL}) x WHERE user_id = %s ORDER BY exposure_pct DESC",
        (user_id,))


@app.get("/api/analytics/risk")
def risk():
    return run_query(f"SELECT * FROM ({EXPOSURE_SQL}) x WHERE exposure_pct > 50")


@app.get("/api/analytics/fomo-traders")
def fomo_traders():
    # BUYs made when the price was >= 2% above its price 15 minutes earlier
    return run_query("""
        SELECT t.user_id, u.username, COUNT(*) AS spike_buys
        FROM trades t
        JOIN users u ON u.user_id = t.user_id
        JOIN LATERAL (
            SELECT p.price AS old_price
            FROM price_history p
            WHERE p.stock_id = t.stock_id
              AND p.recorded_at <= t.executed_at - INTERVAL 15 MINUTE
            ORDER BY p.recorded_at DESC, p.price_id DESC
            LIMIT 1
        ) prev ON TRUE
        WHERE t.trade_type = 'BUY'
          AND (t.execution_price - prev.old_price) / prev.old_price >= 0.02
        GROUP BY t.user_id, u.username
        HAVING COUNT(*) >= 2
        ORDER BY spike_buys DESC""")


# ---------- indexing demo (used after Step 10) ----------
@app.get("/api/benchmark/explain")
def explain_demo():
    conn = get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            EXPLAIN ANALYZE
            SELECT * FROM price_history_bench
            WHERE stock_id = 3
              AND recorded_at BETWEEN NOW() - INTERVAL 30 DAY AND NOW() - INTERVAL 20 DAY""")
        return {"plan": "\n".join(str(r[0]) for r in cur.fetchall())}
    except mysql.connector.Error as e:
        raise HTTPException(status_code=400, detail=f"Create price_history_bench first (Step 10): {e}")
    finally:
        conn.close()
FRONTEND = os.path.join(os.path.dirname(__file__), "..", "frontend")
app.mount("/", StaticFiles(directory=FRONTEND, html=True), name="frontend")