from __future__ import annotations

import argparse
import json
from pathlib import Path

from pipeline_common import LEVEL_001_TTS_DIR, OUTPUT_DIR, PACKAGE_PATH, ensure_output_dir, load_config, load_package, word_id
from validate_packages import validate_package


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Google TTS pronunciation manifest.")
    parser.add_argument("--package", type=Path, default=PACKAGE_PATH)
    parser.add_argument("--output", type=Path, default=LEVEL_001_TTS_DIR)
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
    manifest_path = output_dir / "pronunciation_tts_manifest.jsonl"
    tts = config["tts"]
    with manifest_path.open("w", encoding="utf-8") as f:
        for word in package["words"]:
            wid = word_id(config, word)
            row = {
                "word_id": wid,
                "headword": word["headword"].strip().lower(),
                "text": word["headword"].strip().lower(),
                "provider": tts["provider"],
                "voice": tts["voice"],
                "audio_encoding": tts["audio_encoding"],
                "speaking_rate": tts["speaking_rate"],
                "storage_bucket": tts["storage_bucket"],
                "output_path": f"{tts['path_prefix']}/{wid}.mp3",
                "local_output_path": f"content_pipeline/audio/pronunciations/{wid}.mp3",
            }
            f.write(json.dumps(row, ensure_ascii=False) + "\n")

    print(f"Wrote {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
