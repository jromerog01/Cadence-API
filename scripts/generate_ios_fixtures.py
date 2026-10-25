"""Regenerate Swift fixtures using the backend schemas and exporters."""
import sys
from datetime import datetime, timezone
from pathlib import Path
from uuid import UUID

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "backend/src"))

from api.schemas import JobOut
from domain.exporters import TEXT_EXPORTERS
from domain.models import Job, Segment

job = Job(
    id=UUID("7ea01d35-27f5-4d81-a33d-096b579ddaa7"),
    owner_id=UUID("0ea01d35-27f5-4d81-a33d-096b579ddaa7"),
    original_filename="reunión con Ana.m4a", stored_path="/unused.m4a",
    mime_type="audio/mp4", size_bytes=128, model="small", status="done",
    progress=1, detected_language="es", duration_seconds=63.25,
    created_at=datetime(2026, 10, 25, 18, 48, 38, 123456, tzinfo=timezone.utc),
    segments=[Segment(0, 0.0, 1.5, "Hola, mundo."),
              Segment(1, 1.5, 63.25, 'Segunda frase: "sí".', "Ana")],
)
destination = ROOT / "ios/CadenceKit/Tests/CadenceKitTests/Fixtures"
destination.mkdir(parents=True, exist_ok=True)
(destination / "job.json").write_text(JobOut.from_domain(job).model_dump_json(indent=2), encoding="utf-8")
for format_name, exporter in TEXT_EXPORTERS.items():
    (destination / f"expected.{format_name}").write_text(exporter(job), encoding="utf-8")
