"""US4 学情档案：薄弱点排序 / 阻塞章节 / 五维雷达 / 总结来源标注"""
import uuid
import pytest

from services.learning_startup import ensure_learning_ready
from services import quiz_service, mastery_service as ms, profile_service


def uid():
    return "t_" + uuid.uuid4().hex[:8]


@pytest.mark.asyncio
async def test_profile_shape_and_radar():
    await ensure_learning_ready()
    u = uid()
    prof = await profile_service.build_profile(u, "route_A")
    assert set(prof["ability_radar"]).issuperset(
        {"materialism", "dialectics", "epistemology", "historical_materialism", "political_economy"})
    assert isinstance(prof["weak_points"], list)
    assert "summary" in prof and prof["summary"]


@pytest.mark.asyncio
async def test_weak_points_sorted_by_rank():
    """薄弱点排序 key=(1-score)×依赖出度×考频：实践(root)应排在前面"""
    await ensure_learning_ready()
    u = uid()
    # 学一部分，使部分节点有分
    t = await quiz_service.start_section_test(u, "sec_A_02", "route_A")
    await quiz_service.submit_test(t["test_id"], u, [{"item_id": it["id"], "answer": "B"} for it in t["items"]])
    prof = await profile_service.build_profile(u, "route_A")
    scores = [w["score"] for w in prof["weak_points"]]
    # 弱项按排序返回，第一项应是分数最低或依赖出度最高的组合点；至少非空
    assert prof["weak_points"]
    # 且应以 rank 逻辑排序：手工校验首项 rank >= 次项 rank
    from services.knowledge_graph_service import get_kg
    kg = get_kg()
    from content.knowledge_graph import get_node
    def rank(w):
        n = get_node(w["node_id"])
        return (1 - w["score"]) * (1 + kg.dependents_count(w["node_id"])) * n["exam_weight"]
    ranks = [rank(w) for w in prof["weak_points"]]
    assert ranks == sorted(ranks, reverse=True)


@pytest.mark.asyncio
async def test_blocking_sections_field():
    await ensure_learning_ready()
    u = uid()
    prof = await profile_service.build_profile(u, "route_A")
    for w in prof["weak_points"]:
        assert "blocking_sections" in w
        assert isinstance(w["blocking_sections"], int)


@pytest.mark.asyncio
async def test_summary_source_tags():
    await ensure_learning_ready()
    u = uid()
    t = await quiz_service.start_section_test(u, "sec_A_02", "route_A")
    await quiz_service.submit_test(t["test_id"], u, [{"item_id": it["id"], "answer": "A"} for it in t["items"]])
    s = await profile_service.generate_summary(u, "route_A")
    assert "mastered" in s and "to_reinforce" in s and "next_step" in s
    assert isinstance(s["source_tags"], dict)
