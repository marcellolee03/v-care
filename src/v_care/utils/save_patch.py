from pathlib import Path

from v_care.models.correction_patch import CorrectionPatch


def save_patch(
    correction_patch: CorrectionPatch,
    filepath: str | Path,
) -> Path:
    directory = Path(filepath)
    directory.mkdir(parents=True, exist_ok=True)
    output_path = directory / f"{correction_patch.author}.sh"
    output_path.write_text(correction_patch.script, encoding="utf-8")
    return output_path
