from typing import Literal

from pydantic.main import BaseModel


class Judgement(BaseModel):
    fixes_vulnerability: bool
    strategy: Literal[
        "config_change", 
        "patch_update", 
        "major_update", 
        "disable", 
        "uninstall"
    ]