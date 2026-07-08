from __future__ import annotations

import csv
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
IMPORT = ROOT / "constructed_data" / "band_4_0_v1" / "supabase_import"
FIRST_FIVE = ROOT / "constructed_data" / "levels_001_005" / "supabase_import"
BAND4_FIRST_GENERATED_LEVEL = 6
BAND4_LAST_LEVEL = 33
BAND4_TARGET_NEW_SENSES = 45


def read(name: str, root: Path = IMPORT) -> list[dict[str, str]]:
    with (root / name).open(encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def fail(errors: list[str]) -> int:
    print("BAND 4.0 VALIDATION FAILED")
    for error in errors[:200]:
        print(f"- {error}")
    if len(errors) > 200:
        print(f"- ... {len(errors) - 200} additional errors")
    return 1


def main() -> int:
    errors: list[str] = []
    levels = read("03_levels.csv")
    words = read("04_words.csv")
    senses = read("05_word_senses.csv")
    forms = read("06_word_forms.csv")
    assignments = read("08_level_sense_assignments.csv")
    examples = read("10_examples.csv")
    questions = read("12_questions.csv")
    options = read("13_question_options.csv")

    if {int(row["level_number"]) for row in levels} != set(range(1, 241)):
        errors.append("Level metadata must contain exactly Levels 1-240")

    if len(words) != 1465 or len(senses) != 1465:
        errors.append(
            f"Expected 1,465 unique Band 4 words/senses, got {len(words)}/{len(senses)}"
        )
    if len({row["headword"].lower() for row in words}) != len(words):
        errors.append("Duplicate Band 4 headwords")
    if len({row["id"] for row in words}) != len(words):
        errors.append("Duplicate word IDs")
    if len({row["id"] for row in senses}) != len(senses):
        errors.append("Duplicate sense IDs")

    for filename in (
        "04_words.csv",
        "05_word_senses.csv",
        "06_word_forms.csv",
        "07_pronunciations.csv",
        "08_level_sense_assignments.csv",
        "09_usage_evidence.csv",
        "10_examples.csv",
        "11_collocations.csv",
        "12_questions.csv",
        "13_question_options.csv",
    ):
        original = read(filename, FIRST_FIVE)
        combined = read(filename)
        combined_prefix = combined[: len(original)]
        if filename == "12_questions.csv":
            senses_by_id = {
                row["id"]: row for row in read("05_word_senses.csv", FIRST_FIVE)
            }
            examples_by_id = {
                row["id"]: row for row in read("10_examples.csv", FIRST_FIVE)
            }
            original = [dict(row) for row in original]
            for row in original:
                row["is_context_hint"] = "false"
                row["context_for_multiple_meaning"] = "false"
                if row["stem"].startswith("Which word means: "):
                    row["stem"] = row["stem"][
                        len("Which word means: "):
                    ].removesuffix("?")
                if (
                    row["answer_form"] == "option"
                    and row["example_id"]
                    and row["prompt_hint"]
                    == "Choose the word that completes the sentence."
                ):
                    example = examples_by_id[row["example_id"]]
                    row["stem"] = (
                        f'{example["sentence_en"]}\n\n'
                        f'句中“{example["target_span"]}”是什么意思？'
                    )
                    row["prompt_hint"] = "根据句子选择目标单词的完整中文释义。"
                    row["correct_answer"] = senses_by_id[row["sense_id"]][
                        "definition_zh"
                    ]
                    row["translation_zh"] = senses_by_id[row["sense_id"]][
                        "definition_zh"
                    ]
                    row["is_active"] = "true"
                    row["is_context_hint"] = "true"
                    row["context_for_multiple_meaning"] = str(
                        bool(
                            re.search(
                                r";\s*or\s+",
                                senses_by_id[row["sense_id"]]["definition_en"],
                                re.IGNORECASE,
                            )
                        )
                    ).lower()
        elif filename == "13_question_options.csv":
            original_questions = read("12_questions.csv", FIRST_FIVE)
            context_question_ids = {
                row["id"]
                for row in original_questions
                if row["answer_form"] == "option"
                and row["example_id"]
                and row["prompt_hint"]
                == "Choose the word that completes the sentence."
            }
            senses_by_id = {
                row["id"]: row for row in read("05_word_senses.csv", FIRST_FIVE)
            }
            original = [dict(row) for row in original]
            for row in original:
                if row["question_id"] in context_question_ids:
                    row["option_text"] = senses_by_id[row["target_sense_id"]][
                        "definition_zh"
                    ]
        if combined_prefix != original:
            errors.append(f"Levels 1-5 prefix changed in {filename}")

    sense_ids = {row["id"] for row in senses}
    word_ids = {row["id"] for row in words}
    for row in senses:
        if row["word_id"] not in word_ids:
            errors.append(f"Sense references missing word: {row['id']}")
        if not row["definition_en"].strip() or not row["definition_zh"].strip():
            errors.append(f"Incomplete definition: {row['id']}")
        if len(row["definition_en"]) > 220:
            errors.append(f"Definition exceeds 220 characters: {row['id']}")
        if re.search(
            r"\b(baseball|american football|obsolete|archaic|formerly)\b",
            row["definition_en"],
            re.IGNORECASE,
        ):
            errors.append(f"Obscure or stale definition selected: {row['id']}")
        if row["review_status"] != "approved" or row["human_review"] != "false":
            errors.append(f"Sense is not prototype-approved: {row['id']}")

    assignment_by_level: Counter[int] = Counter()
    for row in assignments:
        if row["placement_type"] == "new":
            assignment_by_level[int(row["level_number"])] += 1
        if row["sense_id"] not in sense_ids:
            errors.append(f"Assignment references missing sense: {row['sense_id']}")

    level_by_number = {int(row["level_number"]): row for row in levels}
    for level in range(1, BAND4_LAST_LEVEL + 1):
        metadata = level_by_number[level]
        target = int(metadata["new_sense_target"])
        if target != assignment_by_level[level]:
            errors.append(
                f"Level {level} target {target} != assignments {assignment_by_level[level]}"
            )
        total_slots = (
            target
            + int(metadata["collocation_target"])
            + int(metadata["review_target"])
        )
        if total_slots != 80:
            errors.append(f"Level {level} has {total_slots} learning slots")
        if level <= 5 and target != 45:
            errors.append(f"Reviewed Level {level} no longer has 45 new senses")
        if (
            level >= BAND4_FIRST_GENERATED_LEVEL
            and abs(target - BAND4_TARGET_NEW_SENSES) > 5
        ):
            errors.append(
                f"Level {level} target {target} outside expected "
                f"{BAND4_TARGET_NEW_SENSES} +/- 5"
            )

    if int(level_by_number[BAND4_LAST_LEVEL + 1]["band_id"]) != 2:
        errors.append(
            f"Level {BAND4_LAST_LEVEL + 1} must be the first Band 4.5 level"
        )

    examples_by_sense: Counter[str] = Counter(row["sense_id"] for row in examples)
    for row in examples:
        target_count = len(
            re.findall(
                rf"\b{re.escape(row['target_span'])}\b",
                row["sentence_en"],
                re.IGNORECASE,
            )
        )
        if target_count != 1:
            errors.append(
                f"Example target appears {target_count} times: {row['id']}"
            )
    level_by_sense = {
        row["sense_id"]: int(row["level_number"])
        for row in assignments
        if row["placement_type"] == "new"
    }
    questions_by_sense: Counter[str] = Counter(row["sense_id"] for row in questions)
    for sense_id in sense_ids:
        if examples_by_sense[sense_id] != 2:
            errors.append(
                f"Sense {sense_id} has {examples_by_sense[sense_id]} examples"
            )
        expected_questions = 12 if level_by_sense.get(sense_id, 999) <= 5 else 3
        if questions_by_sense[sense_id] != expected_questions:
            errors.append(
                f"Sense {sense_id} has {questions_by_sense[sense_id]} questions"
            )

    options_by_question: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in options:
        options_by_question[row["question_id"]].append(row)
        if row["target_sense_id"] and row["target_sense_id"] not in sense_ids:
            errors.append(f"Option references missing sense: {row['id']}")

    for question in questions:
        if question["sense_id"] not in sense_ids:
            errors.append(f"Question references missing sense: {question['id']}")
        if (
            question["answer_form"] == "option"
            and question["example_id"]
            and question["prompt_hint"]
            == "Choose the word that completes the sentence."
        ):
            errors.append(
                "Old ambiguous context-option format remains: "
                f"{question['id']}"
            )
        if question.get("is_context_hint") == "true":
            if question["prompt_hint"] != "根据句子选择目标单词的完整中文释义。":
                errors.append(f"Context hint has the wrong prompt: {question['id']}")
            if not question["example_id"]:
                errors.append(f"Context hint lacks an example: {question['id']}")
        if question["stem"].startswith("Which word means: "):
            errors.append(f"Redundant English stem prefix remains: {question['id']}")
        if question["answer_form"] == "option":
            question_options = options_by_question[question["id"]]
            if len(question_options) != 4:
                errors.append(f"Choice question lacks four options: {question['id']}")
                continue
            if sum(row["is_correct"] == "true" for row in question_options) != 1:
                errors.append(
                    f"Choice question lacks one correct option: {question['id']}"
                )
            if len({row["option_text"] for row in question_options}) != 4:
                errors.append(f"Choice question has duplicate text: {question['id']}")
        elif options_by_question[question["id"]]:
            errors.append(f"Keyboard question has options: {question['id']}")

    form_keys = Counter(
        (row["sense_id"], row["form_type"], row["form_text"]) for row in forms
    )
    if any(count > 1 for count in form_keys.values()):
        errors.append("Duplicate word-form rows")

    if errors:
        return fail(errors)

    targets = [
        int(level_by_number[level]["new_sense_target"])
        for level in range(BAND4_FIRST_GENERATED_LEVEL, BAND4_LAST_LEVEL + 1)
    ]
    print("BAND 4.0 VALIDATION PASSED")
    print(f"- levels: {len(levels)}")
    print(f"- words/senses: {len(words)}")
    print(f"- examples: {len(examples)}")
    print(f"- questions: {len(questions)}")
    print(f"- options: {len(options)}")
    print(f"- forms: {len(forms)}")
    print(
        f"- Level {BAND4_FIRST_GENERATED_LEVEL}-{BAND4_LAST_LEVEL} "
        f"target range: {min(targets)}-{max(targets)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
