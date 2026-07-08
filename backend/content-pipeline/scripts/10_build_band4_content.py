from __future__ import annotations

import csv
import re
import uuid
from collections import Counter, defaultdict
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parents[1]
CONSTRUCTED = ROOT / "constructed_data"
FIRST_FIVE = CONSTRUCTED / "levels_001_005" / "supabase_import"
CURRICULUM = CONSTRUCTED / "curriculum_10000_v1" / "01_curriculum_headwords.csv"
ECDICT = ROOT / "sources" / "ECDICT" / "ecdict.csv"
OXFORD = ROOT / "sources" / "words" / "data" / "oxford-5k.csv"
TOPIC_MAP = ROOT / "input" / "ielts_topic_map.csv"
OUTPUT = CONSTRUCTED / "band_4_0_v1"
IMPORT = OUTPUT / "supabase_import"

ID_NAMESPACE = uuid.UUID("e2c8727f-fdfb-4b76-91c6-3ea4dd4fc920")
ECDICT_SOURCE_ID = "20bba4df-8a16-5e63-b73e-951692d95379"
GENERATION_VERSION = "band_4_0_ai_reviewed_v1"
BAND4_FIRST_GENERATED_LEVEL = 6
BAND4_LAST_LEVEL = 33
BAND4_TARGET_NEW_SENSES = 45
BAND4_LEVEL_SHIFT = 54 - BAND4_LAST_LEVEL

COPY_FILES = (
    "01_content_sources.csv",
    "02_topic_clusters.csv",
)

DATA_FILES = (
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
)

FORM_TYPES = {
    "n.": {"plural"},
    "v.": {"past", "past_participle", "present_participle", "third_person_singular"},
    "adj.": {"comparative", "superlative"},
    "adv.": {"comparative", "superlative"},
}

EXCHANGE_TYPES = {
    "p": "past",
    "d": "past_participle",
    "i": "present_participle",
    "3": "third_person_singular",
    "r": "comparative",
    "t": "superlative",
    "s": "plural",
}

POS_PREFIXES = (
    ("n.", "n."),
    ("v.", "v."),
    ("vt.", "v."),
    ("vi.", "v."),
    ("adj.", "adj."),
    ("a.", "adj."),
    ("adv.", "adv."),
    ("ad.", "adv."),
    ("prep.", "prep."),
    ("pron.", "pron."),
    ("conj.", "conj."),
    ("num.", "num."),
    ("interj.", "exclam."),
)

SPECIAL_CONTENT = {
    "smartphone": {
        "definition_en": "a mobile phone that connects to the internet and runs apps",
        "definition_zh": "智能手机",
        "part_of_speech": "n.",
    },
    "since": {
        "definition_en": "because; or from a past time until now",
        "definition_zh": "因为；自从",
        "part_of_speech": "conj.",
        "context_example_en": "I have lived here since 2020.",
        "context_example_zh": "我从2020年起就一直住在这里。",
    },
    "out": {
        "definition_en": "away from the inside of a place; not at home or work",
        "definition_zh": "外出；在外",
        "part_of_speech": "adv.",
    },
    "hit": {
        "definition_en": "an act of hitting something; or a very successful song, movie, or product",
        "definition_zh": "打击；热门作品",
        "part_of_speech": "n.",
        "context_example_en": "The new song became a hit around the world.",
        "context_example_zh": "这首新歌成了风靡全球的热门作品。",
    },
    "castle": {
        "definition_en": "a large strong building where a ruler or noble family lived",
        "definition_zh": "城堡",
        "part_of_speech": "n.",
    },
    "headache": {
        "definition_en": "a continuous pain in the head",
        "definition_zh": "头痛",
        "part_of_speech": "n.",
    },
    "run": {
        "definition_en": "to move quickly on foot; or to operate or manage something",
        "definition_zh": "跑；运行；管理",
        "part_of_speech": "v.",
        "context_example_en": "She can run a small restaurant near the station.",
        "context_example_zh": "她在车站附近经营一家小餐馆。",
    },
    "shoot": {
        "definition_en": "to fire a gun; or to take a photograph or video",
        "definition_zh": "射击；拍摄",
        "part_of_speech": "v.",
        "context_example_en": "They will shoot the video tomorrow.",
        "context_example_zh": "他们明天会拍摄这段视频。",
    },
    "gun": {
        "definition_en": "a weapon that fires bullets",
        "definition_zh": "枪",
        "part_of_speech": "n.",
    },
    "dry": {
        "context_example_en": "The clothes are dry now.",
        "context_example_zh": "这些衣服现在已经干了。",
    },
}


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, rows: list[dict[str, object]], headers: Iterable[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(headers), extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def stable_id(kind: str, key: str) -> str:
    return str(uuid.uuid5(ID_NAMESPACE, f"{kind}:{key}"))


def normalized_word(value: str) -> str:
    return re.sub(r"\s+", " ", value.strip().lower())


def has_multiple_meanings(definition_en: str) -> bool:
    """Conservative marker: only explicitly separated alternative meanings."""
    return bool(re.search(r";\s*or\s+", definition_en, re.IGNORECASE))


def first_source_line(value: str) -> str:
    for line in value.replace("\\n", "\n").splitlines():
        line = re.sub(r"\s+", " ", line).strip()
        if line and not line.startswith("["):
            return line
    return ""


def source_lines(value: str) -> list[str]:
    return [
        re.sub(r"\s+", " ", line).strip()
        for line in value.replace("\\n", "\n").splitlines()
        if re.sub(r"\s+", " ", line).strip()
        and not re.sub(r"\s+", " ", line).strip().startswith("[")
    ]


def line_matches_pos(line: str, pos: str) -> bool:
    lowered = line.lower()
    prefixes = {
        "n.": ("n.", "n "),
        "v.": ("v.", "v ", "vt.", "vt ", "vi.", "vi "),
        "adj.": ("adj.", "adj ", "a.", "a ", "s.", "s "),
        "adv.": ("adv.", "adv ", "ad.", "ad ", "r.", "r "),
        "prep.": ("prep.", "prep ", "r.", "r "),
        "pron.": ("pron.", "pron ", "s.", "s "),
        "conj.": ("conj.", "conj "),
        "num.": ("num.", "num ", "n.", "n ", "s.", "s "),
        "exclam.": ("interj.", "interj ", "exclam.", "exclam "),
    }
    return lowered.startswith(prefixes.get(pos, ()))


def select_source_line(value: str, pos: str) -> str:
    lines = source_lines(value)
    return next((line for line in lines if line_matches_pos(line, pos)), lines[0] if lines else "")


def infer_pos(english: str, chinese: str) -> str:
    lowered = f"{english} {chinese}".lower().strip()
    for prefix, result in POS_PREFIXES:
        if lowered.startswith(prefix):
            return result
    return "n."


def clean_english(value: str, headword: str, pos: str) -> str:
    line = select_source_line(value, pos)
    line = re.sub(
        r"^(?:interj|exclam|prep|pron|conj|num|adj|adv|vt|vi|ad|n|v|a|s|r)\.?\s*",
        "",
        line,
        flags=re.IGNORECASE,
    )
    line = line.strip(" ;,.")
    line = re.sub(r"\s*\([^)]*(?:obsolete|archaic|formerly)[^)]*\)", "", line, flags=re.IGNORECASE)
    if not line:
        return SPECIAL_CONTENT.get(headword, {}).get(
            "definition_en", f"the vocabulary word {headword}"
        )
    if len(line) > 220:
        line = line[:217].rsplit(" ", 1)[0] + "..."
    return line


def clean_chinese(value: str, headword: str, pos: str) -> str:
    line = select_source_line(value, pos)
    line = re.sub(
        r"^(?:interj|exclam|prep|pron|conj|num|adj|adv|vt|vi|ad|n|v|a|s|r)\.?\s*",
        "",
        line,
        flags=re.IGNORECASE,
    )
    line = re.sub(r"\[[^\]]+\]", "", line)
    parts = [
        part.strip()
        for part in re.split(r"[,，;；]", line)
        if part.strip()
    ]
    if not parts:
        return SPECIAL_CONTENT.get(headword, {}).get("definition_zh", headword)
    return "；".join(parts[:3])


def cefr(value: str) -> str:
    choices = [
        item.strip().upper()
        for item in value.split("|")
        if item.strip().upper() in {"A1", "A2", "B1", "B2", "C1", "C2"}
    ]
    return choices[0] if choices else "A2"


def parse_forms(exchange: str, pos: str, headword: str) -> list[tuple[str, str]]:
    allowed = FORM_TYPES.get(pos, set())
    result: list[tuple[str, str]] = []
    seen: set[tuple[str, str]] = set()
    for part in exchange.split("/"):
        code, separator, form = part.partition(":")
        form_type = EXCHANGE_TYPES.get(code)
        form = normalized_word(form)
        key = (form_type or "", form)
        if (
            separator
            and form_type in allowed
            and form
            and form != headword
            and key not in seen
        ):
            seen.add(key)
            result.append((form_type, form))
    return result


def level_titles() -> dict[int, tuple[str, str]]:
    titles: dict[int, tuple[str, str]] = {}
    for row in read_csv(TOPIC_MAP):
        start_text, separator, end_text = row["approx_levels"].partition("-")
        start = int(start_text)
        end = int(end_text if separator else start_text)
        topic_id = re.sub(
            r"[^a-z0-9]+",
            "_",
            f'{row["topic"]}_{row["subtopic"]}'.lower(),
        ).strip("_")
        title = f'{row["topic"]}: {row["subtopic"]}'
        for level in range(start, end + 1):
            titles[level] = (topic_id, title)
    return titles


def topic_titles() -> dict[str, tuple[str, str]]:
    titles: dict[str, tuple[str, str]] = {}
    for row in read_csv(TOPIC_MAP):
        topic_id = re.sub(
            r"[^a-z0-9]+",
            "_",
            f'{row["topic"]}_{row["subtopic"]}'.lower(),
        ).strip("_")
        titles[topic_id] = (topic_id, f'{row["topic"]}: {row["subtopic"]}')
    return titles


def select_new_candidates(
    first_five_words: set[str],
) -> tuple[list[dict[str, str]], dict[int, str]]:
    rows = [
        row
        for row in read_csv(CURRICULUM)
        if 6 <= int(row["level_number"]) <= 54
        and normalized_word(row["headword"]) not in first_five_words
    ]
    rows.sort(key=lambda row: (int(row["level_number"]), int(row["order_in_level"])))
    if len({normalized_word(row["headword"]) for row in rows}) != len(rows):
        raise ValueError("Band 4 candidate rows contain duplicate headwords")
    return rows, {int(row["level_number"]): row["topic_id"] for row in rows}


def compact_generated_levels(
    candidates: list[dict[str, str]],
) -> tuple[list[dict[str, str]], dict[int, str]]:
    levels = list(range(BAND4_FIRST_GENERATED_LEVEL, BAND4_LAST_LEVEL + 1))
    if not levels:
        raise ValueError("No generated Band 4 levels configured")
    base_size, extra = divmod(len(candidates), len(levels))
    if base_size < BAND4_TARGET_NEW_SENSES - 5:
        raise ValueError(
            "Not enough Band 4 candidates to keep generated levels near "
            f"{BAND4_TARGET_NEW_SENSES} senses"
        )

    reassigned: list[dict[str, str]] = []
    level_topic: dict[int, str] = {}
    cursor = 0
    for index, level in enumerate(levels):
        size = base_size + (1 if index < extra else 0)
        chunk = candidates[cursor: cursor + size]
        cursor += size
        if not chunk:
            raise ValueError(f"No candidates assigned to Level {level}")
        topic_counts = Counter(row["topic_id"] for row in chunk)
        level_topic[level] = topic_counts.most_common(1)[0][0]
        for order, row in enumerate(chunk, start=1):
            copied = dict(row)
            copied["source_level_number"] = row["level_number"]
            copied["level_number"] = str(level)
            copied["order_in_level"] = str(order)
            reassigned.append(copied)

    if cursor != len(candidates):
        raise ValueError("Generated Band 4 level compaction lost candidates")
    return reassigned, level_topic


def load_ecdict(required_words: set[str]) -> dict[str, dict[str, str]]:
    result: dict[str, dict[str, str]] = {}
    with ECDICT.open(encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            word = normalized_word(row["word"])
            if word in required_words and word not in result:
                result[word] = row
                if len(result) == len(required_words):
                    break
    missing = sorted(required_words - result.keys())
    if missing:
        raise ValueError(f"ECDICT is missing {len(missing)} required words: {missing[:10]}")
    return result


def load_oxford_pos(required_words: set[str]) -> dict[str, str]:
    level_order = {"a1": 1, "a2": 2, "b1": 3, "b2": 4, "c1": 5}
    choices: dict[str, list[tuple[int, int, str]]] = defaultdict(list)
    with OXFORD.open(encoding="utf-8-sig", newline="") as handle:
        for row_number, row in enumerate(csv.DictReader(handle)):
            word = normalized_word(row["word"])
            if word not in required_words:
                continue
            mapped = {
                "noun": "n.",
                "verb": "v.",
                "adjective": "adj.",
                "adverb": "adv.",
                "preposition": "prep.",
                "pronoun": "pron.",
                "conjunction": "conj.",
                "number": "num.",
                "exclamation": "exclam.",
            }.get(row["pos"].strip().lower())
            if mapped:
                choices[word].append(
                    (level_order.get(row["level"].strip().lower(), 99), row_number, mapped)
                )
    return {
        word: min(options)[2]
        for word, options in choices.items()
        if options
    }


def choose_distractors(
    target: dict[str, str],
    same_level: list[dict[str, str]],
    all_senses: list[dict[str, str]],
) -> list[dict[str, str]]:
    candidates = [
        row
        for row in same_level
        if row["id"] != target["id"]
        and row["part_of_speech"] == target["part_of_speech"]
    ]
    if len(candidates) < 3:
        candidates.extend(
            row
            for row in same_level
            if row["id"] != target["id"] and row not in candidates
        )
    if len(candidates) < 3:
        candidates.extend(
            row
            for row in all_senses
            if row["id"] != target["id"]
            and row["part_of_speech"] == target["part_of_speech"]
            and row not in candidates
        )
    candidates.sort(
        key=lambda row: stable_id(
            "distractor-order", f'{target["id"]}:{row["id"]}'
        )
    )
    return candidates[:3]


def example_sentence(headword: str, pos: str, index: int) -> tuple[str, str]:
    """Fallback app-authored examples for generated Band 4 prototype content."""
    by_pos = {
        "n.": (
            (
                f"The {headword} is important for the campus project.",
                f"这个{headword}对校园项目很重要。",
            ),
            (
                f"Please check the {headword} before class starts.",
                f"请在上课前检查这个{headword}。",
            ),
        ),
        "v.": (
            (
                f"Students need to {headword} their ideas clearly.",
                f"学生需要清楚地{headword}他们的想法。",
            ),
            (
                f"I will {headword} the answer after the lecture.",
                f"我会在讲座后{headword}这个答案。",
            ),
        ),
        "adj.": (
            (
                f"The {headword} answer was easy to understand.",
                f"这个{headword}的答案很容易理解。",
            ),
            (
                f"Her tutor gave a {headword} example in class.",
                f"她的导师在课上给了一个{headword}的例子。",
            ),
        ),
        "adv.": (
            (
                f"She answered the question {headword} during the tutorial.",
                f"她在辅导课上{headword}回答了问题。",
            ),
            (
                f"He explained the problem {headword} to his group.",
                f"他向小组{headword}解释了这个问题。",
            ),
        ),
    }
    templates = by_pos.get(
        pos,
        (
            (
                f"The professor used {headword} in a simple sentence.",
                f"教授在一个简单句子中使用了{headword}。",
            ),
            (
                f"I noticed {headword} in the reading passage.",
                f"我在阅读文章中注意到了{headword}。",
            ),
        ),
    )
    start = (index - 1) % len(templates)
    for offset in range(len(templates)):
        sentence, translation = templates[(start + offset) % len(templates)]
        if len(re.findall(rf"\b{re.escape(headword)}\b", sentence, re.IGNORECASE)) == 1:
            return sentence, translation
    raise ValueError(f"Could not create an unambiguous example for {headword}")
def build() -> None:
    IMPORT.mkdir(parents=True, exist_ok=True)
    for filename in COPY_FILES:
        rows = read_csv(FIRST_FIVE / filename)
        write_csv(IMPORT / filename, rows, rows[0].keys())
    write_topic_upsert(read_csv(FIRST_FIVE / "02_topic_clusters.csv"))

    first_five = {name: read_csv(FIRST_FIVE / name) for name in DATA_FILES}
    first_five_words = {normalized_word(row["headword"]) for row in first_five["04_words.csv"]}
    source_candidates, _ = select_new_candidates(first_five_words)
    candidates, compact_level_topics = compact_generated_levels(source_candidates)
    required_words = {normalized_word(row["headword"]) for row in candidates}
    ecdict = load_ecdict(required_words)
    oxford_pos = load_oxford_pos(required_words)
    titles = level_titles()
    titles_by_topic = topic_titles()

    words: list[dict[str, object]] = list(first_five["04_words.csv"])
    senses: list[dict[str, object]] = list(first_five["05_word_senses.csv"])
    forms: list[dict[str, object]] = list(first_five["06_word_forms.csv"])
    pronunciations: list[dict[str, object]] = list(first_five["07_pronunciations.csv"])
    assignments: list[dict[str, object]] = list(first_five["08_level_sense_assignments.csv"])
    evidence: list[dict[str, object]] = list(first_five["09_usage_evidence.csv"])
    examples: list[dict[str, object]] = list(first_five["10_examples.csv"])
    collocations: list[dict[str, object]] = list(first_five["11_collocations.csv"])
    questions: list[dict[str, object]] = list(first_five["12_questions.csv"])
    first_five_senses_by_id = {
        row["id"]: row for row in first_five["05_word_senses.csv"]
    }
    first_five_examples_by_id = {
        row["id"]: row for row in first_five["10_examples.csv"]
    }
    # Convert reviewed sentence-completion questions into contextual meaning
    # questions. The complete sentence remains visible, while the learner
    # chooses the target word's Chinese definition. This avoids multiple
    # grammatically plausible English completions.
    for question in questions:
        question["is_context_hint"] = "false"
        question["context_for_multiple_meaning"] = "false"
        if question["stem"].startswith("Which word means: "):
            question["stem"] = question["stem"][
                len("Which word means: "):
            ].removesuffix("?")
        if (
            question["answer_form"] == "option"
            and question["example_id"]
            and question["prompt_hint"]
            == "Choose the word that completes the sentence."
        ):
            example = first_five_examples_by_id[question["example_id"]]
            sense = first_five_senses_by_id[question["sense_id"]]
            question["stem"] = (
                f'{example["sentence_en"]}\n\n'
                f'句中“{example["target_span"]}”是什么意思？'
            )
            question["prompt_hint"] = "根据句子选择目标单词的完整中文释义。"
            question["correct_answer"] = sense["definition_zh"]
            question["translation_zh"] = sense["definition_zh"]
            question["is_active"] = "true"
            question["is_context_hint"] = "true"
            question["context_for_multiple_meaning"] = str(
                has_multiple_meanings(sense["definition_en"])
            ).lower()
    options: list[dict[str, object]] = list(first_five["13_question_options.csv"])
    question_by_id = {row["id"]: row for row in questions}
    for option in options:
        question = question_by_id.get(option["question_id"])
        if (
            question
            and question["prompt_hint"]
            == "根据句子选择目标单词的完整中文释义。"
        ):
            option["option_text"] = first_five_senses_by_id[
                option["target_sense_id"]
            ]["definition_zh"]

    level_senses: dict[int, list[dict[str, str]]] = defaultdict(list)
    generated_senses: list[dict[str, str]] = []
    form_count_by_level: Counter[int] = Counter()

    for order, candidate in enumerate(candidates, start=1):
        level = int(candidate["level_number"])
        headword = normalized_word(candidate["headword"])
        source = ecdict[headword]
        english_line = first_source_line(source.get("definition", ""))
        chinese_line = first_source_line(source.get("translation", ""))
        pos = SPECIAL_CONTENT.get(headword, {}).get(
            "part_of_speech",
            oxford_pos.get(headword, infer_pos(english_line, chinese_line)),
        )
        definition_zh = SPECIAL_CONTENT.get(headword, {}).get(
            "definition_zh",
            clean_chinese(source.get("translation", ""), headword, pos),
        )
        has_matching_english_sense = any(
            line_matches_pos(line, pos)
            for line in source_lines(source.get("definition", ""))
        )
        definition_en = SPECIAL_CONTENT.get(headword, {}).get(
            "definition_en",
            (
                clean_english(source.get("definition", ""), headword, pos)
                if has_matching_english_sense
                else f'the English expression meaning “{definition_zh}”'
            ),
        )
        word_id = stable_id("word", headword)
        sense_key = f"band4:l{level}:{headword}:{pos}:1"
        sense_id = stable_id("sense", sense_key)

        words.append(
            {
                "id": word_id,
                "headword": headword,
                "display_spelling": candidate["display_spelling"] or headword,
                "frequency_rank": candidate["bnc_rank"] or candidate["frq_rank"],
                "human_review": "false",
            }
        )
        sense = {
            "id": sense_id,
            "word_id": word_id,
            "headword": headword,
            "part_of_speech": pos,
            "sense_number": "1",
            "definition_en": definition_en,
            "definition_zh": definition_zh,
            "vocabulary_role": candidate["vocabulary_role"],
            "difficulty_band": "4.0",
            "cefr_level": cefr(candidate["cefr_levels"]),
            "register": "",
            "is_primary": "true",
            "source_id": ECDICT_SOURCE_ID,
            "human_review": "false",
            "review_status": "approved",
            "level_number": str(level),
        }
        generated_senses.append(sense)
        level_senses[level].append(sense)
        senses.append({key: value for key, value in sense.items() if key not in {"headword", "level_number"}})
        assignments.append(
            {
                "level_number": str(level),
                "sense_id": sense_id,
                "placement_type": "new",
                "order_in_level": str(len(level_senses[level])),
                "vocabulary_role": candidate["vocabulary_role"],
                "is_required": "true",
                "human_review": "false",
            }
        )

        for form_type, form_text in parse_forms(source.get("exchange", ""), pos, headword):
            forms.append(
                {
                    "id": stable_id("form", f"{sense_id}:{form_type}:{form_text}"),
                    "word_id": word_id,
                    "sense_id": sense_id,
                    "form_type": form_type,
                    "form_text": form_text,
                    "source_id": ECDICT_SOURCE_ID,
                    "human_review": "false",
                }
            )
            form_count_by_level[level] += 1

        phonetic = source.get("phonetic", "").strip()
        if phonetic:
            pronunciations.append(
                {
                    "id": stable_id("pronunciation", sense_id),
                    "word_id": word_id,
                    "sense_id": sense_id,
                    "ipa_us": phonetic,
                    "audio_path": "",
                    "source_id": ECDICT_SOURCE_ID,
                    "human_review": "false",
                }
            )

        evidence.append(
            {
                "id": stable_id("evidence", sense_id),
                "sense_id": sense_id,
                "source_id": ECDICT_SOURCE_ID,
                "quoted_text": select_source_line(
                    source.get("definition", ""), pos
                ) or definition_en,
                "matched_span": headword,
                "source_locator": "ECDICT local licensed dataset",
                "usage_analysis": "Source-backed definition used to construct prototype practice content.",
                "paper_types": "{}",
                "copyright_status": "licensed",
                "human_review": "false",
            }
        )

        special = SPECIAL_CONTENT.get(headword, {})
        example_specs = (
            (
                special["context_example_en"],
                special["context_example_zh"],
            )
            if "context_example_en" in special
            else example_sentence(headword, pos, 1),
            example_sentence(headword, pos, 2),
        )
        for sort_order, (sentence, translation) in enumerate(example_specs, start=1):
            examples.append(
                {
                    "id": stable_id("example", f"{sense_id}:{sort_order}"),
                    "sense_id": sense_id,
                    "sentence_en": sentence,
                    "translation_zh": translation,
                    "target_span": headword,
                    "origin": "ai_generated_from_sources",
                    "difficulty_band": "4.0",
                    "source_id": ECDICT_SOURCE_ID,
                    "review_status": "approved",
                    "human_review": "false",
                    "audio_path": "",
                    "sort_order": str(sort_order),
                }
            )

    example_one_by_sense = {
        row["sense_id"]: row
        for row in examples
        if row["sort_order"] == "1"
    }
    all_generated = generated_senses
    for sense in generated_senses:
        level = int(sense["level_number"])
        distractors = choose_distractors(sense, level_senses[level], all_generated)
        if len(distractors) != 3:
            raise ValueError(f"Not enough distractors for {sense['headword']}")

        specs = (
            (
                "meaning_en",
                sense["definition_en"],
                "Choose the word that matches the English meaning.",
                "",
                sense["headword"],
                False,
                "12000",
            ),
            (
                "context_hint",
                (
                    f'{example_one_by_sense[sense["id"]]["sentence_en"]}\n\n'
                    f'句中“{sense["headword"]}”是什么意思？'
                ),
                "根据句子选择目标单词的完整中文释义。",
                stable_id("example", f"{sense['id']}:1"),
                sense["definition_zh"],
                True,
                "15000",
            ),
        )
        for (
            kind,
            stem,
            hint,
            example_id,
            correct_answer,
            is_context_hint,
            expected_time,
        ) in specs:
            question_id = stable_id("question", f"{sense['id']}:{kind}")
            questions.append(
                {
                    "id": question_id,
                    "sense_id": sense["id"],
                    "question_type_id": "2",
                    "type_code": "2",
                    "category": "new_word",
                    "answer_form": "option",
                    "word_id": sense["word_id"],
                    "example_id": example_id,
                    "stem": stem,
                    "correct_answer": correct_answer,
                    "difficulty": "4.0",
                    "is_active": "true",
                    "generation_version": GENERATION_VERSION,
                    "human_review": "false",
                    "prompt_hint": hint,
                    "translation_zh": sense["definition_zh"],
                    "expected_time_ms": expected_time,
                    "is_context_hint": str(is_context_hint).lower(),
                    "context_for_multiple_meaning": str(
                        is_context_hint
                        and has_multiple_meanings(sense["definition_en"])
                    ).lower(),
                }
            )
            option_senses = [sense, *distractors]
            option_senses.sort(
                key=lambda row: stable_id(
                    "option-order", f"{question_id}:{row['id']}"
                )
            )
            for option_order, option_sense in enumerate(option_senses, start=1):
                options.append(
                    {
                        "id": stable_id(
                            "option", f"{question_id}:{option_sense['id']}"
                        ),
                        "question_id": question_id,
                        "option_text": (
                            option_sense["definition_zh"]
                            if is_context_hint
                            else option_sense["headword"]
                        ),
                        "target_sense_id": option_sense["id"],
                        "is_correct": str(option_sense["id"] == sense["id"]).lower(),
                        "sort_order": str(option_order),
                        "human_review": "false",
                    }
                )

        spelling_question_id = stable_id("question", f"{sense['id']}:spelling")
        questions.append(
            {
                "id": spelling_question_id,
                "sense_id": sense["id"],
                "question_type_id": "1",
                "type_code": "1",
                "category": "new_word",
                "answer_form": "keyboard",
                "word_id": sense["word_id"],
                "example_id": stable_id("example", f"{sense['id']}:2"),
                "stem": (
                    f'{sense["headword"][0]}{"_" * max(3, len(sense["headword"]) - 1)} '
                    f'means "{sense["definition_en"]}".'
                ),
                "correct_answer": sense["headword"],
                "difficulty": "4.0",
                "is_active": "true",
                "generation_version": GENERATION_VERSION,
                "human_review": "false",
                "prompt_hint": "Complete the word using the first-letter hint.",
                "translation_zh": sense["definition_zh"],
                "expected_time_ms": "18000",
                "is_context_hint": "false",
                "context_for_multiple_meaning": "false",
            }
        )

    level_rows = read_csv(FIRST_FIVE / "03_levels.csv")
    level_by_number = {int(row["level_number"]): row for row in level_rows}
    for level in range(BAND4_FIRST_GENERATED_LEVEL, BAND4_LAST_LEVEL + 1):
        target = len(level_senses[level])
        reinforcement = min(5, form_count_by_level[level])
        topic_id, title = titles_by_topic.get(
            compact_level_topics[level],
            titles[level],
        )
        row = level_by_number[level]
        row.update(
            {
                "band_id": "1",
                "topic_cluster_id": topic_id,
                "title": title,
                "order_in_band": str(level),
                "new_sense_target": str(target),
                "collocation_target": str(reinforcement),
                "review_target": str(80 - target - reinforcement),
                "curriculum_version": "2",
                "human_review": "false",
            }
        )

    for level in range(BAND4_LAST_LEVEL + 1, 241):
        shifted_source = level_by_number.get(level + BAND4_LEVEL_SHIFT)
        if shifted_source is None:
            continue
        row = level_by_number[level]
        row.update(
            {
                "band_id": shifted_source["band_id"],
                "topic_cluster_id": shifted_source["topic_cluster_id"],
                "title": shifted_source["title"],
                "order_in_band": shifted_source["order_in_band"],
                "new_sense_target": shifted_source["new_sense_target"],
                "collocation_target": shifted_source["collocation_target"],
                "review_target": shifted_source["review_target"],
                "curriculum_version": shifted_source["curriculum_version"],
                "human_review": shifted_source["human_review"],
            }
        )

    band_level_rows = [level_by_number[level] for level in range(1, 241)]
    write_csv(IMPORT / "03_levels.csv", band_level_rows, band_level_rows[0].keys())
    write_level_upsert(band_level_rows)

    payloads = {
        "04_words.csv": words,
        "05_word_senses.csv": senses,
        "06_word_forms.csv": forms,
        "07_pronunciations.csv": pronunciations,
        "08_level_sense_assignments.csv": assignments,
        "09_usage_evidence.csv": evidence,
        "10_examples.csv": examples,
        "11_collocations.csv": collocations,
        "12_questions.csv": questions,
        "13_question_options.csv": options,
    }
    for filename, rows in payloads.items():
        write_csv(IMPORT / filename, rows, rows[0].keys())

    write_manifest(payloads, band_level_rows)
    print(
        "Built Band 4.0 package: "
        f"{len(words)} words, {len(senses)} senses, "
        f"{len(questions)} questions, {len(options)} options."
    )


def write_level_upsert(rows: list[dict[str, str]]) -> None:
    values = []
    for row in rows:
        quoted_title = row["title"].replace("'", "''")
        quoted_topic = row["topic_cluster_id"].replace("'", "''")
        values.append(
            "("
            f"{row['level_number']},{row['band_id']},'{quoted_topic}',"
            f"'{quoted_title}',{row['order_in_band']},{row['new_sense_target']},"
            f"{row['collocation_target']},{row['review_target']},"
            f"{row['curriculum_version']},{row['human_review']}"
            ")"
        )
    sql = """begin;
insert into public.levels (
  level_number, band_id, topic_cluster_id, title, order_in_band,
  new_sense_target, collocation_target, review_target,
  curriculum_version, human_review
)
values
  %s
on conflict (level_number) do update
set band_id = excluded.band_id,
    topic_cluster_id = excluded.topic_cluster_id,
    title = excluded.title,
    order_in_band = excluded.order_in_band,
    new_sense_target = excluded.new_sense_target,
    collocation_target = excluded.collocation_target,
    review_target = excluded.review_target,
    curriculum_version = excluded.curriculum_version,
    human_review = excluded.human_review,
    updated_at = now();
commit;
""" % ",\n  ".join(values)
    (IMPORT / "03_band_levels_upsert.sql").write_text(sql, encoding="utf-8")


def write_manifest(
    payloads: dict[str, list[dict[str, object]]],
    levels: list[dict[str, str]],
) -> None:
    band4_levels = [
        row for row in levels
        if int(row["level_number"]) <= BAND4_LAST_LEVEL
    ]
    generated_targets = [
        int(row["new_sense_target"])
        for row in band4_levels
        if int(row["level_number"]) >= BAND4_FIRST_GENERATED_LEVEL
    ]
    text = f"""# Band 4.0 Supabase Import

Generated by `scripts/10_build_band4_content.py`.

## Scope

- Band 4.0 Levels: 1-{BAND4_LAST_LEVEL}
- Unique words/senses: {len(payloads["05_word_senses.csv"]):,}
- Questions: {len(payloads["12_questions.csv"]):,}
- Choice options: {len(payloads["13_question_options.csv"]):,}
- Level 1-5 targets: 45 new senses each
- Level 6-{BAND4_LAST_LEVEL} targets: compact {min(generated_targets)}-{max(generated_targets)} new senses each

Levels 1-5 preserve the reviewed package. Levels 6-{BAND4_LAST_LEVEL} compact
the remaining Band 4 candidate curriculum into real study-sized levels instead
of stretching the same 1,465 senses across 54 thin levels. They are suitable for
engineering and product testing. A separate human editorial pass is still
required before any public release.

## Import order

1. Apply all migrations through `202607060028_due_review_new_word_gate.sql`.
2. If the five-level slice is already loaded, back up the database and run
   `backend/supabase/manual/reset_vocabulary_content_for_rebuild.sql` before
   loading this replacement package.
3. On a clean vocabulary database, import `01_content_sources.csv`. Skip it
   when the same six source rows already exist.
4. `02_topic_clusters.csv` is an audit copy. Run
   `02_topic_clusters_upsert.sql` to create/update the required reference rows.
5. Run `03_band_levels_upsert.sql`.
6. Import files `04` through `13` in numeric order.
7. Run `scripts/11_validate_band4_content.py`.
8. Run `backend/supabase/tests/verify_project_installation.sql`.
"""
    (IMPORT / "README.md").write_text(text, encoding="utf-8")


def sql_text(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def write_topic_upsert(rows: list[dict[str, str]]) -> None:
    values = []
    for row in rows:
        values.append(
            "("
            f"{sql_text(row['id'])},{sql_text(row['topic'])},"
            f"{sql_text(row['subtopic'])},{sql_text(row['paper_types'])}::text[],"
            f"{row['band_min']},{row['band_max']},{row['word_goal']},"
            f"{row['candidate_goal']},{sql_text(row['chinese_learner_priority'])},"
            f"{row['curriculum_version']},{row['human_review']}"
            ")"
        )
    sql = """begin;
insert into public.topic_clusters (
  id, topic, subtopic, paper_types, band_min, band_max,
  word_goal, candidate_goal, chinese_learner_priority,
  curriculum_version, human_review
)
values
  %s
on conflict (id) do update
set topic = excluded.topic,
    subtopic = excluded.subtopic,
    paper_types = excluded.paper_types,
    band_min = excluded.band_min,
    band_max = excluded.band_max,
    word_goal = excluded.word_goal,
    candidate_goal = excluded.candidate_goal,
    chinese_learner_priority = excluded.chinese_learner_priority,
    curriculum_version = excluded.curriculum_version,
    human_review = excluded.human_review,
    updated_at = now();
commit;
""" % ",\n  ".join(values)
    (IMPORT / "02_topic_clusters_upsert.sql").write_text(sql, encoding="utf-8")


if __name__ == "__main__":
    build()

