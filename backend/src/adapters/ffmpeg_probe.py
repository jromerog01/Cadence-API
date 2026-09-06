import json
import subprocess
from pathlib import Path

from domain.ports import AudioInfo


class FfmpegAudioProbe:
    """Validates uploads and reports duration via ffprobe, independent of
    container format (mp3/m4a/ogg/opus/flac/wav/webm/mp4)."""

    def probe(self, path: Path) -> AudioInfo:
        result = subprocess.run(
            [
                "ffprobe",
                "-v", "error",
                "-print_format", "json",
                "-show_format",
                "-show_streams",
                str(path),
            ],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            raise ValueError(f"ffprobe failed: {result.stderr.strip()}")

        data = json.loads(result.stdout)
        streams = data.get("streams", [])
        has_audio_stream = any(s.get("codec_type") == "audio" for s in streams)

        duration_str = data.get("format", {}).get("duration")
        duration_seconds = float(duration_str) if duration_str else 0.0

        return AudioInfo(duration_seconds=duration_seconds, has_audio_stream=has_audio_stream)


def normalize_to_wav(input_path: Path, output_path: Path) -> None:
    """Normalizes any input format to mono 16kHz PCM WAV, the format
    faster-whisper expects. -vn drops any video stream present (mp4/webm)."""
    output_path.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(
        [
            "ffmpeg", "-y",
            "-i", str(input_path),
            "-vn",
            "-ac", "1",
            "-ar", "16000",
            "-c:a", "pcm_s16le",
            str(output_path),
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise ValueError(f"ffmpeg normalization failed: {result.stderr.strip()}")
