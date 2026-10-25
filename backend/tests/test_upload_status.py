import json
import sys
from pathlib import Path
from uuid import uuid4

from fastapi import HTTPException
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from api.routes import uploads
from domain.models import User


def test_upload_status_reports_only_received_parts(tmp_path, monkeypatch):
    owner = User(uuid4(), "owner@example.com", None, "Owner")
    other = User(uuid4(), "other@example.com", None, "Other")
    upload_id = uuid4()
    monkeypatch.setattr(uploads, "_uploads_root", lambda: tmp_path)
    session = tmp_path / str(upload_id)
    session.mkdir()
    (session / "meta.json").write_text(json.dumps({"owner_id": str(owner.id), "total_parts": 5}))
    for name in ("part-00000", "part-00002", "part-00004", "part-00006", "part-invalid"):
        (session / name).write_bytes(b"x")

    result = uploads.upload_status(upload_id, owner)
    assert result.total_parts == 5
    assert result.received == [0, 2, 4]
    with pytest.raises(HTTPException) as exc:
        uploads.upload_status(upload_id, other)
    assert exc.value.status_code == 404
