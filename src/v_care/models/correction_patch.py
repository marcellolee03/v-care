from pydantic import BaseModel

from v_care.ai.models import ModelName


class CorrectionPatch(BaseModel):
    author: ModelName
    script: str