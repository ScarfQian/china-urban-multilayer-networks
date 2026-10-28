"""Resolve the shared input and output paths in config/paths.json."""
from __future__ import annotations

import json
from pathlib import Path


def repository_root() -> Path:
    return Path(__file__).resolve().parents[2]


def study_path(area: str, *parts: str) -> Path:
    root = repository_root()
    settings = json.loads((root / "config" / "paths.json").read_text())
    if area == "data":
        value = Path(settings["data_directory"]).expanduser()
    elif area == "generated":
        value = Path(settings["output_directory"]).expanduser()
    else:
        raise ValueError(f"Unknown path area: {area}")
    base = value if value.is_absolute() else root / value
    return base.joinpath(*parts)
