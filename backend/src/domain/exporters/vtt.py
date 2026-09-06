from domain.exporters._util import format_timestamp
from domain.models import Job


def to_vtt(job: Job) -> str:
    blocks = ["WEBVTT\n"]
    for s in job.segments:
        start = format_timestamp(s.start_seconds, ".")
        end = format_timestamp(s.end_seconds, ".")
        blocks.append(f"{start} --> {end}\n{s.text}\n")
    return "\n".join(blocks)
