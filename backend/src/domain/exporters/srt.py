from domain.exporters._util import format_timestamp
from domain.models import Job


def to_srt(job: Job) -> str:
    blocks = []
    for i, s in enumerate(job.segments, start=1):
        start = format_timestamp(s.start_seconds, ",")
        end = format_timestamp(s.end_seconds, ",")
        blocks.append(f"{i}\n{start} --> {end}\n{s.text}\n")
    return "\n".join(blocks)
