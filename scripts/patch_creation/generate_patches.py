import argparse
import json
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate patches for a vulnerability.")
    parser.add_argument("name", help="Vulnerability name in details/vulnerabilities.jsonl")
    args = parser.parse_args()

    with (ROOT / "details" / "vulnerabilities.jsonl").open(encoding="utf-8") as f:
        vulnerabilities = {
            record['name']: record
            for line in f
            if line.strip()
            for record in (json.loads(line),)
        }

    vulnerability = vulnerabilities.get(args.name)
    if vulnerability is None:
        parser.error(f"unknown vulnerability: {args.name}")

    from v_care.ai.generator import Generator
    from v_care.utils.save_patch import save_patch

    details = {
        'vulnerability_details': vulnerability['vulnerability_details'],
        'environment_details': vulnerability['environment_details'],
    }

    deepseek_generator = Generator('deepseek_flash')
    haiku_generator = Generator('claude_haiku')

    with ThreadPoolExecutor(max_workers=2) as executor:
        deepseek_future = executor.submit(deepseek_generator.generate, **details)
        haiku_future = executor.submit(haiku_generator.generate, **details)

        deepseek_patch = deepseek_future.result()
        haiku_patch = haiku_future.result()

    patch_dir = ROOT / 'data' / vulnerability['source'] / vulnerability['name'] / 'patches'

    save_patch(correction_patch=deepseek_patch, filepath=patch_dir)
    save_patch(correction_patch=haiku_patch, filepath=patch_dir)


if __name__ == "__main__":
    main()
