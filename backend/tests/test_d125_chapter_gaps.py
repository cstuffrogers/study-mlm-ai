"""D125 门禁：按九个章节的内容缺口补 13 篇

立项依据（写死在这里）：这一批不是「按作者全集补全」，而是先把 32 章的
延伸阅读逐章过一遍，找出「讲得到架子、举不出原文」的位置，再补上那一篇。

  · 国家与革命：夺权｜`sec_B_02`——补列宁 1917 年夺权三篇：《论策略书》
    （1917.4）、《马克思主义和起义》（1917.9）、《布尔什维克能保持国家
    政权吗？》（1917.10）。
  · 异化劳动与人的解放｜`sec_A_12`——补马克思《论犹太人问题》（1843）。
  · 打碎旧国家机器：法兰西内战｜`sec_A_09`——补李大钊《一八七一年的巴黎
    “康妙恩”》（1923）。
  · 辩证唯物主义要义｜`sec_A_13`——补列宁《卡尔·马克思（传略和马克思主义
    概述）》的哲学部分（1914）。
  · 调查研究与阶级分析的范本｜`sec_B_09`——补李大钊《土地与农民》（1925）、
    《鲁豫陕等省的红枪会》（1926）。
  · 新民主主义论｜`sec_C_02`——补李大钊《马克思的中国民族革命观》（1926）。
  · 论人民民主专政｜`sec_C_03`——补毛泽东《关于中华人民共和国宪法草案》
    （1954）、周恩来《关于我国民族政策的几个问题》（1957）。
  · 革命政党的战略与策略｜`sec_B_08`——补周恩来《论统一战线》（1945）。
  · 中国社会各阶级的分析｜`sec_B_03`——补邓中夏《我们的力量》（1924）。

收录口径：12 篇全文照录、一字未改；《卡尔·马克思》只按小节标题裁为哲学
部分（保留「序言」、传略与「马克思的学说」下哲学唯物主义、辩证法、唯物
主义历史观、阶级斗争四节），边界落在标题行上，篇内文字不动。

分档：列宁／马克思／毛泽东／周恩来／李大钊为「经典原著／1.0」（与各自既有
条目同档）；邓中夏为「正统／0.9」（与既有《中国职工运动简史（节选）》同档）。
"""
import re
from pathlib import Path

import pytest

from content.book_chunks import BOOKS, _GENERIC_TERMS, all_book_chunks
from content.reading_extensions import extensions_for

TEXTS = Path(__file__).resolve().parents[2] / "sources" / "texts"

# 文件 → (work, author, 分档, 权重, 篇首识别行, 篇末溯源行)
WORKS = {
    "1-论策略书.txt": (
        "论策略书", "列宁", "经典原著", 1.0,
        "（1917年4月8日和13日〔21日和26日〕之间）",
        "出席全俄工兵代表苏维埃会议的布尔什维克代表和孟什维克代表的联席会议",
    ),
    "1-马克思主义和起义.txt": (
        "马克思主义和起义", "列宁", "经典原著", 1.0,
        "给俄国社会民主工党（布）中央委员会的信",
        "译自《列宁全集》俄文第5版第34卷第242—247页",
    ),
    "1-布尔什维克能保持国家政权吗.txt": (
        "布尔什维克能保持国家政权吗？", "列宁", "经典原著", 1.0,
        "（1917年9月底—10月1日〔14日〕）",
        "莫尔恰林是俄国作家亚·谢·格里鲍耶陀夫的喜剧《智慧的痛苦》中的主人公",
    ),
    "1-论犹太人问题.txt": (
        "论犹太人问题", "马克思", "经典原著", 1.0,
        "布鲁诺·鲍威尔；《犹太人问题》1843年不伦瑞克版",
        "马克思这里说的“犹太精神”，德文原文是Judentum",
    ),
    "1-一八七一年的巴黎康妙恩.txt": (
        "一八七一年的巴黎“康妙恩”", "李大钊", "经典原著", 1.0,
        "（五十年的回顾 社会革命的先声）",
        "署名：李大钊",
    ),
    "1-卡尔马克思传略和马克思主义概述节选.txt": (
        "卡尔·马克思（传略和马克思主义概述·节选）", "列宁", "经典原著", 1.0,
        "（传略和马克思主义概述） [85]",
        "把唯物主义贯彻和推广运用于社会现象领域",
    ),
    "1-土地与农民.txt": (
        "土地与农民", "李大钊", "经典原著", 1.0,
        "一 中国历史上平均地权运动",
        "署名：守常",
    ),
    "1-鲁豫陕等省的红枪会.txt": (
        "鲁豫陕等省的红枪会", "李大钊", "经典原著", 1.0,
        "帝国主义者和军阀扰乱中国，以致内乱踵起",
        "是农民运动的仇敌",
    ),
    "1-马克思的中国民族革命观.txt": (
        "马克思的中国民族革命观", "李大钊", "经典原著", 1.0,
        "马克思批评当代历史事实的论文，是无产阶级研究马克思的人们绝好的材料的宝藏",
        "我们读了马克思这篇论文以后",
    ),
    "1-论统一战线.txt": (
        "论统一战线", "周恩来", "经典原著", 1.0,
        "（一九四五年四月三十日）",
        "所以领导权的问题，是统一战线中最集中的一个问题",
    ),
    "1-关于中华人民共和国宪法草案.txt": (
        "关于中华人民共和国宪法草案", "毛泽东", "经典原著", 1.0,
        "这是毛泽东同志在中央人民政府委员会第三十次会议上的讲话",
        "指袁世凯政府一九一三年的天坛宪法草案",
    ),
    "1-关于我国民族政策的几个问题.txt": (
        "关于我国民族政策的几个问题", "周恩来", "经典原著", 1.0,
        "（一九五七年八月四日）",
        "不信仰宗教的人和信仰宗教的人都可以合作",
    ),
    "1-我们的力量.txt": (
        "我们的力量", "邓中夏", "正统", 0.9,
        "（载于一九二四年十一月出版的《中国工人》第二期）",
        "原载《中国工人》第2期",
    ),
}

KEY_LINES = {
    "1-论策略书.txt": [
        "我也就没有权利推辞了。",
        "俄国当前形势的特点",
    ],
    "1-马克思主义和起义.txt": [
        "马克思主义者象对待艺术那样对待起义",
        "必须 赢得 第一次胜利",
    ],
    "1-布尔什维克能保持国家政权吗.txt": [
        "从理论的领域转到了实践的领域",
        "现在不应当用言论，而应当用行动来回答这个问题",
    ],
    "1-论犹太人问题.txt": [
        "它必须提出问题：这里指的是 哪一类解放 ？",
        "政治解放不是彻头彻尾、没有矛盾的 人的 解放方式",
    ],
    "1-一八七一年的巴黎康妙恩.txt": [
        "巴黎的人民在“巴黎康妙恩”（The Commune of Paris）名义之下开始了一个自由的新时代",
    ],
    "1-卡尔马克思传略和马克思主义概述节选.txt": [
        "哲学唯物主义",
        "辩证法",
        "唯物主义历史观",
        "阶级斗争",
    ],
    "1-土地与农民.txt": [
        "农民约占总人口百分之七十以上",
    ],
    "1-鲁豫陕等省的红枪会.txt": [
        "远则为白莲教的支裔，近则为义和团的流派",
    ],
    "1-马克思的中国民族革命观.txt": [
        "无产阶级研究马克思的人们绝好的材料的宝藏",
    ],
    "1-论统一战线.txt": [
        "领导权的问题，是统一战线中最集中的一个问题",
        "空喊无产阶级领导",
    ],
    "1-关于中华人民共和国宪法草案.txt": [
        "全国有代表性的八千多人的广泛讨论",
        "这个宪法草案，看样子是得人心的",
    ],
    "1-关于我国民族政策的几个问题.txt": [
        "实行民族区域自治，是我们解放以后在民族问题上的一个根本性的政策",
        "这是我国宪法上规定了的",
    ],
    "1-我们的力量.txt": [
        "中国所有产业工人总人数是一百八十五万余人",
    ],
}

# 延伸阅读挂接：章节 → 篇名集合
EXPECTED = {
    "sec_B_02": {"论策略书", "马克思主义和起义", "布尔什维克能保持国家政权吗？"},
    "sec_A_12": {"论犹太人问题"},
    "sec_A_09": {"一八七一年的巴黎“康妙恩”"},
    "sec_A_13": {"卡尔·马克思（传略和马克思主义概述·节选）"},
    "sec_B_09": {"土地与农民", "鲁豫陕等省的红枪会"},
    "sec_C_02": {"马克思的中国民族革命观"},
    "sec_C_03": {"关于中华人民共和国宪法草案", "关于我国民族政策的几个问题"},
    "sec_B_08": {"论统一战线"},
    "sec_B_03": {"我们的力量"},
}

# 本批唯一允许做篇内裁剪的一篇（按小节标题裁到哲学部分）
TRIMMED = "1-卡尔马克思传略和马克思主义概述节选.txt"

DISPLAY_JARGON = re.compile(r"D\d{2,3}|TRIM|sec_[A-C]_\d\d|OCR|PDF|HTML|入库|镜像|分片|\.txt|\.md")


@pytest.mark.parametrize("fname", sorted(WORKS))
def test_d125_text_present_and_traceable(fname):
    path = TEXTS / fname
    assert path.exists(), f"缺正文文件：{fname}"
    t = path.read_text(encoding="utf-8")
    _work, _author, _tag, _score, head, tail = WORKS[fname]
    assert head in t[:1200], f"{fname}: 篇首识别行缺失「{head}」"
    assert tail in t, f"{fname}: 篇末溯源行缺失「{tail}」"
    assert len(t) > 800, f"{fname}: 正文过短（{len(t)} 字符），疑似只剩导读"
    assert "\n\n\n\n" not in t, f"{fname}: 出现连续空行，疑似拼接残留"


@pytest.mark.parametrize("fname", sorted(WORKS))
def test_d125_key_lines_verbatim(fname):
    flat = re.sub(r"\s+", "", (TEXTS / fname).read_text(encoding="utf-8"))
    for line in KEY_LINES[fname]:
        assert re.sub(r"\s+", "", line) in flat, f"{fname}: 关键句不逐字匹配「{line}」"


@pytest.mark.parametrize("fname", sorted(WORKS))
def test_d125_book_meta(fname):
    work, author, tag, score, _head, _tail = WORKS[fname]
    hits = [b for b in BOOKS if b["file"] == fname]
    assert len(hits) == 1, f"{fname}: BOOKS 里应恰好登记一次，实际 {len(hits)}"
    b = hits[0]
    assert b["work"] == work, f"{fname}: work 应为「{work}」，实际「{b['work']}」"
    assert b["author"] == author, f"{fname}: 作者应为「{author}」，实际「{b['author']}」"
    assert b["orthodoxy_tag"] == tag, f"{fname}: 分档应为「{tag}」，实际「{b['orthodoxy_tag']}」"
    assert b["authority_score"] == score, f"{fname}: 权重应为 {score}，实际 {b['authority_score']}"


def test_d125_prefix_and_slug_unique():
    mine = [b for b in BOOKS if b["file"] in WORKS]
    assert len(mine) == 13, f"本批条目应为 13 条，实际 {len(mine)}"
    prefixes = [b["id_prefix"] for b in BOOKS]
    slugs = [b["slug"] for b in BOOKS]
    assert len(set(prefixes)) == len(prefixes), "id_prefix 全库重复"
    assert len(set(slugs)) == len(slugs), "slug 全库重复"
    for b in mine:
        assert re.fullmatch(r"CH-[A-Z]{4}-", b["id_prefix"]), \
            f"id_prefix 形如「CH-XXXX-」：{b['id_prefix']}"


def test_d125_chunks_indexed():
    chunks = all_book_chunks()
    for fname, (work, *_rest) in WORKS.items():
        mine = [c for c in chunks if c.get("source") == work]
        assert mine, f"{fname}: 分片未进索引进（work={work}）"
        assert all(c["text"].strip() for c in mine), f"{fname}: 存在空分片"
        ids = [c["id"] for c in mine]
        assert len(set(ids)) == len(ids), f"{fname}: 分片 id 重复"


def test_d125_extensions_wired():
    all_works = {w for s in EXPECTED.values() for w in s}
    assert len(all_works) == 13
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


def test_d125_sections_still_32():
    from content.routes import SECTIONS
    assert len(SECTIONS) == 32
    ids = {s["id"] for s in SECTIONS}
    assert set(EXPECTED) <= ids, f"挂接到了不存在的章节：{sorted(set(EXPECTED) - ids)}"


def test_d125_rebuild_matches_library():
    """从源页重新拼接必须与库内正文逐字相同（含唯一一篇按标题行裁剪的节选）。"""
    import importlib.util

    mp = Path(__file__).resolve().parents[2] / "scripts" / "import_mirror.py"
    spec = importlib.util.spec_from_file_location("import_mirror_d125", mp)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)

    by_file = {s["file"]: s for s in mod.SPECS}
    for fname in WORKS:
        assert fname in by_file, f"{fname}: 源规格里没有这一篇"
        text, cn = mod.build(by_file[fname])
        cur = (TEXTS / fname).read_text(encoding="utf-8")
        assert text == cur, f"{fname}: 从源页重新拼接与库内正文不一致（原文被改写？）"
        assert cn == len(re.findall(r"[\u4e00-\u9fff]", cur))


def test_d125_only_one_piece_is_trimmed():
    """除《卡尔·马克思》按小节标题取哲学部分外，本批篇内一律不裁。"""
    import importlib.util

    mp = Path(__file__).resolve().parents[2] / "scripts" / "import_mirror.py"
    spec = importlib.util.spec_from_file_location("import_mirror_d125b", mp)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)

    trimmed = sorted(f for f in WORKS if f in mod.TRIM)
    assert trimmed == [TRIMMED], f"本批只应裁剪一篇，实际 {trimmed}"
    segs = mod.TRIM[TRIMMED]["segments"]
    assert segs == [(None, 1, "马克思的经济学说", 1)], \
        f"裁剪边界应落在「马克思的经济学说」标题行，实际 {segs}"


def test_d125_trim_keeps_philosophy_drops_economics():
    """节选边界核对：哲学四节在、经济学说与书目不在。"""
    t = (TEXTS / TRIMMED).read_text(encoding="utf-8")
    lines = {ln.strip() for ln in t.split("\n")}
    for keep in ("序言", "哲学唯物主义", "辩证法", "唯物主义历史观", "阶级斗争"):
        assert keep in lines, f"节选漏掉了小节标题「{keep}」"
    # 只按标题行判定：正文里提到「经济学说」是保留段落的原话，不算越界
    for drop in ("马克思的经济学说", "社会主义", "无产阶级阶级斗争的策略", "书目"):
        assert drop not in lines, f"节选越界，混进了小节「{drop}」"


def test_d125_generic_terms_widened():
    """起义／宪法／异化等是本批新词族，不进词表则检索零命中。"""
    for w in ("起义", "宪法", "异化", "巴黎公社", "土地革命", "领导权", "农民运动"):
        assert w in _GENERIC_TERMS, f"通用概念词缺「{w}」"
    mentions = {t for c in all_book_chunks()
                if c.get("source") in {v[0] for v in WORKS.values()}
                for t in c.get("concept_mentions", [])}
    for w in ("起义", "宪法", "异化"):
        assert w in mentions, f"本批分片侧未抽到「{w}」mention"


def test_d125_quotes_verbatim():
    """延伸阅读里所有「」引文必须逐字出现在正文（只认原文逐字句）。"""
    all_works = {w for s in EXPECTED.values() for w in s}
    by_work = {v[0]: f for f, v in WORKS.items()}
    checked = 0
    miss = []
    for sid in EXPECTED:
        for item in extensions_for(sid):
            if item.get("local_work") not in all_works:
                continue
            flat = re.sub(r"\s+", "",
                          (TEXTS / by_work[item["local_work"]]).read_text(encoding="utf-8"))
            blob = " ".join(item.get("points", [])) + " " + item.get("intro", "")
            for quote in re.findall(r"「([^」]{6,})」", blob):
                q = re.sub(r"\s+", "", quote)
                checked += 1
                if q and q not in flat:
                    miss.append(f"{sid}/《{item['title']}》: 「{quote[:40]}」")
    assert checked >= 25, f"引文核对样本过少：{checked}"
    assert not miss, "引文与正文不逐字一致：\n" + "\n".join(miss)


def test_d125_no_critical_material():
    """排除项：批判资料与托派文献一篇也不许混入本批。"""
    banned = ["批判资料", "反革命修正主义", "我们的政治意见书", "告全党同志书"]
    files = {p.name for p in TEXTS.glob("*.txt")}
    for b in banned:
        bad = sorted(f for f in files if b in f)
        assert not bad, f"批判资料混进了正文目录：{bad}"
    for b in BOOKS:
        for word in banned:
            assert word not in (b.get("work") or ""), f"《{b['work']}》属排除项（{word}）"
