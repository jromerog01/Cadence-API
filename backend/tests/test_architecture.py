from pathlib import Path

FORBIDDEN_IMPORTS = ("fastapi", "sqlalchemy", "faster_whisper")
DOMAIN_DIR = Path(__file__).resolve().parent.parent / "src" / "domain"


def test_domain_has_no_framework_imports():
    offenders = []
    for py_file in DOMAIN_DIR.rglob("*.py"):
        text = py_file.read_text()
        for forbidden in FORBIDDEN_IMPORTS:
            if f"import {forbidden}" in text or f"from {forbidden}" in text:
                offenders.append((py_file, forbidden))
    assert not offenders, f"domain/ imports frameworks it must not depend on: {offenders}"
