from __future__ import annotations

import csv
import json
import random
import re
import uuid
from pathlib import Path
from typing import Any


PIPELINE_ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = PIPELINE_ROOT / "config" / "pipeline_config.json"
PACKAGE_PATH = PIPELINE_ROOT / "packages" / "level_001_packages.json"
OUTPUT_DIR = PIPELINE_ROOT / "output"
LEVEL_001_DIR = OUTPUT_DIR / "level_001"
LEVEL_001_TTS_DIR = LEVEL_001_DIR / "tts"


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def load_config() -> dict[str, Any]:
    return load_json(CONFIG_PATH)


def load_package(path: Path = PACKAGE_PATH) -> dict[str, Any]:
    return load_json(path)


def ensure_output_dir() -> Path:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    return OUTPUT_DIR


def namespace_uuid(config: dict[str, Any]) -> uuid.UUID:
    return uuid.UUID(config["uuid_namespace"])


def stable_uuid(config: dict[str, Any], kind: str, *parts: object) -> str:
    normalized = "|".join(str(p).strip().lower() for p in parts)
    return str(uuid.uuid5(namespace_uuid(config), f"{kind}|{normalized}"))


def word_id(config: dict[str, Any], word: dict[str, Any]) -> str:
    return stable_uuid(config, "word", word["level_number"], word["headword"])


def example_id(config: dict[str, Any], word: dict[str, Any], example: dict[str, Any]) -> str:
    return stable_uuid(config, "example", word["level_number"], word["headword"], example["sentence_en"])


def question_id(
    config: dict[str, Any],
    word: dict[str, Any],
    example: dict[str, Any],
    type_code: int,
) -> str:
    return stable_uuid(
        config,
        "question",
        word["level_number"],
        word["headword"],
        example["sentence_en"],
        type_code,
    )


def option_id(config: dict[str, Any], question_uuid: str, option_text: str) -> str:
    return stable_uuid(config, "question_option", question_uuid, option_text)


def jsonb(value: Any) -> str:
    if value is None:
        return ""
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def write_csv(path: Path, headers: list[str], rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8-sig") as f:
        writer = csv.DictWriter(f, fieldnames=headers, extrasaction="raise")
        writer.writeheader()
        for row in rows:
            writer.writerow({header: row.get(header, "") for header in headers})


def blank_target(sentence: str, target: str, replacement: str) -> str:
    idx = sentence.find(target)
    if idx < 0:
        raise ValueError(f"target_span {target!r} not found in sentence {sentence!r}")
    return sentence[:idx] + replacement + sentence[idx + len(target):]


def deterministic_shuffle(items: list[str], seed: str) -> list[str]:
    shuffled = list(items)
    random.Random(seed).shuffle(shuffled)
    return shuffled


def first_letter_hint(target: str) -> str:
    match = re.search(r"[A-Za-z]", target)
    if not match:
        raise ValueError(f"target_span has no Latin first letter: {target!r}")
    return f"___{match.group(0).lower()}___"
