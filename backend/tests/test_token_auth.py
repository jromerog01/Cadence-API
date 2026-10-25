import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import uuid4

import jwt
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from api.deps import get_user_repo
from api.main import app
from api.security import COOKIE_NAME, hash_password
from domain.models import User


def test_token_login_bearer_and_cookie(monkeypatch):
    monkeypatch.setenv("SESSION_SECRET", "test-secret")
    user = User(uuid4(), "ana@example.com", hash_password("correcta"), "Ana")

    class Users:
        def get_by_email(self, email):
            return user if email == user.email else None

        def get_by_id(self, user_id):
            return user if user_id == user.id else None

    app.dependency_overrides[get_user_repo] = lambda: Users()
    try:
        with TestClient(app) as client:
            payload = {"email": user.email, "password": "correcta"}
            response = client.post("/api/auth/token", json=payload)
            assert response.status_code == 200
            assert COOKIE_NAME not in response.cookies
            token = response.json()["token"]
            assert response.json()["user"]["id"] == str(user.id)
            assert client.get("/api/auth/me", headers={"Authorization": f"Bearer {token}"}).status_code == 200
            assert client.get("/api/auth/me", headers={"Authorization": "Bearer invalid"}).status_code == 401
            expired = jwt.encode({"sub": str(user.id), "exp": datetime.now(timezone.utc) - timedelta(seconds=1)}, "test-secret", algorithm="HS256")
            assert client.get("/api/auth/me", headers={"Authorization": f"Bearer {expired}"}).status_code == 401
            assert client.post("/api/auth/token", json={**payload, "password": "mal"}).status_code == 401
            login = client.post("/api/auth/login", json=payload)
            assert login.status_code == 200
            assert COOKIE_NAME in login.cookies
            assert client.get("/api/auth/me").status_code == 200
    finally:
        app.dependency_overrides.clear()
