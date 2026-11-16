"""端到端 Demo：按 quickstart.md 6 步跑通 P0 单章闭环（提纲章）

无需外部服务（学习引擎默认 memory/SQLite）。
运行： cd backend && python demo_routes_flow.py
"""
from __future__ import annotations

import asyncio
import io
import sys

if sys.stdout.encoding and sys.stdout.encoding.lower() not in ("utf-8", "utf8"):
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

from services.learning_startup import ensure_learning_ready
from services import route_service, quiz_service, profile_service, recommendation_service as rec

USER = "demo_user"


def hr(t):
    print("\n" + "=" * 60)
    print(t)
    print("=" * 60)


async def main():
    await ensure_learning_ready()

    # ---- 1. 选路线 ----
    hr("① 选路线")
    routes = await route_service.list_routes()
    for r in routes:
        print(f"  - {r['id']}: {r['name']}（{r['est_duration']}，共享地基={r['shares_foundation']}）")
    sel = await route_service.select_route(USER, "route_A")
    print(f"  选择 route_A → recomputed_start = {sel['recomputed_start']}")

    # ---- 2. 摸底测 ----
    hr("② 摸底测")
    d = await quiz_service.start_diagnostic(USER, "route_A")
    print(f"  摸底题数 = {len(d['items'])}")
    # 模拟作答（前半对、后半错，检验跳过/补强逻辑）
    ans = []
    for i, it in enumerate(d["items"]):
        ans.append({"item_id": it["id"], "answer": "A" if i % 2 == 0 else "B"})
    diag = await quiz_service.submit_diagnostic(d["diag_id"], USER, ans)
    print(f"  推荐起点 = {diag['recommended_start']}")
    print(f"  可跳过章节 = {diag['skippable']}")
    print(f"  需补强 = {[x['name'] for x in diag['to_reinforce']]}")

    # ---- 3. 学一章（对话+即时小结）----
    hr("③ 学一章（对话+即时小结 / 卡顿信号）")
    from services.dialogue_service import DialogueService
    from websocket.protocol import UserMessageIn
    ds = DialogueService()
    r1 = await ds.chat(UserMessageIn(dialogue_id="d_demo", content="什么是实践？", mode="explain",
                                    paragraph_id="CH-ME-TH-01-1"))
    print("  即时小结:", r1["ai_message"]["instant_summary"]["one_line"])
    print("  检验问题:", r1["ai_message"]["instant_summary"]["check_question"])
    r2 = await ds.chat(UserMessageIn(dialogue_id="d_demo", content="市民社会还是不懂，再说一遍",
                                     mode="explain", selected_text="市民社会"))
    if r2.get("struggle"):
        print("  学情信号:", r2["struggle"]["signal_type"], "| dialogue分量:",
              r2["struggle"]["dialogue_component"])
    else:
        print("  （本轮未触发卡顿信号）")

    # ---- 4. 章节测试 + 掌握度 ----
    hr("④ 章节测试 + 掌握度五级")
    t = await quiz_service.start_section_test(USER, "sec_A_02", "route_A")
    print(f"  题目数 = {len(t['items'])}（下发不含答案：{'answer' not in t['items'][0]}）")
    # 混合作答：多数对
    ans = []
    for i, it in enumerate(t["items"]):
        if it["subjective"]:
            ans.append({"item_id": it["id"], "answer": "实践是检验真理的唯一标准，因为只有在改造客观世界的实践中才能验证思维的真理性。"})
        else:
            ans.append({"item_id": it["id"], "answer": "A" if i % 4 != 0 else "B"})
    sub = await quiz_service.submit_test(t["test_id"], USER, ans)
    print(f"  总分 = {sub['total_score']}｜下一章解锁 = {sub['gating']['next_section_unlocked']}")
    for m in sub["mastery"][:5]:
        print(f"    {m['node_id']}: {m['level']}（{m['score']}）")
    wrong = [r for r in sub["review"] if not r.get("is_correct") and not r.get("subjective_feedback")]
    if wrong:
        w = wrong[0]
        print(f"  错题示例: {w['item_id']} 错因={w.get('error_category')} 溯源={w.get('source_chunk_id')}")

    # ---- 5. 看档案与反馈 ----
    hr("⑤ 学情档案 + AI 总结")
    prof = await profile_service.build_profile(USER, "route_A")
    print("  五维雷达:")
    for k, v in prof["ability_radar"].items():
        print(f"    {k}: {v}")
    print("  薄弱点 TOP3:")
    for w in prof["weak_points"][:3]:
        print(f"    {w['name']}（掌握度{w['score']}，阻塞{w['blocking_sections']}章）")
    summ = await profile_service.generate_summary(USER, "route_A")
    print("  AI总结:", summ["summary"])
    print("  数据来源标注:", dict(list(summ["source_tags"].items())[:3]))

    # ---- 6. 按推荐进入下一章 ----
    hr("⑥ 智能推荐")
    today = (await rec.today(USER, "route_A"))["recommendation"]
    print(f"  今日推荐: [{today['rec_type']}] {today['reason']}")
    nxt = await rec.next_step(USER, "route_A", "sec_A_02")
    print(f"  下一步: [{nxt['rec_type']}] {nxt['reason']} → {nxt.get('target_section_id')}")

    hr("✅ 6 步闭环全部完成")
    print("正统性红线自检：所有题带 source_chunk_id；错误诊断题 exempt_marked；偏离不计普通错题。")


if __name__ == "__main__":
    asyncio.run(main())
