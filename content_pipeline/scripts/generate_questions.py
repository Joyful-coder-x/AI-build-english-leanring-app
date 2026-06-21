from __future__ import annotations

import argparse
from pathlib import Path

from pipeline_common import (
    LEVEL_001_DIR,
    OUTPUT_DIR,
    PACKAGE_PATH,
    blank_target,
    deterministic_shuffle,
    ensure_output_dir,
    example_id,
    first_letter_hint,
    load_config,
    load_package,
    option_id,
    question_id,
    word_id,
    write_csv,
)
from validate_packages import validate_package


QUESTIONS_HEADERS = [
    "id",
    "type_code",
    "category",
    "answer_form",
    "word_id",
    "example_id",
    "stem",
    "prompt_hint",
    "correct_answer",
    "translation_zh",
    "explanation",
    "audio_path",
    "expected_time_ms",
    "is_active",
]
OPTIONS_HEADERS = ["id", "question_id", "option_text", "is_correct", "sort_order"]


def build_question_rows(package: dict, config: dict) -> tuple[list[dict], list[dict]]:
    defaults = config["question_defaults"]
    questions: list[dict] = []
    options: list[dict] = []

    for word in package["words"]:
        wid = word_id(config, word)
        distractors = [str(d) for d in word["distractors"]]
        for example in word["examples"]:
            eid = example_id(config, word, example)
            target = example["target_span"]

            if 1 in config["pilot"]["active_question_types"]:
                qid = question_id(config, word, example, 1)
                questions.append(
                    {
                        "id": qid,
                        "type_code": 1,
                        "category": defaults["category"],
                        "answer_form": defaults["type_1_answer_form"],
                        "word_id": wid,
                        "example_id": eid,
                        "stem": blank_target(example["sentence_en"], target, first_letter_hint(target)),
                        "prompt_hint": "Use the first-letter hint to type the complete word.",
                        "correct_answer": target,
                        "translation_zh": example["translation_zh"],
                        "explanation": "",
                        "audio_path": "",
                        "expected_time_ms": defaults["type_1_expected_time_ms"],
                        "is_active": str(defaults["is_active"]).lower(),
                    }
                )

            if 2 in config["pilot"]["active_question_types"]:
                qid = question_id(config, word, example, 2)
                questions.append(
                    {
                        "id": qid,
                        "type_code": 2,
                        "category": defaults["category"],
                        "answer_form": defaults["type_2_answer_form"],
                        "word_id": wid,
                        "example_id": eid,
                        "stem": blank_target(example["sentence_en"], target, "_____"),
                        "prompt_hint": "Choose the correct word to complete the sentence.",
                        "correct_answer": target,
                        "translation_zh": example["translation_zh"],
                        "explanation": "",
                        "audio_path": "",
                        "expected_time_ms": defaults["type_2_expected_time_ms"],
                        "is_active": str(defaults["is_active"]).lower(),
                    }
                )
                shuffled = deterministic_shuffle([target, *distractors], qid)
                for sort_order, option_text in enumerate(shuffled):
                    options.append(
                        {
                            "id": option_id(config, qid, option_text),
                            "question_id": qid,
                            "option_text": option_text,
                            "is_correct": str(option_text == target).lower(),
                            "sort_order": sort_order,
                        }
                    )

    return questions, options


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate type 1/type 2 pilot questions.")
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
    questions, options = build_question_rows(package, config)
    write_csv(output_dir / "questions.csv", QUESTIONS_HEADERS, questions)
    write_csv(output_dir / "question_options.csv", OPTIONS_HEADERS, options)
    print(f"Wrote {len(questions)} questions and {len(options)} question options")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
