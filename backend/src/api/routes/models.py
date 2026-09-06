from fastapi import APIRouter
from pydantic import BaseModel

from adapters.model_catalog import get_enabled_models

router = APIRouter()


class ModelOut(BaseModel):
    name: str
    ram_gb: float
    speed_factor: float
    role: str


@router.get("", response_model=list[ModelOut])
def list_models():
    return [
        ModelOut(name=m.name, ram_gb=m.ram_gb, speed_factor=m.speed_factor, role=m.role)
        for m in get_enabled_models()
    ]
