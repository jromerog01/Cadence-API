import sys
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))
from api.deps import get_current_user, get_repo
from api.main import app
from domain.models import Job, User


def test_import_validates_timeline_and_exports_without_audio():
    owner = User(uuid4(), "ana@example.com", None, "Ana")

    class Repo:
        job = None

        def import_completed_job(self, segments, **fields):
            self.job = Job(**fields, created_at=datetime.now(timezone.utc), segments=segments)
            return self.job

        def get_job(self, job_id, **kwargs):
            return self.job if self.job and self.job.id == job_id else None

    repo = Repo()
    app.dependency_overrides[get_current_user] = lambda: owner
    app.dependency_overrides[get_repo] = lambda: repo
    payload = {
        "original_filename": "reunión.m4a", "duration_seconds": 3.0, "language": "es",
        "segments": [{"idx": 0, "start_seconds": 0, "end_seconds": 2, "text": "Hola mundo"}],
    }
    try:
        with TestClient(app) as client:
            response = client.post("/api/jobs/import", json=payload)
            assert response.status_code == 201
            assert response.json()["status"] == "done"
            assert response.json()["word_count"] == 2
            assert repo.job.stored_path is None and repo.job.size_bytes is None
            assert repo.job.owner_id == owner.id
            for format_name in ("txt", "md", "json", "srt", "vtt", "pdf"):
                export = client.get(f"/api/jobs/{repo.job.id}/export", params={"format": format_name})
                assert export.status_code == 200
                assert export.content
            overlapping = payload["segments"] + [{"idx": 1, "start_seconds": 1, "end_seconds": 3, "text": "Mal"}]
            assert client.post("/api/jobs/import", json={**payload, "segments": overlapping}).status_code == 422
            negative = [{"idx": 0, "start_seconds": -1, "end_seconds": 2, "text": "Mal"}]
            assert client.post("/api/jobs/import", json={**payload, "segments": negative}).status_code == 422
    finally:
        app.dependency_overrides.clear()
