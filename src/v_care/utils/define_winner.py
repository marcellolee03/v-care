from v_care.models.correction_patch import CorrectionPatch
from v_care.models.judgement import Judgement

STRATEGY_RANK = {
    "config_change": 0,
    "patch_update": 1,
    "major_update": 2,
    "disable": 3,
    "uninstall": 4,
}


def define_winner(
    patches: list[CorrectionPatch],
    verdict: list[Judgement]
) -> CorrectionPatch | list[CorrectionPatch] | None:
    corrects = [j for j in verdict if j.fixes_vulnerability]
    if not corrects:
        return None

    patch_by_author = {p.author: p for p in patches}
    best_rank = min(STRATEGY_RANK[j.strategy] for j in corrects)
    winners = [
        patch_by_author[j.author]
        for j in corrects
        if STRATEGY_RANK[j.strategy] == best_rank and j.author in patch_by_author
    ]

    if not winners:
        return None
    return winners[0] if len(winners) == 1 else winners