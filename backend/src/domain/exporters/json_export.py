import json

from domain.models import Job


def to_json(job: Job) -> str:
    payload = {
        "original_filename": job.original_filename,
        "model": job.model,
        "language": job.language,
        "detected_language": job.detected_language,
        "duration_seconds": job.duration_seconds,
        "segments": [
            {
                "idx": s.idx,
                "start_seconds": s.start_seconds,
                "end_seconds": s.end_seconds,
                "text": s.text,
                "speaker": s.speaker,
            }
            for s in job.segments
        ],
    }
    return json.dumps(payload, ensure_ascii=False, indent=2)
