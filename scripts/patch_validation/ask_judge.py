import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main() -> None:
    parser = argparse.ArgumentParser(description="Ask GPT Sol to review remediation patches.")
    parser.add_argument("origin", help="Origin directory under data/")
    parser.add_argument("vulnerability_name", help="Name in details/vulnerabilities.jsonl")
    args = parser.parse_args()

    with (ROOT / "details" / "vulnerabilities.jsonl").open(encoding="utf-8") as file:
        vulnerabilities = {}
        for line in file:
            if line.strip():
                record = json.loads(line)
                vulnerabilities[record["name"]] = record

    vulnerability = vulnerabilities.get(args.vulnerability_name)
    if vulnerability is None:
        parser.error(f"unknown vulnerability: {args.vulnerability_name}")

    case_dir = ROOT / "data" / args.origin / args.vulnerability_name
    patch_dir = case_dir / "patches"
    patch_files = sorted(path for path in patch_dir.glob("*.sh") if path.is_file())
    if not patch_files:
        parser.error(f"no .sh patches found in {patch_dir}")

    from v_care.ai.judge import Judge
    from v_care.models.correction_patch import CorrectionPatch

    patches = {}
    for path in patch_files:
        patch = CorrectionPatch(author=path.stem, script=path.read_text(encoding="utf-8"))
        patches[patch.author] = patch.script

    judgements = Judge("gpt_sol").judge(
        patches=patches,
        vulnerability_details=vulnerability["vulnerability_details"],
        environment_details=vulnerability["environment_details"],
    )

    results_dir = case_dir / "results"
    results_dir.mkdir(parents=True, exist_ok=True)
    output = json.dumps([judgement.model_dump(mode="json") for judgement in judgements], indent=2)
    (results_dir / "judge.json").write_text(output + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
