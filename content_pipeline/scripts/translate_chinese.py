"""
translate_chinese.py
--------------------
Step 5 of the content pipeline — Chinese translation.

Input:  content_pipeline/packages/level_001_packages.json
        (fields with "[待翻译]" produced by rewrite_and_draft.py)
Output: same file, with all "[待翻译]" replaced by real Chinese text

For each word, calls Claude API to produce:
  - definition_zh : 4–8 character learner-friendly Chinese gloss
  - translation_zh: natural Chinese translation of each example sentence

Why Claude instead of Azure Translator:
  - Already configured (same ANTHROPIC_API_KEY)
  - Handles both translation AND learner-friendly rewriting in one call
  - No new account/subscription/region setup needed for a 20–80 word pilot

Requires: ANTHROPIC_API_KEY environment variable
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
from pipeline_common import PACKAGE_PATH

ZH_PLACEHOLDER = "[待翻译]"
_DEFAULT_MODEL = "claude-haiku-4-5-20251001"
_RETRY_DELAY = 2.0
_MAX_RETRIES = 2


def _build_prompt(headword: str, pos: str, definition_en: str, sentences: list[str]) -> str:
    sentences_block = "\n".join(f"  {i+1}. {s}" for i, s in enumerate(sentences))
    return f"""You are writing Chinese content for an English learning app for Chinese speakers at CEFR A1/A2 level.

Word: {headword}
Part of speech: {pos}
English definition: {definition_en}
Example sentences:
{sentences_block}

Output EXACTLY this JSON — no markdown, no extra text:
{{
  "definition_zh": "...",
  "translations": ["...", "..."]
}}

Rules:
- definition_zh: 4–10 Chinese characters only, learner-friendly gloss that matches the English definition, no punctuation at the end
- translations: one Chinese translation per sentence (same count as input sentences), natural spoken Chinese, not overly formal
- Keep translations short and simple — A1/A2 learners should understand them immediately"""


def _extract_json(text: str) -> dict[str, Any]:
    text = text.strip()
    start = text.find("{")
    end = text.rfind("}") + 1
    if start < 0 or end <= start:
        raise ValueError("No JSON object found in response")
    return json.loads(text[start:end])


def _validate(headword: str, obj: dict[str, Any], expected_sentence_count: int) -> list[str]:
    errors: list[str] = []
    def_zh = obj.get("definition_zh", "")
    if not isinstance(def_zh, str) or not def_zh.strip():
        errors.append("definition_zh is missing or blank")
    elif len(def_zh) > 20:
        errors.append(f"definition_zh too long ({len(def_zh)} chars): {def_zh!r}")

    translations = obj.get("translations", [])
    if not isinstance(translations, list):
        errors.append("translations must be a list")
    elif len(translations) != expected_sentence_count:
        errors.append(
            f"expected {expected_sentence_count} translations, got {len(translations)}"
        )
    else:
        for i, t in enumerate(translations):
            if not isinstance(t, str) or not t.strip():
                errors.append(f"translations[{i}] is blank")
    return errors


def _translate_word(
    client: Any,
    headword: str,
    pos: str,
    definition_en: str,
    sentences: list[str],
    model: str,
) -> dict[str, Any] | None:
    prompt = _build_prompt(headword, pos, definition_en, sentences)
    for attempt in range(1, _MAX_RETRIES + 2):
        try:
            response = client.messages.create(
                model=model,
                max_tokens=300,
                messages=[{"role": "user", "content": prompt}],
            )
            obj = _extract_json(response.content[0].text)
            errs = _validate(headword, obj, len(sentences))
            if not errs:
                return obj
            print(f"    attempt {attempt} validation errors: {errs}", file=sys.stderr)
        except Exception as exc:
            print(f"    attempt {attempt} error: {exc}", file=sys.stderr)
        if attempt <= _MAX_RETRIES:
            time.sleep(_RETRY_DELAY)
    return None


def _needs_translation(word: dict[str, Any]) -> bool:
    """Return True if this word still has any [待翻译] placeholder fields."""
    for meaning in word.get("meanings", []):
        if meaning.get("definition_zh") == ZH_PLACEHOLDER:
            return True
    for example in word.get("examples", []):
        if example.get("translation_zh") == ZH_PLACEHOLDER:
            return True
    return False


def main() -> int:
    parser = argparse.ArgumentParser(description="Fill Chinese translation fields in packages.json.")
    parser.add_argument("--package", type=Path, default=PACKAGE_PATH)
    parser.add_argument("--model", default=_DEFAULT_MODEL)
    parser.add_argument("--dry-run", action="store_true",
                        help="Show prompt for first word and exit without calling API")
    args = parser.parse_args()

    if not args.package.exists():
        print(f"ERROR: package file not found: {args.package}", file=sys.stderr)
        print("Run rewrite_and_draft.py first.", file=sys.stderr)
        return 1

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key and not args.dry_run:
        print("ERROR: ANTHROPIC_API_KEY environment variable is not set.", file=sys.stderr)
        return 1

    with args.package.open("r", encoding="utf-8") as fh:
        package = json.load(fh)

    words = package.get("words", [])
    pending = [w for w in words if _needs_translation(w)]
    already_done = len(words) - len(pending)
    print(f"Total words: {len(words)} | Already translated: {already_done} | Pending: {len(pending)}")

    if not pending:
        print("All words already translated. Nothing to do.")
        return 0

    if args.dry_run:
        w = pending[0]
        sentences = [ex["sentence_en"] for ex in w.get("examples", [])]
        def_en = (w.get("meanings") or [{}])[0].get("definition_en", "")
        print("\n--- DRY RUN: prompt for first pending word ---")
        print(_build_prompt(w["headword"], w.get("pos_primary", ""), def_en, sentences))
        return 0

    try:
        import anthropic
    except ImportError:
        print("ERROR: anthropic package not installed. Run: pip install anthropic", file=sys.stderr)
        return 1

    client = anthropic.Anthropic(api_key=api_key)
    ok = skipped = 0

    for word in pending:
        headword = word["headword"]
        pos = word.get("pos_primary", word.get("pos", ""))
        def_en = (word.get("meanings") or [{}])[0].get("definition_en", "")
        sentences = [ex["sentence_en"] for ex in word.get("examples", [])]

        if not sentences:
            print(f"  SKIP  {headword}: no example sentences")
            skipped += 1
            continue

        print(f"  ZH    {headword} ...", end=" ", flush=True)
        result = _translate_word(client, headword, pos, def_en, sentences, args.model)

        if result is None:
            print(f"FAILED — keeping placeholder")
            skipped += 1
            continue

        # Write definition_zh into all meanings that have the placeholder
        for meaning in word.get("meanings", []):
            if meaning.get("definition_zh") == ZH_PLACEHOLDER:
                meaning["definition_zh"] = result["definition_zh"]

        # Write translation_zh into examples
        translations = result["translations"]
        for i, example in enumerate(word.get("examples", [])):
            if example.get("translation_zh") == ZH_PLACEHOLDER and i < len(translations):
                example["translation_zh"] = translations[i]

        print(f"OK  def_zh={result['definition_zh']!r}")
        ok += 1

        # Save after every word so progress is not lost on interruption
        with args.package.open("w", encoding="utf-8") as fh:
            json.dump(package, fh, ensure_ascii=False, indent=2)

    remaining = sum(1 for w in words if _needs_translation(w))
    print(f"\nDone. Translated: {ok} | Skipped: {skipped} | Still pending: {remaining}")
    if remaining == 0:
        print("All [待翻译] fields filled. Ready for validate_packages.py.")
    return 0 if remaining == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
