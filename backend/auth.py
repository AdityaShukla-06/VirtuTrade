import hashlib
import hmac
import os
import secrets
import time

import mysql.connector
from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel, EmailStr, Field

from db import get_conn

router = APIRouter(prefix="/api/auth")


# ---------- password hashing (standard library, no extra install) ----------
def hash_password(pw: str) -> str:
    salt = os.urandom(16)
    h = hashlib.pbkdf2_hmac("sha256", pw.encode(), salt, 200_000)
    return salt.hex() + "$" + h.hex()


def check_password(pw: str, stored) -> bool:
    try:
        salt_hex, h_hex = stored.split("$")
        h = hashlib.pbkdf2_hmac("sha256", pw.encode(), bytes.fromhex(salt_hex), 200_000)
        return hmac.compare_digest(h.hex(), h_hex)
    except Exception:
        return False


# ---------- sessions ----------
def _new_session(cur, user_id: int) -> str:
    token = secrets.token_hex(32)
    cur.execute(
        "INSERT INTO sessions (token, user_id, expires_at) "
        "VALUES (%s, %s, DATE_ADD(NOW(), INTERVAL 7 DAY))",
        (token, user_id),
    )
    return token


def current_user(authorization: str = Header(default="")):
    """Use as a dependency (Depends) on any route that needs a logged-in user."""
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Please log in.")
    token = authorization[7:]
    conn = get_conn()
    try:
        cur = conn.cursor(dictionary=True)
        cur.execute(
            "SELECT u.user_id, u.username FROM sessions s "
            "JOIN users u ON u.user_id = s.user_id "
            "WHERE s.token = %s AND s.expires_at > NOW()",
            (token,),
        )
        user = cur.fetchone()
    finally:
        conn.close()
    if not user:
        raise HTTPException(status_code=401, detail="Session expired. Please log in again.")
    return user


# ---------- request models ----------
class Register(BaseModel):
    username: str = Field(pattern=r"^[A-Za-z0-9_]{3,50}$")
    email: EmailStr
    password: str = Field(min_length=8, max_length=100)


class Login(BaseModel):
    username: str
    password: str


# ---------- routes ----------
@router.post("/register")
def register(body: Register):
    conn = get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT 1 FROM users WHERE username=%s OR email=%s",
            (body.username, body.email),
        )
        if cur.fetchone():
            raise HTTPException(status_code=400, detail="That username or email is already taken.")
        try:
            cur.execute(
                "INSERT INTO users (username, email, password_hash) VALUES (%s, %s, %s)",
                (body.username, body.email, hash_password(body.password)),
            )
        except mysql.connector.IntegrityError:
            raise HTTPException(status_code=400, detail="That username or email is already taken.")
        user_id = cur.lastrowid
        token = _new_session(cur, user_id)
        conn.commit()
        return {"token": token, "user_id": user_id, "username": body.username}
    finally:
        conn.close()


@router.post("/login")
def login(body: Login):
    conn = get_conn()
    try:
        cur = conn.cursor(dictionary=True)
        cur.execute(
            "SELECT user_id, username, password_hash FROM users WHERE username=%s",
            (body.username,),
        )
        u = cur.fetchone()
        if not u or not check_password(body.password, u["password_hash"]):
            time.sleep(0.5)  # slows down password guessing
            raise HTTPException(status_code=401, detail="Wrong username or password.")
        cur.execute("DELETE FROM sessions WHERE expires_at < NOW()")
        token = _new_session(cur, u["user_id"])
        conn.commit()
        return {"token": token, "user_id": u["user_id"], "username": u["username"]}
    finally:
        conn.close()


@router.get("/me")
def me(authorization: str = Header(default="")):
    return current_user(authorization)


@router.post("/logout")
def logout(authorization: str = Header(default="")):
    if authorization.startswith("Bearer "):
        conn = get_conn()
        try:
            cur = conn.cursor()
            cur.execute("DELETE FROM sessions WHERE token=%s", (authorization[7:],))
            conn.commit()
        finally:
            conn.close()
    return {"ok": True}