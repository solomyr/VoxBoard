#!/usr/bin/env python3
"""Preload verified speech/text weights into an installed development app over USB."""

import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess
import tempfile
import urllib.request
import zipfile


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("device", help="Paired iPhone UDID from xcrun devicectl list devices")
    parser.add_argument("--cache", type=pathlib.Path, default=pathlib.Path.home() / "Library/Caches/VoxBoard/models")
    parser.add_argument("--speech", default="openai_whisper-small")
    parser.add_argument("--text", default="qwen35-2b-q5km")
    args = parser.parse_args()
    repo = pathlib.Path(__file__).resolve().parent.parent
    manifest = json.loads((repo / "Sayboard/Resources/model-manifest.json").read_text())
    # Validate selections before downloading anything.
    selected = [("models", args.speech, "Models"), ("llmModels", args.text, "LLMModels")]
    for section, key, _ in selected:
        if key not in manifest[section]:
            parser.error(f"Unknown model: {key}")
    args.cache.mkdir(parents=True, exist_ok=True)
    for section, key, folder in selected:
        entry = manifest[section][key]
        archive = args.cache / f"{key}.zip"
        if not archive.exists() or digest(archive) != entry["sha256"]:
            print(f"Downloading {key} ({entry['sizeBytes'] / 1e6:.0f} MB)…", flush=True)
            partial = archive.with_suffix(".zip.part")
            try:
                with urllib.request.urlopen(entry["url"], timeout=60) as response, partial.open("wb") as target:
                    shutil.copyfileobj(response, target)
                if digest(partial) != entry["sha256"]:
                    raise ValueError(f"Checksum mismatch: {key}")
                partial.replace(archive)
            finally:
                partial.unlink(missing_ok=True)
        print(f"Verified {key}; extracting and transferring…", flush=True)
        with tempfile.TemporaryDirectory(prefix="voxboard-model-", dir=args.cache) as temporary:
            destination = pathlib.Path(temporary) / key
            destination.mkdir()
            with zipfile.ZipFile(archive) as zipped:
                for name in zipped.namelist():
                    if not (destination / name).resolve().is_relative_to(destination.resolve()):
                        raise ValueError(f"Invalid archive member: {name}")
                zipped.extractall(destination)
            subprocess.run([
                "xcrun", "devicectl", "device", "copy", "to", "--device", args.device,
                "--source", str(destination), "--destination", f"Library/Application Support/{folder}/{key}",
                "--domain-type", "appDataContainer", "--domain-identifier", "app.voxboard",
            ], check=True)
    print("Models installed. Relaunch VoxBoard to discover them.")


if __name__ == "__main__":
    main()
