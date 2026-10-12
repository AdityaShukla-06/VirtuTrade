from dotenv import load_dotenv
load_dotenv()
import os
import mysql.connector

def get_conn():
    cfg = dict(
        host=os.environ.get("DB_HOST", "localhost"),
        port=int(os.environ.get("DB_PORT", 3306)),
        user=os.environ.get("DB_USER", "root"),
        password=os.environ["DB_PASSWORD"],
        database=os.environ.get("DB_NAME", "stock_trading_db"),
    )
    ca = os.environ.get("DB_SSL_CA")
    if ca:
        cfg["ssl_ca"] = ca
    return mysql.connector.connect(**cfg)