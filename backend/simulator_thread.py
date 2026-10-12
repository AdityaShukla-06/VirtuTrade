import random
from db import get_conn

def run_simulator(stop_event):
    while not stop_event.is_set():
        try:
            conn = get_conn()
            cur = conn.cursor(dictionary=True)
            while not stop_event.is_set():
                cur.execute("SELECT stock_id, price FROM latest_prices")
                for s in cur.fetchall():
                    new_price = round(max(5.0, float(s["price"]) * (1 + random.uniform(-0.003, 0.003))), 2)
                    cur.execute(
                        "INSERT INTO price_history (stock_id, price, volume) VALUES (%s,%s,%s)",
                        (s["stock_id"], new_price, random.randint(10, 200)),
                    )
                    cur.execute(
                        "UPDATE latest_prices SET price=%s, updated_at=NOW() WHERE stock_id=%s",
                        (new_price, s["stock_id"]),
                    )
                conn.commit()
                stop_event.wait(5)          # 5 seconds between ticks
        except Exception as e:
            print("simulator error:", e)
            stop_event.wait(10)             # wait, then reconnect