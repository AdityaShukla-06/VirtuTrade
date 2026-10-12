import os
import sys
import time
import random

sys.path.append(os.path.join(os.path.dirname(__file__), "..", "backend"))
from db import get_conn

TICK_SECONDS = 3        # time between price updates
MAX_MOVE = 0.003        # each tick moves a price by at most +/-0.3%


def run():
    conn = get_conn()
    cur = conn.cursor(dictionary=True)
    print("Market simulator running. Press Ctrl+C to stop.")
    try:
        while True:
            cur.execute("SELECT stock_id, price FROM latest_prices")
            for row in cur.fetchall():
                old = float(row["price"])
                new = round(max(5.0, old * (1 + random.uniform(-MAX_MOVE, MAX_MOVE))), 2)
                cur.execute(
                    "INSERT INTO price_history (stock_id, price, volume) VALUES (%s, %s, %s)",
                    (row["stock_id"], new, random.randint(10, 200)),
                )
                cur.execute(
                    "UPDATE latest_prices SET price = %s, updated_at = NOW() WHERE stock_id = %s",
                    (new, row["stock_id"]),
                )
            conn.commit()          # history + current price change together
            time.sleep(TICK_SECONDS)
    except KeyboardInterrupt:
        print("\nSimulator stopped.")
    finally:
        cur.close()
        conn.close()


if __name__ == "__main__":
    run()