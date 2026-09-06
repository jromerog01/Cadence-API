import os
from dataclasses import dataclass


@dataclass(frozen=True)
class ModelInfo:
    name: str
    ram_gb: float
    speed_factor: float  # multiplier vs. audio duration
    role: str


# Speed factors are estimates from measuring faster-whisper (int8, 4 threads)
# on the target ProDesk 600 G3 DM (i7-7700T, no GPU) — see plan section 1.
# This dev machine cannot reproduce that measurement; Fase 5 replaces these
# with real numbers measured on the ProDesk itself.
MODEL_CATALOG: list[ModelInfo] = [
    ModelInfo(name="tiny", ram_gb=0.5, speed_factor=0.1, role="borradores, pruebas"),
    ModelInfo(name="base", ram_gb=0.7, speed_factor=0.2, role="notas de voz cortas"),
    ModelInfo(name="small", ram_gb=1.2, speed_factor=0.6, role="defecto rápido"),
    ModelInfo(name="medium", ram_gb=2.5, speed_factor=2.0, role="calidad media"),
    ModelInfo(name="large-v3-turbo", ram_gb=1.8, speed_factor=1.5, role="defecto de calidad"),
    ModelInfo(name="large-v3", ram_gb=3.5, speed_factor=5.0, role="máxima calidad, audio difícil"),
]


def get_enabled_models() -> list[ModelInfo]:
    disabled = {
        name.strip()
        for name in os.environ.get("WHISPER_DISABLED_MODELS", "").split(",")
        if name.strip()
    }
    return [m for m in MODEL_CATALOG if m.name not in disabled]
