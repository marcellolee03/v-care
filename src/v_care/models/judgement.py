from typing import Literal

from pydantic.main import BaseModel

from v_care.ai.models import ModelName


class Judgement(BaseModel):
    author: ModelName
    fixes_vulnerability: bool
    strategy: Literal[
        "config_change", 
        "patch_update", 
        "major_update", 
        "disable", 
        "uninstall"
    ]
