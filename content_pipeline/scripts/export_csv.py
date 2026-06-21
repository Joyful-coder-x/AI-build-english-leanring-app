from __future__ import annotations

import argparse
from pathlib import Path

from pipeline_common import (
    LEVEL_001_DIR,
    OUTPUT_DIR,
    PACKAGE_PATH,
    ensure_output_dir,
    example_id,
    jsonb,
    load_config,
    load_package,
    word_id,
    write_csv,
)
from validate_packages import validate_package


WORDS_HEADERS = [
    "id",
    "level_number",
    "headword",
    "phonetic",
    "pronunciation_path",
    "mnemonic",
    "root_affix",
    "pos_primary",
    "frequency_rank",
]
MEANINGS_HEADERS = ["id", "word_id", "pos", "definition_zh", "definition_en", "sort_order"]
FORMS_HEADERS = ["id", "word_id", "form_label", "form_text"]
EXAMPLES_HEADERS = ["id", "word_id", "sentence_en", "translation_zh", "target_span", "audio_path", "sort_order"]


def build_rows(package: dict, config: dict) -> tuple[list[dict], list[dict], list[dict], list[dict]]:
    words_rows: list[dict] = []
    meanings_rows: list[dict] = []
    forms_rows: list[dict] = []
    examples_rows: list[dict] = []
    tts_prefix = config["tts"]["path_prefix"]

    for word in package["words"]:
        wid = word_id(config, word)
        words_rows.append(
            {
                "id": wid,
                "level_number": word["level_number"],
                "headword": word["headword"].strip().lower(),
                "phonetic": word["phonetic"],
                "pronunciation_path": f"{tts_prefix}/{wid}.mp3",
                "mnemonic": word["mnemonic"],
                "root_affix": jsonb(word.get("root_affix")),
                "pos_primary": word["pos_primary"],
                "frequency_rank": word.get("frequency_rank", ""),
            }
        )

        for index, meaning in enumerate(word.get("meanings", [])):
            meanings_rows.append(
                {
                    "id": __import__("pipeline_common").stable_uuid(config, "meaning", wid, index),
                    "word_id": wid,
                    "pos": meaning["pos"],
                    "definition_zh": meaning["definition_zh"],
                    "definition_en": meaning["definition_en"],
                    "sort_order": meaning.get("sort_order", index),
                }
            )

        for index, form in enumerate(word.get("forms", [])):
            forms_rows.append(
                {
                    "id": __import__("pipeline_common").stable_uuid(config, "form", wid, form["form_label"], form["form_text"]),
                    "word_id": wid,
                    "form_label": form["form_label"],
                    "form_text": form["form_text"],
                }
            )

        for index, example in enumerate(word.get("examples", [])):
            eid = example_id(config, word, example)
            examples_rows.append(
                {
                    "id": eid,
                    "word_id": wid,
                    "sentence_en": example["sentence_en"],
                    "translation_zh": example["translation_zh"],
                    "target_span": example["target_span"],
                    "audio_path": example.get("audio_path", ""),
                    "sort_order": example.get("sort_order", index),
                }
            )

    return words_rows, meanings_rows, forms_rows, examples_rows


def main() -> int:
    parser = argparse.ArgumentParser(description="Export word packages to Supabase CSV files.")
    parser.add_argument("--package", type=Path, default=PACKAGE_PATH)
    parser.add_argument("--output", type=Path, default=LEVEL_001_DIR)
    args = parser.parse_args()

    config = load_config()
    package = load_package(args.package)
    errors = validate_package(package, config)
    if errors:
        for error in errors:
            print(f"- {error}")
        return 1

    output_dir = args.output
    output_dir.mkdir(parents=True, exist_ok=True)
    words_rows, meanings_rows, forms_rows, examples_rows = build_rows(package, config)
    write_csv(output_dir / "words.csv", WORDS_HEADERS, words_rows)
    write_csv(output_dir / "word_meanings.csv", MEANINGS_HEADERS, meanings_rows)
    write_csv(output_dir / "word_forms.csv", FORMS_HEADERS, forms_rows)
    write_csv(output_dir / "examples.csv", EXAMPLES_HEADERS, examples_rows)

    print(f"Wrote {len(words_rows)} words, {len(meanings_rows)} meanings, {len(forms_rows)} forms, {len(examples_rows)} examples")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
