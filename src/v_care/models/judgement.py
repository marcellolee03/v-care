from typing import Literal

from pydantic.main import BaseModel

from v_care.ai.models import GeneratorModelName


class Judgement(BaseModel):
    author: GeneratorModelName
    fixes_vulnerability: bool
    strategy: Literal[
        "config_change", 
        "patch_update", 
        "major_update", 
        "disable", 
        "uninstall"
    ]