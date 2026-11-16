"""D127 门禁：考茨基 4 篇（1887 / 1892 / 1898 / 1908）

立项依据（写死在这里）：这一批从「章节缺什么原文」出发选篇，不按年份铺开。

  · 剩余价值与资本主义积累：资本论｜`sec_A_08`——补《马克思的经济学说》（1887），
    《资本论》第一卷同时代的通俗转述：三篇二十章，篇目次序与原著一致。
  · 怎么办？：建党原则｜`sec_B_01`——补《爱尔福特纲领解说》（1892），
    德国社会民主党爱尔福特纲领的逐条解说，取其中「历史部分」三章。
  · 调查研究与阶级分析的范本｜`sec_B_09`——补《土地问题》（1898），
    从封建农村经济讲到资本主义农业的农村阶级分析长篇。
  · 体系收拢（二）：历史唯物主义要义｜`sec_A_14`——补《基督教之基础》（1908），
    用唯物史观处理具体对象（罗马帝国时代的奴隶制经济—国家—思潮）的完整实例。

收录口径：四部均据中译本的转录文本，原文一字未改；译者说明、出版者说明、
著者序、章末注释与 〔NN〕/ [NN] 编者注一律保留。《马克思的经济学说》篇幅较小，
全书照录不裁；另三部为长篇，按篇／章标题行裁为节选，边界落在标题行上，
章内不删一句。

分档：全部「正统／0.9」，**不记「经典原著／1.0」**——考茨基是第二国际的理论家，
其国家与革命学说后来被列宁《国家与革命》《无产阶级革命和叛徒考茨基》正面批判，
库内只作历史文献与思想史材料。这一立场在每条 extent 的 caution 里写明。
"""
import re
from pathlib import Path

import pytest

from content.book_chunks import BOOKS, all_book_chunks
from content.reading_extensions import extensions_for

TEXTS = Path(__file__).resolve().parents[2] / "sources" / "texts"

# 文件 → (work, 作者, 分档, 权重, 篇首识别行, 篇末溯源行)
WORKS = {
    "1-马克思的经济学说.txt": (
        "马克思的经济学说", "考茨基", "正统", 0.9,
        "俄译本出版说明",
        "1957年8月",
    ),
    "1-爱尔福特纲领解说节选.txt": (
        "爱尔福特纲领解说（节选）", "考茨基", "正统", 0.9,
        "出版者说明",
        "——俄文版编者",
    ),
    "1-土地问题节选.txt": (
        "土地问题（节选）", "考茨基", "正统", 0.9,
        "著者序",
        "科学与商业之紧密的联系乃是整个现代生产方式所固有的特征",
    ),
    "1-基督教之基础节选.txt": (
        "基督教之基础（节选）", "考茨基", "正统", 0.9,
        "引论",
        "再进行一种对犹太民族的特殊研究",
    ),
}

# 每篇的关键句（须逐字出现在该篇正文里）
KEY_LINES = {
    "1-马克思的经济学说.txt": [
        "俄译本出版说明",
        "第一篇 商品、货币和资本",
        "第三章 货币变为资本",
        "随着劳动生产率的改变，社会必要的劳动时间也会改变，价值也会改变。",
        "译后记",
    ],
    "1-爱尔福特纲领解说节选.txt": [
        "出版者说明",
        "著者第一版序",
        "第一章 小生产的灭亡",
        "第三章 资本家阶级",
        "没有比同万能的资本进行斗争的小生产者或农民的生活，更悲惨和更不幸的了。",
    ],
    "1-土地问题节选.txt": [
        "著者序",
        "第一章 绪论",
        "第四章 现代的农村经济",
        "资本并不是把它的势力限于城市工业。资本一旦充分地加强起来，它便使农业屈服于自己。",
    ],
    "1-基督教之基础节选.txt": [
        "第一章 蓄奴制度",
        "第三章 罗马帝国时代之思潮",
        "七 一神主义",
        "这一切情形都给基督教打上它们的印记，并且在基督教的形式中留下它们的遗迹。",
    ],
}

# 章节 → 本批挂接的篇目
EXPECTED = {
    "sec_A_08": {"马克思的经济学说"},
    "sec_B_01": {"爱尔福特纲领解说（节选）"},
    "sec_B_09": {"土地问题（节选）"},
    "sec_A_14": {"基督教之基础（节选）"},
}

# 裁剪进 TRIM 表的三部（1887 那部全书照录，不裁）
TRIMMED = {
    "1-爱尔福特纲领解说节选.txt": (
        "1-爱尔福特纲领解说节选.txt",
        ("第四章 未来的国家", "第五章 阶级斗争"),
    ),
    "1-土地问题节选.txt": (
        "1-土地问题节选.txt",
        ("第五章 现代农村经济的资本主义性质", "社会民主主义的土地政策"),
    ),
    "1-基督教之基础节选.txt": (
        "1-基督教之基础节选.txt",
        ("第一篇 耶稣的人格", "第三篇 犹太民族"),
    ),
}

DISPLAY_JARGON = re.compile(r"D\d{2,3}|TRIM|sec_[A-C]_\d\d|OCR|PDF|HTML|入库|镜像|分片|\.txt|\.md")


def _load_mirror():
    import importlib.util

    mp = Path(__file__).resolve().parents[2] / "scripts" / "import_mirror.py"
    spec = importlib.util.spec_from_file_location("import_mirror_d127", mp)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


@pytest.mark.parametrize("fname", sorted(WORKS))
def test_d127_text_present_and_traceable(fname):
    path = TEXTS / fname
    assert path.exists(), f"缺正文文件：{fname}"
    t = path.read_text(encoding="utf-8")
    _work, _author, _tag, _score, head, tail = WORKS[fname]
    assert head in t[:1500], f"{fname}: 篇首识别行缺失「{head}」"
    assert tail in t, f"{fname}: 篇末溯源行缺失「{tail}」"
    assert len(t) > 30000, f"{fname}: 正文过短（{len(t)} 字符），疑似只剩导读"
    assert "\n\n\n\n" not in t, f"{fname}: 出现连续空行，疑似拼接残留"


@pytest.mark.parametrize("fname", sorted(WORKS))
def test_d127_key_lines_verbatim(fname):
    txt = (TEXTS / fname).read_text(encoding="utf-8")
    # 〔NN〕/ [NN] 编者注号不是原文文字，比对前连同空白一起剥掉
    flat = re.sub(r"\s+", "", re.sub(r"[〔\[]\d+[〕\]]", "", txt))
    for line in KEY_LINES[fname]:
        assert re.sub(r"\s+", "", line) in flat, f"{fname}: 关键句不逐字匹配「{line}」"


@pytest.mark.parametrize("fname", sorted(WORKS))
def test_d127_book_meta(fname):
    work, author, tag, score, _head, _tail = WORKS[fname]
    hits = [b for b in BOOKS if b["file"] == fname]
    assert len(hits) == 1, f"{fname}: BOOKS 里应恰好登记一次，实际 {len(hits)}"
    b = hits[0]
    assert b["work"] == work, f"{fname}: work 应为「{work}」，实际「{b['work']}」"
    assert b["author"] == author, f"{fname}: 作者应为「{author}」，实际「{b['author']}」"
    assert b["orthodoxy_tag"] == tag, f"{fname}: 分档应为「{tag}」，实际「{b['orthodoxy_tag']}」"
    assert b["authority_score"] == score, f"{fname}: 权重应为 {score}，实际 {b['authority_score']}"


def test_d127_not_classic_original():
    """红线：考茨基不是经典作家，四部一律不得记「经典原著／1.0」。"""
    mine = [b for b in BOOKS if b["file"] in WORKS]
    assert len(mine) == 4, f"本批条目应为 4 条，实际 {len(mine)}"
    for b in mine:
        assert b["orthodoxy_tag"] != "经典原著", f"{b['file']}: 不得记「经典原著」"
        assert b["authority_score"] < 1.0, f"{b['file']}: 权重不得取 1.0"


def test_d127_prefix_and_slug_unique():
    mine = [b for b in BOOKS if b["file"] in WORKS]
    prefixes = [b["id_prefix"] for b in BOOKS]
    slugs = [b["slug"] for b in BOOKS]
    assert len(set(prefixes)) == len(prefixes), "id_prefix 全库重复"
    assert len(set(slugs)) == len(slugs), "slug 全库重复"
    for b in mine:
        assert re.fullmatch(r"CH-[A-Z]{4}-", b["id_prefix"]), \
            f"id_prefix 形如「CH-XXXX-」：{b['id_prefix']}"


def test_d127_chunks_indexed():
    chunks = all_book_chunks()
    for fname, (work, *_rest) in WORKS.items():
        mine = [c for c in chunks if c.get("source") == work]
        assert mine, f"{fname}: 分片未进索引（work={work}）"
        assert all(c["text"].strip() for c in mine), f"{fname}: 存在空分片"
        ids = [c["id"] for c in mine]
        assert len(set(ids)) == len(ids), f"{fname}: 分片 id 重复"
        assert len(mine) > 100, f"{fname}: 分片数过少（{len(mine)}）"


def test_d127_extensions_wired():
    works = {w for s in EXPECTED.values() for w in s}
    assert len(works) == 4
    for sid, target in EXPECTED.items():
        items = extensions_for(sid)
        local = {i.get("local_work") for i in items if i.get("local_work")}
        missing = target - local
        assert not missing, f"{sid}: 缺延伸阅读挂接 {sorted(missing)}"
        for i in items:
            if i.get("local_work") not in works:
                continue
            assert i["kind"] == "classic", \
                f"{sid}/《{i['title']}》: kind 应为 classic，实际「{i['kind']}」"
            assert i.get("points"), f"{sid}/《{i['title']}》: 缺要点"
            assert "一字未改" in i.get("caution", ""), \
                f"{sid}/《{i['title']}》: caution 须写明「一字未改」"
            assert "第二国际" in i.get("caution", ""), \
                f"{sid}/《{i['title']}》: caution 须写明作者属于第二国际"
            assert "列宁" in i.get("caution", ""), \
                f"{sid}/《{i['title']}》: caution 须写明后来被列宁批判"
            m = DISPLAY_JARGON.search(i.get("caution", ""))
            assert not m, f"{sid}/《{i['title']}》: caution 出现开发期术语「{m.group(0)}」"


def test_d127_sections_still_32():
    from content.routes import SECTIONS
    assert len(SECTIONS) == 32
    ids = {s["id"] for s in SECTIONS}
    assert set(EXPECTED) <= ids, f"挂接到了不存在的章节：{sorted(set(EXPECTED) - ids)}"


def test_d127_rebuild_matches_library():
    """从源页重新拼接必须与库内正文逐字相同（正文不经二次改写）。"""
    mod = _load_mirror()
    by_file = {s["file"]: s for s in mod.SPECS}
    for fname in WORKS:
        assert fname in by_file, f"{fname}: 源规格里没有这一篇"
        text, cn = mod.build(by_file[fname])
        cur = (TEXTS / fname).read_text(encoding="utf-8")
        assert text == cur, f"{fname}: 从源页重新拼接与库内正文不一致（原文被改写？）"
        assert cn == len(re.findall(r"[\u4e00-\u9fff]", cur))


def test_d127_trim_boundaries_and_scope():
    """三部长篇的裁剪边界必须落在标题行上，且被裁掉的章题不得残留在正文里。"""
    mod = _load_mirror()
    assert "1-马克思的经济学说.txt" not in mod.TRIM, "1887 那部应全书照录，不进裁剪表"
    for fname, (_key, gone) in TRIMMED.items():
        assert fname in mod.TRIM, f"{fname}: 未进裁剪表"
        cfg = mod.TRIM[fname]
        assert cfg.get("desc"), f"{fname}: 裁剪表缺 desc"
        assert cfg.get("segments"), f"{fname}: 裁剪表缺 segments"
        for seg in cfg["segments"]:
            assert len(seg) == 4, f"{fname}: segments 应为四元组"
            for marker in (seg[0], seg[2]):
                assert marker is None or isinstance(marker, str), f"{fname}: 边界应为标题行"
        t = (TEXTS / fname).read_text(encoding="utf-8")
        for title in gone:
            assert title not in t, f"{fname}: 已裁去的章题仍留在正文里「{title}」"


def test_d127_1908_no_page_chrome():
    """1908 那部：镜像每页沿页重复的书名行已按行删除；章标题只留每章首见的一行。"""
    t = (TEXTS / "1-基督教之基础节选.txt").read_text(encoding="utf-8")
    assert "考茨基：基督教之基础" not in t, "站点头部行未删净"
    for title in ("第一章 蓄奴制度", "第二章 国家的生活", "第三章 罗马帝国时代之思潮"):
        assert t.count(title) == 1, f"{title}: 应只出现在章首一行，实际 {t.count(title)} 次"
    assert ">> 第二章 国家的生活" in t, "章标题行被误删"


def test_d127_trim_reproducible_from_backup():
    """从裁剪前全文按 TRIM 重切，必须与现库逐字节一致（原文一字未改、可复现）。"""
    mod = _load_mirror()
    backup = Path(__file__).resolve().parents[2] / "sources" / "_backup_d127_pretrim"
    trimmed = tuple(TRIMMED)
    assert {p.name for p in backup.glob("*.txt")} == set(trimmed), \
        "备份应且只应含这 3 部裁剪前全文"
    for f in trimmed:
        full = (backup / f).read_text(encoding="utf-8")
        cur = (TEXTS / f).read_text(encoding="utf-8")
        assert len(cur) < len(full), f"{f} 未裁剪"
        assert 0.10 < len(cur) / len(full) < 0.90, f"{f} 裁剪比例异常"
        assert mod.apply_trim(f, full) == cur, f"{f} 裁剪结果不可复现（原文被改写？）"


def test_d127_quotes_verbatim():
    """延伸阅读里「」内的文字必须逐字出现在该条目自己的正文中。"""
    works = {w for s in EXPECTED.values() for w in s}
    fmap = {b["work"]: b["file"] for b in BOOKS}
    checked = 0
    bad = 0
    for sid in EXPECTED:
        for it in extensions_for(sid):
            w = it.get("local_work")
            if w not in works:
                continue
            t = (TEXTS / fmap[w]).read_text(encoding="utf-8")
            t = re.sub(r"[〔\[]\d+[〕\]]", "", t)
            t = re.sub(r"\s+", "", t)
            body = "".join(it["points"]) + it["intro"] + it["how_to_use"]
            for q in re.findall(r"「([^」]*)」", body):
                qq = re.sub(r"[〔\[]\d+[〕\]]", "", q)
                qq = re.sub(r"\s+", "", qq)
                checked += 1
                if qq not in t:
                    bad += 1
                    print(f"{sid}/《{it['title']}》: 引文不逐字「{q}」")
    assert checked >= 25, f"逐字核对样本过少：{checked}"
    assert bad == 0, f"引文不逐字的条目有 {bad} 处"


def test_d127_kautsky_corpus_4():
    """考茨基在库内应为 4 部（此前无考茨基著作）。"""
    mine = [b for b in BOOKS if b["author"] == "考茨基"]
    assert len(mine) == 4, f"考茨基篇目应为 4，实际 {len(mine)}"
    files = {b["file"] for b in mine}
    assert files == set(WORKS), f"书目与本批不一致：{sorted(files)}"


def test_d127_duplicates_free():
    """与既有延伸阅读条目零重复。"""
    works = {w for s in EXPECTED.values() for w in s}
    titles = []
    for items in extensions_for.__globals__["READING_EXTENSIONS"].values():
        for it in items:
            if it.get("local_work") in works:
                titles.append(it["title"])
    assert len(titles) == 4, f"挂接条目应为 4 条：{len(titles)}"
    assert len(set(titles)) == 4, "挂接条目标题重复"


def test_d127_scoped_to_selected_chapters():
    """四部正文各自只该出现在本章，不得串章挂接。"""
    for sid, target in EXPECTED.items():
        local = {i.get("local_work") for i in extensions_for(sid) if i.get("local_work")}
        others = {w for s in EXPECTED.values() for w in s} - target
        assert not (local & others), f"{sid}: 混入了他章的挂接 {sorted(local & others)}"
