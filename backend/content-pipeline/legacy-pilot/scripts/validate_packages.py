from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any

from pipeline_common import CONFIG_PATH, PACKAGE_PATH, load_config, load_package


REQUIRED_WORD_FIELDS = [
    "headword",
    "level_number",
    "phonetic",
    "pos_primary",
    "mnemonic",
    "meanings",
    "examples",
    "distractors",
]
ROOT_AFFIX_KEYS = {"root", "prefix", "suffix", "gloss"}


def is_blank(value: Any) -> bool:
    return value is None or (isinstance(value, str) and not value.strip())


def validate_root_affix(errors: list[str], label: str, root_affix: Any) -> None:
    if root_affix is None:
        return
    if not isinstance(root_affix, dict):
        errors.append(f"{label}: root_affix must be an object or null")
        return
    missing = ROOT_AFFIX_KEYS - set(root_affix.keys())
    extra = set(root_affix.keys()) - ROOT_AFFIX_KEYS
    if missing:
        errors.append(f"{label}: root_affix missing keys {sorted(missing)}")
    if extra:
        errors.append(f"{label}: root_affix has unsupported keys {sorted(extra)}")
    if is_blank(root_affix.get("root")) and is_blank(root_affix.get("prefix")) and is_blank(root_affix.get("suffix")):
        errors.append(f"{label}: root_affix must include at least one of root/prefix/suffix")
    if is_blank(root_affix.get("gloss")):
        errors.append(f"{label}: root_affix.gloss is required when root_affix is present")


def validate_package(package: dict[str, Any], config: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    pilot = config["pilot"]
    supported_level = pilot["level_number"]
    active_types = set(pilot["active_question_types"])

    if not {1, 2}.issubset(active_types):
        errors.append("config: pilot.active_question_types must include 1 and 2")
    unsupported_types = active_types - {1, 2}
    if unsupported_types:
        errors.append(f"config: unsupported active question types {sorted(unsupported_types)}")

    words = package.get("words")
    if not isinstance(words, list) or not words:
        return ["package: words must be a non-empty list"]

    seen_headwords: set[tuple[int, str]] = set()
    for index, word in enumerate(words):
        label = f"words[{index}]"
        if not isinstance(word, dict):
            errors.append(f"{label}: must be an object")
            continue

        for field in REQUIRED_WORD_FIELDS:
            if field not in word or is_blank(word.get(field)):
                errors.append(f"{label}: missing required field {field}")

        headword = str(word.get("headword", "")).strip().lower()
        level_number = word.get("level_number")
        if level_number != supported_level:
            errors.append(f"{label} {headword!r}: unsupported level_number {level_number}; expected {supported_level}")

        key = (level_number, headword)
        if key in seen_headwords:
            errors.append(f"{label} {headword!r}: duplicate headword within level")
        seen_headwords.add(key)

        phonetic = word.get("phonetic")
        if isinstance(phonetic, str) and not (phonetic.startswith("/") and phonetic.endswith("/")):
            errors.append(f"{label} {headword!r}: phonetic must start and end with /")

        if is_blank(word.get("mnemonic")):
            errors.append(f"{label} {headword!r}: mnemonic must be non-null and non-blank")

        validate_root_affix(errors, f"{label} {headword!r}", word.get("root_affix"))

        meanings = word.get("meanings")
        if not isinstance(meanings, list) or not meanings:
            errors.append(f"{label} {headword!r}: meanings must contain at least 1 row")
        else:
            for meaning_index, meaning in enumerate(meanings):
                m_label = f"{label}.meanings[{meaning_index}] {headword!r}"
                for field in ["pos", "definition_zh", "definition_en"]:
                    if not isinstance(meaning, dict) or is_blank(meaning.get(field)):
                        errors.append(f"{m_label}: {field} is required")

        examples = word.get("examples")
        if not isinstance(examples, list) or len(examples) < 2:
            errors.append(f"{label} {headword!r}: examples must contain at least 2 rows")
        else:
            seen_examples: set[str] = set()
            for example_index, example in enumerate(examples):
                e_label = f"{label}.examples[{example_index}] {headword!r}"
                for field in ["sentence_en", "translation_zh", "target_span", "source"]:
                    if not isinstance(example, dict) or is_blank(example.get(field)):
                        errors.append(f"{e_label}: {field} is required")
                sentence = str(example.get("sentence_en", ""))
                target = str(example.get("target_span", ""))
                if target and target not in sentence:
                    errors.append(f"{e_label}: target_span {target!r} is not a literal substring of sentence_en")
                if sentence in seen_examples:
                    errors.append(f"{e_label}: duplicate sentence_en")
                seen_examples.add(sentence)

        distractors = word.get("distractors")
        if not isinstance(distractors, list) or len(distractors) != 3:
            errors.append(f"{label} {headword!r}: distractors must contain exactly 3 values")
        else:
            normalized = [str(d).strip().lower() for d in distractors]
            if any(not d for d in normalized):
                errors.append(f"{label} {headword!r}: distractors cannot be blank")
            if headword in normalized:
                errors.append(f"{label} {headword!r}: distractor cannot equal headword")
            if len(set(normalized)) != len(normalized):
                errors.append(f"{label} {headword!r}: duplicate distractors are not allowed")

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate KuaKua Duck word packages.")
    parser.add_argument("--config", type=Path, default=CONFIG_PATH)
    parser.add_argument("--package", type=Path, default=PACKAGE_PATH)
    args = parser.parse_args()

    config = load_config() if args.config == CONFIG_PATH else __import__("json").loads(args.config.read_text(encoding="utf-8"))
    package = load_package(args.package)
    errors = validate_package(package, config)
    if errors:
        print("Package validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print(f"Package validation passed: {len(package['words'])} word(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
