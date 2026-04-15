from fastapi.testclient import TestClient
from unittest.mock import patch, MagicMock
import pytest
import os

os.environ["GROQ_API_KEY"] = "dummy-key-for-tests"

from app.main import app

client = TestClient(app)


# ── /  ────────────────────────────────────────────────────
def test_root_returns_app_info():
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert data["app"] == "LLM Chat API"
    assert data["status"] == "running"


# ── /health  ──────────────────────────────────────────────
def test_health_returns_healthy():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"healthy": True}


# ── /chat — happy path  ───────────────────────────────────
def test_chat_returns_response():
    mock_message = MagicMock()
    mock_message.content = "Hello, I am an AI assistant."

    mock_choice = MagicMock()
    mock_choice.message = mock_message

    mock_completion = MagicMock()
    mock_completion.choices = [mock_choice]

    with patch("app.main.client.chat.completions.create", return_value=mock_completion):
        response = client.post("/chat", json={"prompt": "Say hello"})

    assert response.status_code == 200
    data = response.json()
    assert data["response"] == "Hello, I am an AI assistant."
    assert data["model"] == "llama-3.3-70b-versatile"


# ── /chat — empty prompt  ─────────────────────────────────
def test_chat_rejects_empty_prompt():
    response = client.post("/chat", json={"prompt": ""})
    assert response.status_code == 400
    assert "empty" in response.json()["detail"].lower()


# ── /chat — whitespace only prompt  ──────────────────────
def test_chat_rejects_whitespace_prompt():
    response = client.post("/chat", json={"prompt": "   "})
    assert response.status_code == 400


# ── /chat — upstream API failure  ────────────────────────
def test_chat_handles_groq_error():
    with patch("app.main.client.chat.completions.create", side_effect=Exception("API down")):
        response = client.post("/chat", json={"prompt": "Hello"})
    assert response.status_code == 500
