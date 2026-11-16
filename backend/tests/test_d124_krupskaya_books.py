"""D124 门禁：克鲁普斯卡娅「列宁怎样读书、研究、宣传」10 篇

收录口径（写死在这里）：

  * **只收「读书／研究／宣传」窄口**：图书馆与外国语（读书）、怎样研究马克思的
    著作／创造性的研究过程／理论联系实际的学风／研究马克思主义／列宁是科学
    工作者（研究）、宣传家和鼓动家／论善于为工农群众写作（写作与宣传）、
    列宁如何对待博物馆工作（直观教育）。
  * **整本节选**：人民出版社一九七三年版《列宁是怎样写作学习的》十一篇中取
    七篇，裁去《列宁的编辑工作》《列宁著作中的〈资本论〉》《纪念列宁的
    〈唯物主义和经验批判主义〉一书出版二十五周年》《列宁的方针》；另取
    《论列宁》一九七九年俄文第四版单篇三篇（中译见《马列著作编译资料》）。
    节选在「篇」这一级——篇内不裁，一篇一字不改地整篇照录。
  * **不收**：教育专题整批、生平回忆整批、顶层私人书信。教育专题与生平回忆
    属教育史与传记，不是工作方法；私信属私人文字。

分档：全部「正统／0.9」——克鲁普斯卡娅的回忆是权威的回忆文献，但不是列宁
本人著作，故不占经典原著档（同 D122 蔡特金、D123 工运史料的分档口径）。
"""
import re
from pathlib import Path

import pytest

from content.book_chunks import BOOKS, _GENERIC_TERMS, all_book_chunks
from content.reading_extensions import extensions_for

TEXTS = Path(__file__).resolve().parents[2] / "sources" / "texts"

# 文件 → (work, 分档, 权重, 篇首识别行, 篇末溯源行)
WORKS = {
    "1-列宁是宣传家和鼓动家.txt": (
        "列宁是宣传家和鼓动家", "正统", 0.9,
        "宣传鼓动工作的明确性是一个基本条件",
        "载于娜·康·克鲁普斯卡娅：《列宁是宣传家和鼓动家》",
    ),
    "1-列宁论善于为工农群众写作.txt": (
        "列宁论善于为工农群众写作", "正统", 0.9,
        "弗拉基米尔·伊里奇从西伯利亚流放地写给国外的巴维尔·波利索维奇·阿克雪里罗得的信",
        "载于娜·康·克鲁普斯卡娅：《列宁是党的报刊的编辑和组织者》",
    ),
    "1-列宁怎样研究马克思的著作.txt": (
        "列宁怎样研究马克思的著作", "正统", 0.9,
        "我国的工人运动是在马克思主义旗帜下发展起来的",
        "载于娜·康·克鲁普斯卡娅：《学习列宁那样工作》",
    ),
    "1-创造性的研究过程.txt": (
        "创造性的研究过程", "正统", 0.9,
        "凡是研究过列宁的活动和著作的人",
        "载于娜·康·克鲁普斯卡娅：《关于弗·伊·列宁的最后两篇文章",
    ),
    "1-理论联系实际的学风.txt": (
        "理论联系实际的学风", "正统", 0.9,
        "列宁在1894年写的第一部巨著",
        "未写完的手稿，总标题为《列宁的工作方法》",
    ),
    "1-列宁怎样利用图书馆.txt": (
        "列宁怎样利用图书馆", "正统", 0.9,
        "列宁的很多时间是在图书馆里度过的",
        "载于娜·康·克鲁斯卡娅：《列宁关于图书事业写了和说了些什么？》",
    ),
    "1-列宁怎样学习外国语.txt": (
        "列宁怎样学习外国语", "正统", 0.9,
        "列宁懂得许多种外国语",
        "载于1937年9月5日《真理报》第245号",
    ),
    "1-研究马克思主义.txt": (
        "研究马克思主义", "正统", 0.9,
        "孙凌齐 译 王澍 校",
        "青年人要想成为列宁主义者，就应当用心研究理论",
    ),
    "1-列宁是科学工作者.txt": (
        "列宁是科学工作者", "正统", 0.9,
        "孙凌齐 译 徐鸣珂 校",
        "中译文来自《马列著作编译资料》第16辑",
    ),
    "1-列宁如何对待博物馆工作.txt": (
        "列宁如何对待博物馆工作", "正统", 0.9,
        "刘燕明 译 黄有自 校",
        "这就是我所能回忆起来的列宁对待博物馆工作的点滴情况。",
    ),
}

KEY_LINES = {
    "1-列宁是宣传家和鼓动家.txt": [
        "列宁是一个善于掌握听众 、 和听众建立必要的相互了解的宣传家",
        "在宣传、鼓动和组织工作之间是没有墙隔着的。",
        "列宁把革命的群众罢工叫作无产阶级的鼓动方法。",
    ],
    "1-列宁论善于为工农群众写作.txt": [
        "这本小册子里完全没有鼓动的词句和号召。",
        "列宁认为善于通俗地讲话和写作是非常重要的。",
        "共产党员在形势急剧转变的关头，特别应当写得通俗，讲得通俗。",
    ],
    "1-列宁怎样研究马克思的著作.txt": [
        "列宁经常把各种不同的观点拿来对比",
        "找出其中的异同点——这就是列宁的方法",
        "不是教条，而是行动的指南",
    ],
    "1-创造性的研究过程.txt": [
        "都知道列宁提出自己的基本思想时是多么慎重。",
        "从理论上加以论证后，弗拉基米尔·伊里奇便从中得出实际",
    ],
    "1-理论联系实际的学风.txt": [
        "研究，宣传，组织（Studieren, Propagandieren",
        "实际的宣传鼓动工作始终应放在第一位",
    ],
    "1-列宁怎样利用图书馆.txt": [
        "到国外以后，弗拉基米尔·伊里奇更加勤奋地利用图书馆。",
        "瑞士的图书馆事业搞得很好",
    ],
    "1-列宁怎样学习外国语.txt": [
        "他精通德文、法文和英文，他研究这些语文，翻译这些语文的书籍",
        "许多人把学习外国语同学习本国语分割开来",
    ],
    "1-研究马克思主义.txt": [
        "必须学会了解马克思的“革命辩证法”。",
        "只有马克思主义才了解群众，才教导人们依靠群众。",
    ],
    "1-列宁是科学工作者.txt": [
        "要了解作为科学工作者的列宁，就必须了解他生活并成长为共产主义者的那个时代。",
    ],
    "1-列宁如何对待博物馆工作.txt": [
        "弗拉基米尔·伊里奇不能算是博物馆的特别爱好者。",
        "猿、原始人以及现代人的颅骨也深深地吸引住列宁。",
    ],
}

# 延伸阅读挂接：章节 → 篇名集合
EXPECTED = {
    "sec_B_10": {
        "研究马克思主义", "创造性的研究过程",
        "理论联系实际的学风", "列宁怎样学习外国语",
    },
    "sec_B_05": {
        "列宁怎样研究马克思的著作", "列宁怎样利用图书馆", "列宁是科学工作者",
    },
    "sec_B_04": {"列宁是宣传家和鼓动家", "列宁如何对待博物馆工作"},
    "sec_C_07": {"列宁论善于为工农群众写作"},
}

# 整本 11 篇里被裁掉的 4 篇、以及两个不进的子目录
EXCLUDED_WORK_WORDS = [
    "列宁的编辑工作", "列宁著作中的《资本论》", "出版二十五周年", "列宁的方针",
]
EXCLUDED_FILENAME_WORDS = ["图书事业", "列宁的方针", "回忆列宁", "论教育"]

DISPLAY_JARGON = re.compile(r"D\d{2,3}|TRIM|sec_[A-C]_\d\d|OCR|PDF|HTML|入库|镜像|分片|\.txt|\.md")


@pytest.mark.parametrize("fname", sorted(WORKS))
def test_d124_text_present_and_traceable(fname):
    path = TEXTS / fname
    assert path.exists(), f"缺正文文件：{fname}"
    t = path.read_text(encoding="utf-8")
    _work, _tag, _score, head, tail = WORKS[fname]
    assert head in t[:900], f"{fname}: 篇首识别行缺失「{head}」"
    assert tail in t, f"{fname}: 篇末溯源行缺失「{tail}」"
    assert len(t) > 500, f"{fname}: 正文过短（{len(t)} 字符），疑似只剩导读"
    assert "\n\n\n\n" not in t, f"{fname}: 出现连续空行，疑似拼接残留"


@pytest.mark.parametrize("fname", sorted(WORKS))
def test_d124_key_lines_verbatim(fname):
    flat = re.sub(r"\s+", "", (TEXTS / fname).read_text(encoding="utf-8"))
    for line in KEY_LINES[fname]:
        assert re.sub(r"\s+", "", line) in flat, f"{fname}: 关键句不逐字匹配「{line}」"


@pytest.mark.parametrize("fname", sorted(WORKS))
def test_d124_book_meta(fname):
    work, tag, score, _head, _tail = WORKS[fname]
    hits = [b for b in BOOKS if b["file"] == fname]
    assert len(hits) == 1, f"{fname}: BOOKS 里应恰好登记一次，实际 {len(hits)}"
    b = hits[0]
    assert b["work"] == work, f"{fname}: work 应为「{work}」，实际「{b['work']}」"
    assert b["orthodoxy_tag"] == tag, f"{fname}: 分档应为「{tag}」，实际「{b['orthodoxy_tag']}」"
    assert b["authority_score"] == score, f"{fname}: 权重应为 {score}，实际 {b['authority_score']}"
    assert "克鲁普斯卡娅" in (b.get("author") or ""), f"{fname}: 作者应是克鲁普斯卡娅"


def test_d124_book_count_and_prefix():
    mine = [b for b in BOOKS if "克鲁普斯卡娅" in (b.get("author") or "")]
    assert len(mine) == 10, f"克鲁普斯卡娅条目应为 10 条，实际 {len(mine)}"
    prefixes = [b["id_prefix"] for b in mine]
    assert len(set(prefixes)) == 10, f"id_prefix 重复：{sorted(prefixes)}"
    slugs = [b["slug"] for b in mine]
    assert len(set(slugs)) == 10, f"slug 重复：{sorted(slugs)}"
    for p in prefixes:
        assert re.fullmatch(r"CH-[A-Z]{4}-", p), f"id_prefix 形如「CH-XXXX-」：{p}"


def test_d124_chunks_indexed():
    chunks = all_book_chunks()
    for fname, (work, *_rest) in WORKS.items():
        mine = [c for c in chunks if c.get("source") == work]
        assert mine, f"{fname}: 分片未进索引进（work={work}）"
        assert all(c["text"].strip() for c in mine), f"{fname}: 存在空分片"


def test_d124_extensions_wired():
    all_works = {w for s in EXPECTED.values() for w in s}
    for sid, works in EXPECTED.items():
        items = extensions_for(sid)
        local = {i.get("local_work") for i in items if i.get("local_work")}
        missing = works - local
        assert not missing, f"{sid}: 缺延伸阅读挂接 {sorted(missing)}"
        for i in items:
            if i.get("local_work") in all_works:
                assert i["kind"] in {"classic", "historical"}, \
                    f"{sid}/《{i['title']}》: kind 非法「{i['kind']}」"
                assert i.get("points"), f"{sid}/《{i['title']}》: 缺要点"
                assert "一字未改" in i.get("caution", ""), \
                    f"{sid}/《{i['title']}》: caution 须写明「一字未改」"
                m = DISPLAY_JARGON.search(i.get("caution", ""))
                assert not m, f"{sid}/《{i['title']}》: caution 出现开发期术语「{m.group(0)}」"
    wired = {i.get("local_work") for sid in EXPECTED for i in extensions_for(sid)}
    assert all_works <= wired, f"未挂接：{sorted(all_works - wired)}"


def test_d124_excluded_works_absent():
    """整本里被裁的 4 篇、教育专题与生平回忆，一份也不许进来。"""
    for b in BOOKS:
        for word in EXCLUDED_WORK_WORDS:
            assert word not in (b.get("work") or ""), f"《{b['work']}》属排除项（{word}）"
    files = {p.name for p in TEXTS.glob("*.txt")}
    for word in EXCLUDED_FILENAME_WORDS:
        bad = sorted(f for f in files if word in f)
        assert not bad, f"排除项文章混进了正文目录：{bad}"


def test_d124_selection_is_whole_piece():
    """篇内不裁：每篇正文与该篇镜像原页抽取结果逐字相同（一字未改、无章内裁剪）。"""
    import importlib.util

    mp = Path(__file__).resolve().parents[2] / "scripts" / "import_mirror.py"
    spec = importlib.util.spec_from_file_location("import_mirror_d124", mp)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)

    by_file = {s["file"]: s for s in mod.SPECS}
    for fname in WORKS:
        assert fname not in mod.TRIM, f"{fname}: 本批不做篇内裁剪，不应有 TRIM 配置"
        text, cn = mod.build(by_file[fname])
        cur = (TEXTS / fname).read_text(encoding="utf-8")
        assert text == cur, f"{fname}: 从源页重新拼接与库内正文不一致（原文被改写？）"
        assert cn == len(re.findall(r"[\u4e00-\u9fff]", cur))


def test_d124_generic_terms_widened():
    """「宣传」「鼓动」是本批主题词，必须进通用概念词表，否则图召回零命中。"""
    for w in ("宣传", "鼓动", "学风", "图书馆"):
        assert w in _GENERIC_TERMS, f"通用概念词缺「{w}」"
    chunks = all_book_chunks()
    mentions = {t for c in chunks if "克鲁普" in c.get("book_author", "")
                for t in c.get("concept_mentions", [])}
    assert "宣传" in mentions and "鼓动" in mentions, \
        f"克鲁普斯卡娅分片侧未抽到「宣传」「鼓动」mention（实际 {sorted(mentions)[:20]}）"


def test_d124_quotes_verbatim():
    """延伸阅读里所有「」引文必须逐字出现在正文（只认原文逐字句）。"""
    all_works = {w for s in EXPECTED.values() for w in s}
    by_work = {v[0]: f for f, v in WORKS.items()}
    checked = 0
    miss = []
    for sid in EXPECTED:
        for item in extensions_for(sid):
            if item.get("local_work") not in all_works:
                continue
            text = (TEXTS / by_work[item["local_work"]]).read_text(encoding="utf-8")
            flat = re.sub(r"\s+", "", text)
            blob = " ".join(item.get("points", [])) + " " + item.get("intro", "")
            for quote in re.findall(r"「([^」]{6,})」", blob):
                q = re.sub(r"\s+", "", quote)
                checked += 1
                if q and q not in flat:
                    miss.append(f"{sid}/《{item['title']}》: 「{quote[:40]}」")
    assert checked >= 30, f"引文核对样本过少：{checked}"
    assert not miss, "引文与正文不逐字一致：\n" + "\n".join(miss)


def test_d124_chapter_count_unchanged():
    from content.routes import SECTIONS
    assert len(SECTIONS) == 32
