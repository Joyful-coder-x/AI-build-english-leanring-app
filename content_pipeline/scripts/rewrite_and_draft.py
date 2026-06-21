"""
rewrite_and_draft.py
--------------------
Step 3 of the content pipeline.

Input:  content_pipeline/output/level_001_packages.todo.json
Output: content_pipeline/packages/level_001_packages.json  (overwrites fixture)

Uses Claude API to rewrite each word's raw definition into A1/A2 learner-friendly content:
  - definition_en:  max 12 words, simple vocabulary, no headword
  - sentence_en:    two original sentences using the exact headword
  - mnemonic:       one memorable English hook

Chinese fields (definition_zh, translation_zh) are set to "[待翻译]" — fill these separately.

Requires: ANTHROPIC_API_KEY environment variable.
Install:  pip install anthropic
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).parent))
from pipeline_common import PACKAGE_PATH, LEVEL_001_DIR, PIPELINE_ROOT

TODO_JSON = LEVEL_001_DIR / "packages.todo.json"
ZH_PLACEHOLDER = "[待翻译]"

_DEFAULT_MODEL = "claude-haiku-4-5-20251001"
_RETRY_DELAY = 2.0
_MAX_RETRIES = 2


def _build_prompt(headword: str, pos: str, definition_raw: str, example_raw: str) -> str:
    ex_note = f"\nSource example: {example_raw}" if example_raw else ""
    return f"""You write content for an English vocabulary app. Learners are native Chinese speakers at CEFR A1/A2 level.

Word: {headword}
Part of speech: {pos}
Source definition: {definition_raw}{ex_note}

Output EXACTLY this JSON — no markdown, no extra text:
{{
  "definition_en": "...",
  "sentence_en_1": "...",
  "sentence_en_2": "...",
  "mnemonic": "..."
}}

Rules:
- definition_en: max 12 words, only A1/A2 vocabulary, must NOT contain "{headword}"
- sentence_en_1: 8–14 words, must contain the EXACT string "{headword}", natural modern English
- sentence_en_2: 8–14 words, must contain the EXACT string "{headword}", different context
- mnemonic: 1 English sentence under 15 words, memorable hint about what "{headword}" means"""


def _extract_json(text: str) -> dict[str, Any]:
    text = text.strip()
    start = text.find("{")
    end = text.rfind("}") + 1
    if start < 0 or end <= start:
        raise ValueError("No JSON object found in response")
    return json.loads(text[start:end])


def _validate_output(headword: str, obj: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    for key in ("definition_en", "sentence_en_1", "sentence_en_2", "mnemonic"):
        if not isinstance(obj.get(key), str) or not obj[key].strip():
            errors.append(f"missing or blank field: {key}")
    if not errors:
        for key in ("sentence_en_1", "sentence_en_2"):
            if headword.lower() not in obj[key].lower():
                errors.append(f"{key} does not contain headword '{headword}'")
    return errors


def _rewrite(client: Any, headword: str, pos: str, definition_raw: str,
             example_raw: str, model: str) -> dict[str, Any] | None:
    prompt = _build_prompt(headword, pos, definition_raw, example_raw)
    for attempt in range(1, _MAX_RETRIES + 2):
        try:
            response = client.messages.create(
                model=model,
                max_tokens=512,
                messages=[{"role": "user", "content": prompt}],
            )
            text = response.content[0].text
            obj = _extract_json(text)
            errs = _validate_output(headword, obj)
            if not errs:
                return obj
            print(f"    attempt {attempt} validation errors: {errs}", file=sys.stderr)
        except Exception as exc:
            print(f"    attempt {attempt} error: {exc}", file=sys.stderr)
        if attempt <= _MAX_RETRIES:
            time.sleep(_RETRY_DELAY)
    return None


def _find_target_span(sentence: str, headword: str) -> str:
    """Return the exact substring of sentence that matches headword (case-insensitive)."""
    lower = sentence.lower()
    hw_lower = headword.lower()
    idx = lower.find(hw_lower)
    if idx >= 0:
        return sentence[idx: idx + len(headword)]
    return headword  # fallback: validator will catch this if it really is missing


def _build_word_package(todo_word: dict[str, Any], draft: dict[str, Any]) -> dict[str, Any]:
    headword = todo_word["headword"]
    pos = todo_word.get("pos_primary", "")
    phonetic = todo_word.get("phonetic") or ""
    # Ensure phonetic is wrapped in slashes (some entries may lack them)
    if phonetic and not (phonetic.startswith("/") and phonetic.endswith("/")):
        phonetic = f"/{phonetic}/"

    s1 = draft["sentence_en_1"].strip()
    s2 = draft["sentence_en_2"].strip()

    return {
        "headword": headword,
        "level_number": 1,
        "phonetic": phonetic if phonetic else f"/{headword}/",
        "pos_primary": pos,
        "mnemonic": draft["mnemonic"].strip(),
        "root_affix": None,
        "meanings": [
            {
                "pos": pos,
                "definition_zh": ZH_PLACEHOLDER,
                "definition_en": draft["definition_en"].strip(),
                "sort_order": 0,
                "source": "AI-draft",
            }
        ],
        "forms": [],
        "examples": [
            {
                "sentence_en": s1,
                "translation_zh": ZH_PLACEHOLDER,
                "target_span": _find_target_span(s1, headword),
                "has_audio": False,
                "sort_order": 0,
                "source": "AI-draft",
            },
            {
                "sentence_en": s2,
                "translation_zh": ZH_PLACEHOLDER,
                "target_span": _find_target_span(s2, headword),
                "has_audio": False,
                "sort_order": 1,
                "source": "AI-draft",
            },
        ],
        "distractors": todo_word.get("distractors", []),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="LLM rewrite step — produces draft packages.json.")
    parser.add_argument("--todo", type=Path, default=TODO_JSON)
    parser.add_argument("--out", type=Path, default=PACKAGE_PATH)
    parser.add_argument("--model", default=_DEFAULT_MODEL,
                        help=f"Claude model ID (default: {_DEFAULT_MODEL})")
    parser.add_argument("--dry-run", action="store_true",
                        help="Print prompt for first word and exit without calling API")
    args = parser.parse_args()

    if not args.todo.exists():
        print(f"ERROR: todo file not found: {args.todo}", file=sys.stderr)
        print("Run normalize_senses.py first.", file=sys.stderr)
        return 1

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key and not args.dry_run:
        print("ERROR: ANTHROPIC_API_KEY environment variable is not set.", file=sys.stderr)
        return 1

    with args.todo.open("r", encoding="utf-8") as fh:
        todo = json.load(fh)

    todo_words: list[dict[str, Any]] = todo.get("words", [])
    print(f"Todo words: {len(todo_words)}")

    if args.dry_run and todo_words:
        w = todo_words[0]
        print("\n--- DRY RUN: prompt for first word ---")
        print(_build_prompt(w["headword"], w.get("pos_primary", ""), w.get("definition_raw", ""), w.get("example_raw", "")))
        return 0

    try:
        import anthropic
    except ImportError:
        print("ERROR: anthropic package not installed. Run: pip install anthropic", file=sys.stderr)
        return 1

    client = anthropic.Anthropic(api_key=api_key)
    output_words: list[dict[str, Any]] = []
    ok = skipped = 0

    for word in todo_words:
        headword = word["headword"]
        definition_raw = word.get("definition_raw", "")
        if not definition_raw:
            print(f"  SKIP  {headword}: no definition_raw")
            skipped += 1
            continue

        distractors = word.get("distractors", [])
        if len(distractors) < 3:
            print(f"  WARN  {headword}: only {len(distractors)} distractor(s); package will fail validation")

        print(f"  LLM   {headword} ...", end=" ", flush=True)
        draft = _rewrite(client, headword, word.get("pos_primary", ""), definition_raw,
                         word.get("example_raw", ""), args.model)
        if draft is None:
            print(f"FAILED after {_MAX_RETRIES + 1} attempts — skipping")
            skipped += 1
            continue

        package = _build_word_package(word, draft)
        output_words.append(package)
        print(f"OK  def={draft['definition_en'][:50]!r}")
        ok += 1

    final_package = {
        "package_version": 1,
        "level_number": 1,
        "status": "draft",
        "notes": (
            f"AI-drafted definitions/examples. "
            f"Chinese fields are '{ZH_PLACEHOLDER}' — fill with definition_zh + translation_zh before shipping. "
            "Review all content before Supabase load."
        ),
        "words": output_words,
    }

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", encoding="utf-8") as fh:
        json.dump(final_package, fh, ensure_ascii=False, indent=2)

    print(f"\nDone. Drafted: {ok} | Skipped: {skipped}")
    print(f"Output: {args.out}")
    if ok > 0:
        print(f"\nNext steps:")
        print(f"  1. Fill in '[待翻译]' fields (definition_zh, translation_zh)")
        print(f"  2. python content_pipeline/scripts/validate_packages.py")
        print(f"  3. python content_pipeline/scripts/export_csv.py")
        print(f"  4. python content_pipeline/scripts/generate_questions.py")
        print(f"  5. python content_pipeline/scripts/generate_tts_manifest.py")
    return 0 if skipped == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
