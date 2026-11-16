"""D98：必读书单覆盖率 + 延伸阅读条目结构校验

背景：`书籍.md` / `sources/texts/README.md` 列的 25 本必读，此前有 5 本（选集目录、
反杜林论、唯物主义和经验批判主义、资本论第二/三卷）在整条学习路径上完全找不到——
既没有章节，也没有延伸阅读。D98 用「导读型延伸阅读」（无 local_work）把它们补上。

这两个测试是 D98 的门禁：
  1) 25 本必读 + 关键选读，必须全都能从学习路径（章节 work 或延伸阅读 title）上找到；
  2) 延伸阅读条目结构合法：kind 合法、必填字段齐、无 local_work 的必须是导读（带 caution）、
     有 local_work 的必须指向真实入库原著。
"""
import pytest

from content.book_chunks import available_works
from content.reading_extensions import READING_EXTENSIONS, KIND_LABEL
from content.routes import SECTIONS


# ---------------------------------------------------------------------------
# 一、25 本必读（`书籍.md` / `sources/texts/README.md`）—— 关键词须能在路径上找到
# ---------------------------------------------------------------------------
REQUIRED_25: list[tuple[str, str]] = [
    # 第 0 阶段｜建坐标系
    ("0-1 大众哲学", "大众哲学"),
    ("0-2 马克思恩格斯选集（目录序言）", "马克思恩格斯选集"),
    ("0-3 辩证唯物主义和历史唯物主义（斯大林）", "辩证唯物主义和历史唯物主义"),
    # 第 1 阶段｜辩证法预备
    ("1-1 哲学笔记", "哲学笔记"),
    ("1-2 实践论", "实践论"),
    ("1-3 矛盾论", "矛盾论"),
    ("1-4 关于正确处理人民内部矛盾的问题", "关于正确处理人民内部矛盾"),
    # 第 2 阶段｜马克思本人
    ("2-1 1844年经济学哲学手稿", "1844年经济学哲学手稿"),
    ("2-2 关于费尔巴哈的提纲", "关于费尔巴哈的提纲"),
    ("2-3 德意志意识形态", "德意志意识形态"),
    ("2-4 共产党宣言", "共产党宣言"),
    ("2-5 政治经济学批判序言", "政治经济学批判"),
    # 第 3 阶段｜体系化
    ("3-1 路德维希·费尔巴哈和德国古典哲学的终结", "费尔巴哈和德国古典哲学的终结"),
    ("3-2 反杜林论（哲学篇）", "反杜林论"),
    ("3-3 家庭、私有制和国家的起源", "家庭、私有制和国家的起源"),
    ("3-4 国家与革命", "国家与革命"),
    ("3-5 唯物主义和经验批判主义", "唯物主义和经验批判主义"),
    # 第 4 阶段｜经济学印证
    ("4-1 资本论第一卷", "资本论"),
    ("4-2 资本论第二卷", "第二卷"),
    ("4-3 资本论第三卷", "第三卷"),
    ("4-4 哥达纲领批判", "哥达纲领批判"),
    ("4-5 帝国主义是资本主义的最高阶段", "帝国主义是资本主义的最高阶段"),
    # 第 5 阶段｜中国化
    ("5-1 中国社会各阶级的分析", "中国社会各阶级的分析"),
    ("5-2 湖南农民运动考察报告", "湖南农民运动考察报告"),
    ("5-3 新民主主义论", "新民主主义论"),
    ("5-4 论人民民主专政", "论人民民主专政"),
    ("5-5 论十大关系", "论十大关系"),
]

# 关键选读（`学习顺序2.md`）：不强制，但既已入库/已补位，就不该从路径上掉队
SELECTED_READINGS: list[tuple[str, str]] = [
    ("自然辩证法", "自然辩证法"),
    ("路易·波拿巴的雾月十八日", "雾月十八日"),
    ("工资、价格和利润", "工资、价格和利润"),
    ("给查苏利奇的复信草稿", "查苏利奇"),
    ("论一元论历史观的发展（普列汉诺夫）", "论一元论历史观的发展"),
    ("怎么办？", "怎么办"),
    ("共产主义运动中的“左派”幼稚病", "左派"),
    ("法兰西内战", "法兰西内战"),
    ("雇佣劳动与资本", "雇佣劳动与资本"),
    ("马克思主义的三个来源和三个组成部分", "三个来源"),
    ("改造我们的学习", "改造我们的学习"),
    ("整顿党的作风", "整顿党的作风"),
    ("反对党八股", "反对党八股"),
    ("在延安文艺座谈会上的讲话", "在延安文艺座谈会上的讲话"),
    ("反对本本主义", "反对本本主义"),
]


def _path_text() -> str:
    """整条学习路径的可检索文本：章节 work/标题 + 延伸阅读标题/作者。"""
    parts: list[str] = []
    for s in SECTIONS:
        parts.append(s.get("work") or "")
        parts.append(s.get("title") or "")
    for items in READING_EXTENSIONS.values():
        for it in items:
            parts.append(it.get("title") or "")
            parts.append(it.get("author") or "")
    return "\n".join(parts)


@pytest.mark.parametrize("label,keyword", REQUIRED_25 + SELECTED_READINGS,
                         ids=[f"{i+1:02d}-{lbl}" for i, (lbl, _) in
                              enumerate(REQUIRED_25 + SELECTED_READINGS)])
def test_canon_book_on_learning_path(label, keyword):
    """每一本必读/关键选读，都必须能从学习路径（章节或延伸阅读）上找到。"""
    text = _path_text()
    assert keyword in text, f"《{label}》在学习路径上找不到（关键词：{keyword}）"


def test_d98_extensions_wellformed():
    """延伸阅读条目结构合法；无 local_work 的必须是导读（带 caution），有 local_work 的必须真实存在。"""
    works = set(available_works())
    seen: dict[tuple[str, str], int] = {}
    problems: list[str] = []

    for sid, items in READING_EXTENSIONS.items():
        for it in items:
            name = f"{sid} / 《{it.get('title')}》"
            kind = it.get("kind")
            if kind not in KIND_LABEL:
                problems.append(f"{name}: kind 非法（{kind}）")
            for field in ("title", "author", "intro", "how_to_use"):
                if not it.get(field):
                    problems.append(f"{name}: 缺字段 {field}")
            if not isinstance(it.get("points"), list) or not it["points"]:
                problems.append(f"{name}: points 必须是非空列表")

            lw = it.get("local_work")
            if lw is None:
                # 无正文：必须带 caution
                if not it.get("caution"):
                    problems.append(f"{name}: 导读条目缺 caution（不得冒充原文）")
                # 但只有 classic 档是在冒充「经典原文」的位置上，必须明示自己只是导读；
                # historical / private / contested 本就声明为史料、民间或靶子，各有各的 caution 口径。
                elif kind == "classic" and "导读" not in it["caution"] and "无正文" not in it["caution"]:
                    problems.append(f"{name}: classic 档无正文，caution 未声明『仅导读』")
            elif lw not in works:
                problems.append(f"{name}: local_work={lw!r} 不在已入库原著中")

            key = (sid, it.get("title") or "")
            seen[key] = seen.get(key, 0) + 1

    dup = [k for k, n in seen.items() if n > 1]
    assert not problems, "延伸阅读结构问题:\n" + "\n".join(problems)
    assert not dup, f"同一章节内重复条目: {dup}"

# 依赖 sources/texts/ 原著正文；无正文时由 conftest.py 自动跳过。
pytestmark = pytest.mark.needs_texts
