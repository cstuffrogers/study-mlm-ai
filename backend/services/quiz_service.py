"""QuizService — 出题 / 判分 / 错因归类 / 主观题三维批改（Orthodoxy 门禁）

正统性门禁（FR-022/023）：
  - 每题必须带 source_chunk_id；缺则拒绝出题；
  - authority_status=pending 或 trial_only 的题仅作练习，不计入正式掌握度；
  - 错误诊断题的故意错误项 exempt_marked=True，判分时走豁免（不因“提到错误话术”被防偏离误杀）。
"""
from __future__ import annotations

from datetime import datetime

from sqlalchemy import select

from core.config import QUIZ_SIZE_MIN, QUIZ_SIZE_MAX
from services.learning_db import session_scope
from services import mastery_service as ms
from core.verify.triple_check import TripleCheck
from core.guard.orthodoxy import OrthodoxyGuard
from content.knowledge_graph import get_node
from model.models_learning import QuizItem, QuizAttempt, SectionTest, DiagnosticTest

# 立场偏移关键词（用于客观题“选了西马/修正主义话术”判定为 stance_deviation）
_DEVIATION_KEYWORDS = ("市场社会主义", "资产阶级", "宪法爱国", "交往理性", "单向度", "博弈论", "去革命")

_tc = TripleCheck(guard=OrthodoxyGuard())


def _is_async_session(s) -> bool:
    try:
        from sqlalchemy.ext.asyncio import AsyncSession
        return isinstance(s, AsyncSession)
    except Exception:
        return False


async def _exec(s, stmt):
    if _is_async_session(s):
        return await s.execute(stmt)
    return s.execute(stmt)


async def _flush(s):
    if _is_async_session(s):
        await s.flush()
    else:
        s.flush()


class OrthodoxyViolation(Exception):
    pass


async def _items_for_section(section_id: str) -> list[QuizItem]:
    async with session_scope() as s:
        res = await _exec(s, select(QuizItem).where(QuizItem.section_id == section_id))
        return list(res.scalars().all())


def _select_items(items: list[QuizItem]) -> list[QuizItem]:
    """从题库选出 8-12 题：特殊题型必选 + 保证每知识点至少 1 题 + 余量顺序补齐。"""
    cap = max(QUIZ_SIZE_MIN, min(QUIZ_SIZE_MAX, len(items)))
    if len(items) <= cap:
        return list(items)
    chosen: list[QuizItem] = []
    chosen_ids: set[str] = set()

    def _add(it):
        if it.id not in chosen_ids and len(chosen) < cap:
            chosen.append(it)
            chosen_ids.add(it.id)

    # 1) 特殊题型优先（应用/主观/费曼）
    for it in items:
        if it.type == "application" or it.subjective:
            _add(it)
    # 2) 每个知识点保底 1 题
    seen_nodes: set[str] = set()
    for it in items:
        if it.node_id not in seen_nodes:
            seen_nodes.add(it.node_id)
            _add(it)
    # 3) 余量按原顺序补齐
    for it in items:
        _add(it)
    return chosen


def _interleave_items(items: list[QuizItem]) -> list[QuizItem]:
    """轻量交错排题（interleaving）：尽量让相邻两题属于不同知识点，降低块状效应。
    保持组内相对顺序稳定（不随机），仅在必要时调整；确定性结果便于测试。"""
    if len(items) <= 2:
        return list(items)
    # 按 node 分组，保持首次出现顺序
    groups: dict[str, list[QuizItem]] = {}
    order: list[str] = []
    for it in items:
        if it.node_id not in groups:
            groups[it.node_id] = []
            order.append(it.node_id)
        groups[it.node_id].append(it)
    if len(groups) <= 1:
        return list(items)
    # 轮转取题：每轮从每个还有剩余题的节点取一道，避免连续同节点
    out: list[QuizItem] = []
    while any(groups[k] for k in order):
        for k in order:
            if groups[k]:
                out.append(groups[k].pop(0))
    # 校验：若仍有相邻同节点（极少），做一次局部交换
    for i in range(1, len(out)):
        if out[i].node_id == out[i - 1].node_id:
            for j in range(i + 1, len(out)):
                if out[j].node_id != out[i - 1].node_id and (j + 1 >= len(out) or out[j + 1].node_id != out[i].node_id):
                    out[i], out[j] = out[j], out[i]
                    break
    return out


def _norm_choice(s: str) -> str:
    """客观题选项归一化：去空白、取首个字母、转大写。"""
    t = (s or "").strip().upper()
    if not t:
        return ""
    return t[0]


def _public_item(it: QuizItem) -> dict:
    """下发题面：不含 answer / explanation / error_category（判分时再返回）"""
    if not it.source_chunk_id:
        raise OrthodoxyViolation(f"题目 {it.id} 缺少溯源 chunk_id，拒绝出题")
    return {
        "id": it.id, "type": it.type, "stem": it.stem, "options": it.options,
        "difficulty": it.difficulty, "subjective": it.subjective,
        "application": it.type == "application",
        "source_chunk_id": it.source_chunk_id,
        "authority_status": it.authority_status,
        "exempt_marked": it.exempt_marked,
        "trial_only": _is_trial_only(it),
    }


def _is_official(it: QuizItem) -> bool:
    """是否为已审题（可计入正式掌握度）"""
    return it.authority_status == "reviewed" and not it.trial_only


def _is_trial_only(it: QuizItem) -> bool:
    """待审/试点题：仅练习不计正式掌握度"""
    return bool(it.trial_only) or it.authority_status != "reviewed"


async def start_section_test(user_id: str, section_id: str, route_id: str) -> dict:
    items = await _items_for_section(section_id)
    if not items:
        raise OrthodoxyViolation(f"章节 {section_id} 暂无题库，降级为按段落学习 + 简化测试")
    # 控制题量 8-12（P0 题库可多于 12 题）：
    #  1) 应用题/主观题（特殊题型）必选；
    #  2) 优先保障每个知识点至少 1 道（先修覆盖完整）；
    #  3) 余量按题库顺序补齐；最后交错排序（P2-⑤ 降低块状）。
    chosen = _select_items(items)
    chosen = _interleave_items(chosen)
    public = [_public_item(it) for it in chosen]
    async with session_scope() as s:
        test = SectionTest(user_id=user_id, section_id=section_id, route_id=route_id,
                           item_ids=[it.id for it in chosen], status="in_progress")
        s.add(test)
        await _flush(s)
        test_id = test.id
    return {"test_id": test_id, "section_id": section_id, "items": public}


def _classify_error(quiz: QuizItem, chosen_text: str) -> str:
    if any(k in (chosen_text or "") for k in _DEVIATION_KEYWORDS):
        return "stance_deviation"
    if quiz.type in ("concept_discrimination", "error_diagnosis"):
        return "concept_layer_confusion"
    return "real_unknown"


# 错因编码 → 面向学习者的说法。前端也有一份同样的映射（local_quiz.dart），
# 这里返回中文标签，避免把内部编码直接甩给学习者。
ERROR_CATEGORY_LABELS = {
    "real_unknown": "真不会",
    "concept_layer_confusion": "概念层级混淆",
    "stance_deviation": "立场偏移",
    "careless": "粗心",
    "concept_application": "概念运用不准",
    "term_misuse": "术语使用不当",
}

_ERROR_ADVICE = {
    "stance_deviation": "所选说法偏离经典立场（含非正统话语），作答时请使用正统术语与原著原意。",
    "concept_layer_confusion": "本题考概念辨析，把不同层次或相邻概念混在了一起；先分清概念的定义边界，再判断哪一句符合原著。",
    "concept_application": "原理本身说得过去，但扣错了现实对象或条件；先把材料里的关键条件与原理的适用范围对齐。",
    "term_misuse": "术语用得不准：用词偏离经典表述，建议改用原著术语重述一遍论证。",
    "real_unknown": "这一知识点还没有真正掌握：对照解析回看原句，再用自己的话复述一遍原理。",
    "careless": "思路大致对，但选项读漏或看反了；答题时先把每个选项读完再判断。",
}


def _err_label(code: str) -> str:
    code = (code or "").strip()
    return ERROR_CATEGORY_LABELS.get(code, code)


def _err_advice(code: str) -> str:
    return _ERROR_ADVICE.get((code or "").strip(), "")


def _grade_subjective(quiz: QuizItem, answer: str) -> dict:
    """三维度批改：术语正统性 / 逻辑自洽 / 概念层次（FR-014），给建议不代写"""
    tc = _tc.check(answer, retrieved_context=quiz.explanation, mode="feynman")
    stance = tc["stance"]
    term = tc["terminology"]
    # 显式偏离关键词（西马/修正主义话术）——直接拉低术语正统性
    has_deviation = any(k in (answer or "") for k in _DEVIATION_KEYWORDS)
    terminology_orthodoxy = 1.0 if (stance["status"] == "pass" and term["status"] == "pass" and not has_deviation) else 0.35
    # 逻辑自洽（启发式：长度与关键词覆盖）
    logic = 0.9 if len(answer.strip()) >= 20 else 0.5
    if any(x in answer for x in ("因为", "所以", "因此", "只有", "才能")):
        logic = min(1.0, logic + 0.05)
    # 概念层次（是否混入近义/错误用法）
    concept_layer = 1.0
    if stance["status"] == "block" or has_deviation:
        concept_layer = 0.3
    suggestions = []
    if terminology_orthodoxy < 0.6:
        suggestions.append("建议使用正统术语，避免西马/修正主义话语（如“市场社会主义”“交往理性”）")
    if logic < 0.7:
        suggestions.append("论证偏简，建议补充“原理—推理—结论”的完整链条")
    if concept_layer < 0.6:
        suggestions.append("存在概念层次混淆，注意区分“实践”与“理论活动”")
    score = round((terminology_orthodoxy + logic + concept_layer) / 3, 4)
    return {
        "terminology_orthodoxy": round(terminology_orthodoxy, 4),
        "logic_coherence": round(logic, 4),
        "concept_layer": round(concept_layer, 4),
        "suggestions": suggestions or ["表述基本符合要求，可补充一个原文例证"],
        "score": score,
        "stance": "block" if has_deviation else stance["status"],
    }


def _grade_application(quiz: QuizItem, answer: str) -> dict:
    """应用题/案例题论证评分（P1-②，rubric 三维）：
      structure（结构完整）/ concept_use（概念运用）/ stance（立场正确）。
    给建议不代写；故意错误项 exempt_marked 时不做偏离惩罚。
    """
    from content.concept_keywords import terms_for, misconceptions_for
    ans = (answer or "")
    node = get_node(quiz.node_id)
    node_ids = [quiz.node_id]
    terms = terms_for(node_ids)
    misconceptions = misconceptions_for(node_ids)
    # 1) 概念运用：命中核心术语比例
    hit = [t for t in terms if t in ans]
    concept_use = round(min(1.0, len(hit) / max(1, min(3, len(terms)))), 4)
    # 2) 结构：是否给出例证/因果链/结论（启发式）
    structure = 0.5
    if len(ans.strip()) >= 30:
        structure += 0.2
    if any(x in ans for x in ("例如", "比如", "因为", "所以", "因此", "这体现", "这说明", "可见")):
        structure += 0.2
    structure = round(min(1.0, structure), 4)
    # 3) 立场：误用错误话术或防偏离拦截 → 降低
    mis_hit = [m for m in misconceptions if m in ans]
    tc = _tc.check(ans, retrieved_context=quiz.explanation, mode="application")
    has_deviation = any(k in ans for k in _DEVIATION_KEYWORDS)
    if quiz.exempt_marked:
        stance = 1.0
    else:
        stance = 1.0 if (tc["stance"]["status"] == "pass" and not has_deviation and not mis_hit) else 0.3
    suggestions = []
    if concept_use < 0.6:
        suggestions.append("答题较少运用核心概念，建议显式引入：" + "、".join(terms[:4]))
    if structure < 0.7:
        suggestions.append("论证结构偏弱，建议按『原理—结合具体案例—得出结论』展开")
    if stance < 0.6:
        suggestions.append("存在概念误用或立场偏移，注意运用正统术语（避免：" + "、".join(misconceptions[:3]) + "）")
    score = round(0.4 * structure + 0.4 * concept_use + 0.2 * stance, 4)
    return {
        "structure": structure,
        "concept_use": concept_use,
        "stance": stance,
        "matched_terms": hit,
        "suggestions": suggestions or ["论证完整、概念运用准确，可再举一个现实例证升华"],
        "score": score,
    }


async def submit_test(test_id: str, user_id: str, answers: list[dict]) -> dict:
    # 取测试与题目
    async with session_scope() as s:
        res = await _exec(s, select(SectionTest).where(SectionTest.id == test_id))
        test = res.scalars().first()
        if test is None:
            raise ValueError("测试不存在")
        # 幂等保护：同一次测试只能提交一次；重复提交（双击/网络重试）不得再次回写掌握度，
        # 否则会把同一节点的 accuracy 覆盖成新一次作答结果，污染学情（真实缺陷）。
        if test.status == "submitted":
            raise ValueError("该测试已提交，请勿重复提交")
        item_ids = test.item_ids
        res = await _exec(s, select(QuizItem).where(QuizItem.id.in_(item_ids)))
        quiz_map = {q.id: q for q in res.scalars().all()}
        section_id, route_id = test.section_id, test.route_id

    ans_by_id = {a["item_id"]: a for a in answers}
    review = []
    node_stats: dict[str, dict] = {}  # node_id -> {correct, total, diff_sum, feynman}
    item_scores = []

    async with session_scope() as s:
        for qid in item_ids:
            q = quiz_map.get(qid)
            if q is None:
                continue
            a = ans_by_id.get(qid, {})
            ans_text = a.get("answer", "")
            official = _is_official(q)
            if q.type == "application":
                fb = _grade_application(q, ans_text)
                score = fb["score"]
                item_scores.append(score)
                st = node_stats.setdefault(q.node_id, {"correct": 0, "total": 0, "diff_sum": 0.0,
                                                       "feynman": None, "official": official})
                st["total"] += 1
                st["diff_sum"] += q.difficulty
                if score >= 0.6:
                    st["correct"] += 1
                err_cat = "" if score >= 0.6 else "concept_application"
                review.append({
                    "item_id": qid, "node_id": q.node_id, "stem": q.stem,
                    "type": q.type, "options": q.options,
                    "is_correct": score >= 0.6, "answer": ans_text,
                    "reference": q.explanation, "explanation": q.explanation,
                    "source_chunk_id": q.source_chunk_id,
                    "application_feedback": fb, "exempt_marked": q.exempt_marked,
                    "error_category": err_cat, "error_label": _err_label(err_cat),
                    "error_reason": _err_advice(err_cat),
                })
                s.add(QuizAttempt(user_id=user_id, quiz_id=qid, test_id=test_id, answer=ans_text,
                                  is_correct=score >= 0.6, score=score, duration_ms=a.get("duration_ms", 0),
                                  error_category="" if score >= 0.6 else "concept_application",
                                  confidence=(a.get("confidence") or ""),
                                  subjective_feedback=fb))
            elif q.subjective:
                fb = _grade_subjective(q, ans_text)
                score = fb["score"]
                item_scores.append(score)
                st = node_stats.setdefault(q.node_id, {"correct": 0, "total": 0, "diff_sum": 0.0,
                                                       "feynman": None, "official": official})
                st["total"] += 1
                st["diff_sum"] += q.difficulty
                if score >= 0.6:
                    st["correct"] += 1
                st["feynman"] = fb["score"]
                err_cat = "" if score >= 0.6 else "term_misuse"
                review.append({
                    "item_id": qid, "node_id": q.node_id, "stem": q.stem,
                    "type": q.type, "options": q.options,
                    "is_correct": score >= 0.6, "answer": ans_text,
                    "reference": q.explanation, "explanation": q.explanation,
                    "source_chunk_id": q.source_chunk_id,
                    "subjective_feedback": fb, "exempt_marked": q.exempt_marked,
                    "error_category": err_cat, "error_label": _err_label(err_cat),
                    "error_reason": _err_advice(err_cat),
                })
                s.add(QuizAttempt(user_id=user_id, quiz_id=qid, test_id=test_id, answer=ans_text,
                                  is_correct=score >= 0.6, score=score, duration_ms=a.get("duration_ms", 0),
                                  error_category="" if score >= 0.6 else "term_misuse",
                                  confidence=(a.get("confidence") or ""),
                                  subjective_feedback=fb))
            else:
                correct = (_norm_choice(ans_text) == _norm_choice(q.answer))
                chosen_text = ""
                if isinstance(q.options, list):
                    idx = ord(_norm_choice(ans_text) or "@") - 65
                    if 0 <= idx < len(q.options):
                        chosen_text = q.options[idx]
                err_cat = "" if correct else _classify_error(q, chosen_text)
                score = 1.0 if correct else 0.0
                item_scores.append(score)
                st = node_stats.setdefault(q.node_id, {"correct": 0, "total": 0, "diff_sum": 0.0,
                                                       "feynman": None, "official": official})
                st["total"] += 1
                st["diff_sum"] += q.difficulty
                if correct:
                    st["correct"] += 1
                st["official"] = st.get("official", False) and official if st["total"] > 1 else official
                review.append({
                    "item_id": qid, "node_id": q.node_id, "stem": q.stem,
                    "type": q.type, "options": q.options,
                    "is_correct": correct, "answer": q.answer, "answer_key": q.answer,
                    "chosen": chosen_text,
                    "explanation": q.explanation, "source_chunk_id": q.source_chunk_id,
                    "error_category": err_cat, "error_label": _err_label(err_cat),
                    "error_reason": _err_advice(err_cat),
                    "exempt_marked": q.exempt_marked,
                    "trial_only": q.trial_only or q.authority_status != "reviewed",
                })
                s.add(QuizAttempt(user_id=user_id, quiz_id=qid, test_id=test_id, answer=ans_text,
                                  is_correct=correct, score=score, duration_ms=a.get("duration_ms", 0),
                                  error_category=err_cat, confidence=(a.get("confidence") or "")))
        # 在同一（attached）session 内重查并写回，确保 status/submitted_at/total_score 持久化。
        # 原实现在 detached 对象上赋值，导致重复提交无法拦截、成绩不落库。
        res2 = await _exec(s, select(SectionTest).where(SectionTest.id == test_id))
        t2 = res2.scalars().first()
        if t2 is not None:
            t2.status = "submitted"
            t2.submitted_at = datetime.utcnow()
            t2.total_score = round(sum(item_scores) / len(item_scores), 4) if item_scores else 0.0
        await _flush(s)

    # 更新掌握度（仅 official 题计入正式掌握度；trial_only 仅练习）
    mastery_out = []
    for node_id, st in node_stats.items():
        if not st.get("official", False):
            continue
        accuracy = st["correct"] / st["total"] if st["total"] else 0.0
        difficulty = round(st["diff_sum"] / st["total"], 4) if st["total"] else 0.5
        prior = await ms.get_mastery_map(user_id, route_id)
        prior_stability = prior.get(node_id, {}).get("basis", {}).get("stability", 0.0) or 0.0
        stability = min(1.0, max(0.0, prior_stability + (0.3 if accuracy >= 0.999 else -0.1)))
        patch = {"accuracy": round(accuracy, 4), "difficulty": difficulty, "stability": round(stability, 4)}
        if st.get("feynman") is not None:
            patch["feynman"] = st["feynman"]
        dom_err = _dominant_error(review, node_id)
        if dom_err:
            patch["error_category"] = dom_err  # 节点级主导错因，供学情档案/推荐解释使用
        rec = await ms.upsert_mastery(user_id, node_id, route_id, patch, source="quiz", schedule_review=True)
        mastery_out.append({"node_id": node_id, "level": rec["level"], "score": rec["score"],
                            "error_category": dom_err, "section_id": _node_section(node_id)})

    # 元认知校准（P2-④）：自评把握度 vs 实测正确率
    calibration = _compute_calibration(answers, quiz_map, review)

    # 门控
    m_map = await ms.get_mastery_map(user_id, route_id)
    gating = ms.compute_gating(m_map, route_id, section_id)
    # 回填快照
    async with session_scope() as s:
        res = await _exec(s, select(SectionTest).where(SectionTest.id == test_id))
        t = res.scalars().first()
        t.mastery_snapshot = {"mastery": mastery_out, "gating": gating}
        await _flush(s)

    return {"test_id": test_id, "total_score": round(sum(item_scores) / len(item_scores), 4) if item_scores else 0.0,
            "mastery": mastery_out, "review": review, "gating": gating, "calibration": calibration}


def _compute_calibration(answers: list[dict], quiz_map: dict, review: list[dict]) -> dict:
    """元认知校准：把每题自评把握度映射为预期正确概率，与实测正确率对比。"""
    from core.config import CALIBRATION_CONFIDENCE_MAP, CALIBRATION_OVERCONFIDENT_GAP
    correct_map = {r["item_id"]: bool(r["is_correct"]) for r in review}
    pairs = []
    for a in answers:
        conf = (a.get("confidence") or "").lower()
        if conf not in CALIBRATION_CONFIDENCE_MAP:
            continue
        qid = a.get("item_id")
        if qid not in correct_map:
            continue
        pairs.append((CALIBRATION_CONFIDENCE_MAP[conf], 1.0 if correct_map[qid] else 0.0))
    if not pairs:
        return {"available": False}
    expected = sum(p[0] for p in pairs) / len(pairs)
    actual = sum(p[1] for p in pairs) / len(pairs)
    gap = expected - actual
    if gap > CALIBRATION_OVERCONFIDENT_GAP:
        verdict, tip = "overconfident", "你对自己的把握偏高，部分『觉得会』的题实际错了；建议对存疑点先自测再下结论。"
    elif gap < -CALIBRATION_OVERCONFIDENT_GAP:
        verdict, tip = "underconfident", "你实际掌握得比自评好，可以更有信心；不必过度复核。"
    else:
        verdict, tip = "calibrated", "自评与实测大体一致，元认知较准确，保持这种『知之为知之』的判断。"
    return {"available": True, "expected": round(expected, 3), "actual": round(actual, 3),
            "gap": round(gap, 3), "verdict": verdict, "tip": tip}


def _dominant_error(review: list[dict], node_id: str) -> str:
    """节点级错因汇总：取该节点错题中出现最多的 error_category（非空）。
    若节点无错题则返回空串。应用/主观题已有专属 error_category（concept_application / term_misuse）。"""
    counts: dict[str, int] = {}
    for r in review:
        cat = (r.get("error_category") or "").strip()
        if not cat:
            continue
        counts[cat] = counts.get(cat, 0) + 1
    if not counts:
        return ""
    return max(counts.items(), key=lambda kv: kv[1])[0]


def _node_section(node_id: str) -> str:
    n = get_node(node_id)
    return n["section_id"] if n else ""


# ---------------- 摸底测 ----------------
async def start_diagnostic(user_id: str, route_id: str) -> dict:
    from content.routes import sections_for_route
    secs = sections_for_route(route_id)
    items = []
    for sec in secs:
        its = await _items_for_section(sec["id"])
        items.extend(its[:3])  # 每章抽 3 题
    if not items:
        # 无题库：返回空，调用方可选跳过
        return {"diag_id": None, "items": [], "note": "该路线题库建设中，可跳过摸底直接选起点"}
    public = [_public_item(it) for it in items[:12]]
    from model.models_learning import DiagnosticTest
    async with session_scope() as s:
        diag = DiagnosticTest(user_id=user_id, route_id=route_id, item_ids=[it.id for it in items[:12]])
        s.add(diag)
        await _flush(s)
        diag_id = diag.id
    return {"diag_id": diag_id, "items": public}


async def submit_diagnostic(diag_id: str, user_id: str, answers: list[dict]) -> dict:
    from content.routes import sections_for_route
    from core.config import UNLOCK_THRESHOLD
    async with session_scope() as s:
        res = await _exec(s, select(DiagnosticTest).where(DiagnosticTest.id == diag_id))
        diag = res.scalars().first()
        if diag is None:
            raise ValueError(f"诊断测试不存在或已过期: {diag_id}")
        route_id = diag.route_id
        item_ids = diag.item_ids
        res = await _exec(s, select(QuizItem).where(QuizItem.id.in_(item_ids)))
        quiz_map = {q.id: q for q in res.scalars().all()}

    ans_by_id = {a["item_id"]: a.get("answer", "") for a in answers}
    # 按章节统计正确率
    sec_correct: dict[str, list[int]] = {}
    node_correct: dict[str, list[int]] = {}
    for qid, q in quiz_map.items():
        correct = 1 if _norm_choice(ans_by_id.get(qid, "")) == _norm_choice(q.answer) else 0
        sec_correct.setdefault(q.section_id, []).append(correct)
        node_correct.setdefault(q.node_id, []).append(correct)

    secs = sections_for_route(route_id)
    order = []
    skippable = []
    recommended_start = None
    for sec in secs:
        vals = sec_correct.get(sec["id"])
        if vals is None:
            # 无测试数据 → 视为需从该章开始（若尚未确定起点）
            if recommended_start is None:
                recommended_start = sec["id"]
            order.append(sec["id"])
            continue
        avg = sum(vals) / len(vals)
        if avg >= UNLOCK_THRESHOLD:
            skippable.append(sec["id"])
        else:
            if recommended_start is None:
                recommended_start = sec["id"]
            order.append(sec["id"])

    # 需补强知识点
    to_reinforce = []
    for node_id, vals in node_correct.items():
        if sum(vals) / len(vals) < UNLOCK_THRESHOLD:
            from content.knowledge_graph import get_node
            n = get_node(node_id)
            to_reinforce.append({"node_id": node_id, "name": n["name"] if n else node_id,
                                 "reason": "摸底正确率偏低"})

    result = {"recommended_start": recommended_start or (secs[0]["id"] if secs else None),
              "order": order, "skippable": skippable, "to_reinforce": to_reinforce}
    async with session_scope() as s:
        res = await _exec(s, select(DiagnosticTest).where(DiagnosticTest.id == diag_id))
        d = res.scalars().first()
        d.result = result
        await _flush(s)
    return {"diag_id": diag_id, **result}
