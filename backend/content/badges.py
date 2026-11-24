"""学习勋章目录 — 纯数据模块（spec 001 勋章系统）

所有勋章的定义集中在此，`badge_service` 运行时读取本模块做达成判定。
**改配置即生效**：新增/停用勋章只需改这里，无需动引擎代码（D1）。

条件类型（condition_type）：
- ``threshold``  : 单一指标 >= threshold（如掌握 10 个知识点）
- ``ratio``      : 主指标 >= threshold **且** 比率指标/主指标 >= accuracy_threshold
                   （如累计作答 ≥50 题且正确率 ≥90%）
- ``completion`` : 特殊完成型（如 route_all：完成当前系统内全部已开放路线）

指标键（metric_key）对应 ``badge_service.collect_metrics`` 产出的快照：
mastered_count / journey_count / milestones_achieved / quiz_correct_total /
quiz_attempt_total / routes_completed / streak_days / dialogues_completed
"""
from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class BadgeDef:
    """单枚勋章定义（不可变，线程安全）。"""
    badge_id: str
    name: str
    description: str
    category: str
    icon_key: str
    condition_type: str                 # threshold | ratio | completion
    metric_key: str                     # 主指标键
    threshold: int | float              # 达成阈值（主指标）
    ratio_metric: str | None = None     # ratio 型：被除的比率指标键
    accuracy_threshold: float | None = None  # ratio 型：比率下限
    sort_order: int = 0
    enabled: bool = True


# ------------------------------------------------------------------ 目录
# 分类顺序与 spec 一致：知识掌握 / 贯通 / 里程碑 / 答题 / 路线 / 连续学习 / 对话
_CATS = {
    "知识掌握": "knowledge",
    "贯通": "journey",
    "里程碑": "milestone",
    "答题": "quiz",
    "路线": "route",
    "连续学习": "streak",
    "对话": "dialogue",
}

_BADGES: list[BadgeDef] = [
    # ---- 知识掌握（mastered_count）----
    BadgeDef("mastery_1", "初窥门径", "掌握 1 个知识点，迈出学习第一步",
             "知识掌握", "seed", "threshold", "mastered_count", 1, sort_order=101),
    BadgeDef("mastery_5", "知识新苗", "掌握 5 个知识点，知识开始扎根",
             "知识掌握", "sprout", "threshold", "mastered_count", 5, sort_order=102),
    BadgeDef("mastery_10", "知识学人", "掌握 10 个知识点，学习渐入佳境",
             "知识掌握", "book", "threshold", "mastered_count", 10, sort_order=103),
    BadgeDef("mastery_25", "知识行家", "掌握 25 个知识点，已成行家里手",
             "知识掌握", "expert", "threshold", "mastered_count", 25, sort_order=104),
    BadgeDef("mastery_50", "知识贤者", "掌握 50 个知识点，学识广博深厚",
             "知识掌握", "sage", "threshold", "mastered_count", 50, sort_order=105),
    BadgeDef("mastery_100", "知识宗师", "掌握 100 个知识点，登峰造极",
             "知识掌握", "master", "threshold", "mastered_count", 100, sort_order=106),

    # ---- 贯通（journey_count）----
    BadgeDef("journey_5", "启程之步", "贯通 5 个知识点，思路开始贯通",
             "贯通", "depart", "threshold", "journey_count", 5, sort_order=201),
    BadgeDef("journey_15", "行途初启", "贯通 15 个知识点，脉络渐次清晰",
             "贯通", "navigate", "threshold", "journey_count", 15, sort_order=202),
    BadgeDef("journey_30", "行途渐广", "贯通 30 个知识点，视野不断拓宽",
             "贯通", "route_way", "threshold", "journey_count", 30, sort_order=203),
    BadgeDef("journey_60", "行途通达", "贯通 60 个知识点，融会贯通",
             "贯通", "travel", "threshold", "journey_count", 60, sort_order=204),

    # ---- 里程碑（milestones_achieved）----
    BadgeDef("milestone_1", "首个里程碑", "达成 1 个里程碑，目标初现",
             "里程碑", "flag_first", "threshold", "milestones_achieved", 1, sort_order=301),
    BadgeDef("milestone_5", "里程碑探索者", "达成 5 个里程碑，探索见成果",
             "里程碑", "explore", "threshold", "milestones_achieved", 5, sort_order=302),
    BadgeDef("milestone_10", "里程碑达人", "达成 10 个里程碑，步步为营",
             "里程碑", "bolt", "threshold", "milestones_achieved", 10, sort_order=303),
    BadgeDef("milestone_15", "里程碑守护者", "达成 15 个里程碑，坚持不懈",
             "里程碑", "guard", "threshold", "milestones_achieved", 15, sort_order=304),

    # ---- 答题（quiz_correct_total / quiz_attempt_total）----
    BadgeDef("quiz_10", "初次答对", "累计答对 10 题，答题初见成效",
             "答题", "quiz", "threshold", "quiz_correct_total", 10, sort_order=401),
    BadgeDef("quiz_50", "答题新秀", "累计答对 50 题，答题渐入佳境",
             "答题", "touch", "threshold", "quiz_correct_total", 50, sort_order=402),
    BadgeDef("quiz_100", "答题能手", "累计答对 100 题，答题驾轻就熟",
             "答题", "check", "threshold", "quiz_correct_total", 100, sort_order=403),
    BadgeDef("quiz_200", "答题宗师", "累计答对 200 题，答题炉火纯青",
             "答题", "psyche", "threshold", "quiz_correct_total", 200, sort_order=404),
    BadgeDef("quiz_acc_50", "精准之声", "累计作答 ≥50 题且正确率 ≥90%，精准过人",
             "答题", "tune", "ratio", "quiz_attempt_total", 50,
             ratio_metric="quiz_correct_total", accuracy_threshold=0.9, sort_order=405),

    # ---- 路线（routes_completed）----
    BadgeDef("route_1", "首路达成", "完成 1 条路线学习，首条路线圆满",
             "路线", "map_one", "threshold", "routes_completed", 1, sort_order=501),
    BadgeDef("route_3", "路线行者", "完成 3 条路线学习，行路渐远",
             "路线", "map_three", "threshold", "routes_completed", 3, sort_order=502),
    BadgeDef("route_5", "路线通晓", "完成 5 条路线学习，通晓多路",
             "路线", "globe", "threshold", "routes_completed", 5, sort_order=503),
    BadgeDef("route_all", "全路先锋", "完成当前系统内全部已开放路线，全路贯通",
             "路线", "all_path", "completion", "routes_completed", 0, sort_order=504),

    # ---- 连续学习（streak_days）----
    BadgeDef("streak_7", "七日坚持", "连续学习 7 天，养成坚持的习惯",
             "连续学习", "fire7", "threshold", "streak_days", 7, sort_order=601),
    BadgeDef("streak_21", "月度恒心", "连续学习 21 天，月度恒心可嘉",
             "连续学习", "flame", "threshold", "streak_days", 21, sort_order=602),
    BadgeDef("streak_60", "季度长跑", "连续学习 60 天，季度长跑不辍",
             "连续学习", "timer", "threshold", "streak_days", 60, sort_order=603),
    BadgeDef("streak_100", "百日不辍", "连续学习 100 天，百日坚持不辍",
             "连续学习", "love", "threshold", "streak_days", 100, sort_order=604),

    # ---- 对话（dialogues_completed）----
    BadgeDef("dialogue_10", "对话初成", "完成 10 次对话学习，问答渐有收获",
             "对话", "chat", "threshold", "dialogues_completed", 10, sort_order=701),
    BadgeDef("dialogue_30", "对话熟手", "完成 30 次对话学习，问答驾轻就熟",
             "对话", "forum", "threshold", "dialogues_completed", 30, sort_order=702),
]

# 全量目录（按 sort_order 排序，供枚举/分页）
BADGES: list[BadgeDef] = sorted(_BADGES, key=lambda b: b.sort_order)

# 索引：badge_id -> BadgeDef
_BADGE_MAP: dict[str, BadgeDef] = {b.badge_id: b for b in BADGES}


def get_badge(badge_id: str) -> BadgeDef | None:
    """按 id 取勋章定义；未找到或已停用返回 None。"""
    b = _BADGE_MAP.get(badge_id)
    return b if b and b.enabled else None


def all_badges(enabled_only: bool = True) -> list[BadgeDef]:
    """返回勋章列表；enabled_only=True 时排除停用项。"""
    if enabled_only:
        return [b for b in BADGES if b.enabled]
    return list(BADGES)


def category_of(badge_id: str) -> str:
    b = _BADGE_MAP.get(badge_id)
    return b.category if b else ""


def total_count(enabled_only: bool = True) -> int:
    return len(all_badges(enabled_only))
