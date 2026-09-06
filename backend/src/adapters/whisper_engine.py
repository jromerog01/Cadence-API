from pathlib import Path
from typing import Iterator

from faster_whisper import WhisperModel

from domain.models import Segment, TranscriptionInfo


class WhisperEngine:
    """Wraps faster-whisper. Caches the loaded model in memory across jobs
    handled by the same worker process, since loading from a mechanical disk
    is expensive (see plan section 1)."""

    def __init__(
        self,
        model_size: str = "tiny",
        device: str = "cpu",
        compute_type: str = "int8",
        cpu_threads: int = 4,
        download_root: str | None = None,
    ):
        self.model_size = model_size
        self._device = device
        self._compute_type = compute_type
        self._cpu_threads = cpu_threads
        self._download_root = download_root
        self._model: WhisperModel | None = None

    def _get_model(self) -> WhisperModel:
        if self._model is None:
            self._model = WhisperModel(
                self.model_size,
                device=self._device,
                compute_type=self._compute_type,
                cpu_threads=self._cpu_threads,
                download_root=self._download_root,
            )
        return self._model

    def transcribe(
        self, audio_path: Path, *, language: str | None
    ) -> tuple[TranscriptionInfo, Iterator[Segment]]:
        model = self._get_model()
        raw_segments, info = model.transcribe(
            str(audio_path), language=language, vad_filter=True
        )
        domain_info = TranscriptionInfo(
            detected_language=info.language, duration_seconds=info.duration
        )

        def _iter_segments() -> Iterator[Segment]:
            # faster-whisper's generator is lazy: the actual transcription
            # work happens as this loop advances, not when transcribe() is
            # called. This is what makes real progress reporting possible.
            for i, raw in enumerate(raw_segments):
                yield Segment(
                    idx=i,
                    start_seconds=raw.start,
                    end_seconds=raw.end,
                    text=raw.text.strip(),
                    speaker=None,
                )

        return domain_info, _iter_segments()
