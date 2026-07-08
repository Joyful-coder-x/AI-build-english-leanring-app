from __future__ import annotations

import csv
import io
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))

from export_csv import EXAMPLES_HEADERS, FORMS_HEADERS, MEANINGS_HEADERS, WORDS_HEADERS, build_rows
from generate_questions import OPTIONS_HEADERS, QUESTIONS_HEADERS, build_question_rows
from pipeline_common import load_config
from validate_packages import validate_package


def load_fixture() -> dict:
    return {
        "level_number": 1,
        "status": "approved",
        "word_count": 1,
        "words": [
            {
                "headword": "family",
                "level_number": 1,
                "phonetic": "/ˈfæməli/",
                "pos_primary": "n.",
                "mnemonic": "fam(familiar)+ily→people you know well→家人",
                "root_affix": None,
                "frequency_rank": 100,
                "meanings": [
                    {
                        "pos": "n.",
                        "definition_zh": "家庭；家人",
                        "definition_en": "a group of people related to each other, especially parents and children",
                        "sort_order": 0,
                    }
                ],
                "forms": [],
                "examples": [
                    {
                        "sentence_en": "She comes from a large family.",
                        "translation_zh": "她来自一个大家庭。",
                        "target_span": "family",
                        "has_audio": False,
                        "sort_order": 0,
                    },
                    {
                        "sentence_en": "The family moved to a new city last year.",
                        "translation_zh": "这家人去年搬到了一个新城市。",
                        "target_span": "family",
                        "has_audio": False,
                        "sort_order": 1,
                    },
                ],
                "distractors": ["class", "office", "team"],
            }
        ],
    }


def assert_validation_error(package: dict, expected: str) -> None:
    errors = validate_package(package, load_config())
    joined = "\n".join(errors)
    assert expected in joined, joined


def test_valid_fixture() -> None:
    package = load_fixture()
    errors = validate_package(package, load_config())
    assert errors == []


def test_missing_mnemonic() -> None:
    package = load_fixture()
    package["words"][0]["mnemonic"] = ""
    assert_validation_error(package, "mnemonic")


def test_missing_examples() -> None:
    package = load_fixture()
    package["words"][0]["examples"] = []
    assert_validation_error(package, "examples must contain at least 2 rows")


def test_bad_target_span() -> None:
    package = load_fixture()
    package["words"][0]["examples"][0]["target_span"] = "missing"
    assert_validation_error(package, "not a literal substring")


def test_bad_distractor_count() -> None:
    package = load_fixture()
    package["words"][0]["distractors"] = ["accept", "continue"]
    assert_validation_error(package, "exactly 3")


def test_duplicate_distractor() -> None:
    package = load_fixture()
    package["words"][0]["distractors"] = ["accept", "accept", "keep"]
    assert_validation_error(package, "duplicate distractors")


def test_csv_headers_and_stable_ids() -> None:
    config = load_config()
    package = load_fixture()
    first = build_rows(package, config)
    second = build_rows(package, config)
    assert first == second
    assert list(first[0][0].keys()) == WORDS_HEADERS
    assert list(first[1][0].keys()) == MEANINGS_HEADERS
    assert list(first[2][0].keys()) == FORMS_HEADERS
    assert list(first[3][0].keys()) == EXAMPLES_HEADERS


def test_questions_and_options() -> None:
    config = load_config()
    package = load_fixture()
    questions, options = build_question_rows(package, config)
    assert list(questions[0].keys()) == QUESTIONS_HEADERS
    assert list(options[0].keys()) == OPTIONS_HEADERS
    assert len(questions) == 8
    assert len(options) == 16
    assert all(q["explanation"] == "" for q in questions)

    for question in [q for q in questions if q["type_code"] == 2]:
        question_options = [o for o in options if o["question_id"] == question["id"]]
        assert len(question_options) == 4
        assert sum(o["is_correct"] == "true" for o in question_options) == 1


def test_csv_roundtrip_shape() -> None:
    config = load_config()
    package = load_fixture()
    words, _, _, _ = build_rows(package, config)
    buffer = io.StringIO()
    writer = csv.DictWriter(buffer, fieldnames=WORDS_HEADERS)
    writer.writeheader()
    writer.writerows(words)
    buffer.seek(0)
    rows = list(csv.DictReader(buffer))
    assert len(rows) == len(words)
    assert rows[0]["id"] == words[0]["id"]


def main() -> int:
    tests = [
        test_valid_fixture,
        test_missing_mnemonic,
        test_missing_examples,
        test_bad_target_span,
        test_bad_distractor_count,
        test_duplicate_distractor,
        test_csv_headers_and_stable_ids,
        test_questions_and_options,
        test_csv_roundtrip_shape,
    ]
    for test in tests:
        test()
        print(f"PASS {test.__name__}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
