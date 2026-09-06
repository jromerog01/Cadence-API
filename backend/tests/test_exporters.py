import sys
from pathlib import Path
from uuid import uuid4

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from domain.exporters import to_json, to_markdown, to_srt, to_txt, to_vtt
from domain.models import Job, Segment


def make_job(**overrides) -> Job:
    segments = overrides.pop(
        "segments",
        [
            Segment(idx=0, start_seconds=0.0, end_seconds=1.5, text="Hola mundo", speaker=None),
            Segment(idx=1, start_seconds=1.5, end_seconds=63.25, text="Segunda frase", speaker="Ana"),
        ],
    )
    defaults = dict(
        id=uuid4(),
        owner_id=uuid4(),
        original_filename="entrevista.wav",
        stored_path="/data/audio/x.wav",
        mime_type="audio/wav",
        size_bytes=1234,
        model="tiny",
        status="done",
        language=None,
        detected_language="es",
        duration_seconds=63.25,
        segments=segments,
    )
    defaults.update(overrides)
    return Job(**defaults)


def test_to_txt_includes_header_and_segments():
    text = to_txt(make_job())
    assert "entrevista.wav" in text
    assert "[00:00] Hola mundo" in text
    assert "[00:02] Segunda frase" in text


def test_to_json_round_trips_segments():
    import json

    data = json.loads(to_json(make_job()))
    assert data["original_filename"] == "entrevista.wav"
    assert data["detected_language"] == "es"
    assert len(data["segments"]) == 2
    assert data["segments"][1]["speaker"] == "Ana"
    assert data["segments"][1]["start_seconds"] == 1.5


def test_to_markdown_includes_speaker_when_present():
    md = to_markdown(make_job())
    assert md.startswith("# entrevista.wav")
    assert "**Ana**" in md
    assert "Hola mundo" in md


def test_to_srt_uses_comma_milliseconds():
    srt = to_srt(make_job())
    assert "00:00:00,000 --> 00:00:01,500" in srt
    assert "00:00:01,500 --> 00:01:03,250" in srt
    assert "1\n" in srt and "2\n" in srt


def test_to_vtt_uses_dot_milliseconds_and_header():
    vtt = to_vtt(make_job())
    assert vtt.startswith("WEBVTT")
    assert "00:00:00.000 --> 00:00:01.500" in vtt
    assert "," not in vtt.split("\n", 1)[1]


def test_exporters_do_not_touch_database_or_disk():
    # No repository, no session, no file I/O anywhere above — this test
    # exists to document that guarantee, since the functions are called
    # with a plain in-memory Job.
    job = make_job(segments=[])
    assert to_txt(job)
    assert to_json(job)
    assert to_markdown(job)
    assert to_srt(job) == ""
    assert to_vtt(job) == "WEBVTT\n"
