"""US2 逐章学习闭环：即时小结 / 卡顿信号上报 / 偏离不计普通人错题"""
import uuid
import pytest

from services.learning_startup import ensure_learning_ready
from services.dialogue_service import DialogueService
from websocket.protocol import UserMessageIn


def mk_user(content: str, **kw) -> UserMessageIn:
    return UserMessageIn(dialogue_id="d_" + uuid.uuid4().hex[:8], content=content, **kw)


@pytest.mark.asyncio
async def test_instant_summary_each_turn():
    await ensure_learning_ready()
    svc = DialogueService()
    res = await svc.chat(mk_user("什么是实践？", mode="explain", paragraph_id="CH-ME-TH-01-1"))
    assert "ai_message" in res
    inst = res["ai_message"].get("instant_summary")
    assert inst and inst.get("one_line")
    assert inst.get("check_question")


@pytest.mark.asyncio
async def test_struggle_signal_reported_on_repeated_question():
    await ensure_learning_ready()
    svc = DialogueService()
    res = await svc.chat(mk_user("实践还是不懂，再说一遍", mode="explain", selected_text="实践"))
    assert res.get("struggle"), "反复追问应触发学情信号"
    assert res["struggle"]["signal_type"] in ("repeated_question", "low_confidence")
    assert "dialogue_component" in res["struggle"]


@pytest.mark.asyncio
async def test_deviation_marked_not_normal_error(monkeypatch):
    """T022：被判偏离的内容标注『需批判对象引导』，not_a_normal_error=True"""
    await ensure_learning_ready()
    svc = DialogueService()

    def fake_check(generated, retrieved_context="", mode="explain", allow_critical=False):
        return {
            "fact_consistency": {"status": "pass"},
            "terminology": {"status": "pass"},
            "stance": {"status": "block", "source": "rule", "detail": [{"reason": "西马话术"}]},
            "action": "block",
        }
    monkeypatch.setattr(svc.triple_check, "check", fake_check)
    res = await svc.chat(mk_user("我们应当走市场社会主义", mode="explain"))
    blocked = res.get("blocked")
    assert blocked, "应被防偏离拦截"
    assert blocked.get("not_a_normal_error") is True
    assert blocked.get("treat_as") == "critique_target"
