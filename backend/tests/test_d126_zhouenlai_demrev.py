"""D126 门禁：周恩来民主革命期 12 篇，按六章的内容缺口补

立项依据（写死在这里）：这一批延续「按章节缺口选篇」，不按年份铺开——先把
六章的延伸阅读逐条过一遍，找出「讲得到架子、举不出原文」的位置，再补那一篇。

  · 怎么办？：建党原则｜`sec_B_01`——补《中共中央给红军第四军前委的指示信》
    （1929.9，九月来信）、《坚决肃清党内一切非无产阶级的意识》（1928.11）。
  · 国家与革命：夺权｜`sec_B_02`——补《全国大反攻，打倒蒋介石》（1947.9）、
    《关于和平谈判问题的报告》（1949.4）。
  · 中国社会各阶级的分析｜`sec_B_03`——补《论中国的法西斯主义——新专制主义》
    （1943.8）。
  · 革命政党的战略与策略｜`sec_B_08`——补《现时政治斗争中之我们》（1926.12）、
    《关于一九二四至二六年党对国民党的关系》（1943 春）、《一年来的谈判及
    前途》（1946.12）。
  · 调查研究与阶级分析的范本｜`sec_B_09`——补《老区半老区的土地改革与整党
    工作》（1948.2）。
  · 新民主主义论｜`sec_C_02`——补《人民政协共同纲领草案的特点》（1949.9）、
    《恢复生产，建设中国》（1949.7）、《新民主主义的经济建设》（1948.6）。

收录口径：12 篇全文照录、一字未改、不设裁剪、不留裁剪备份。其中四篇自带
删节或摘要题注（九月来信「个别段落没有选入」、论中国的法西斯主义「第五部分
有删节」、一年来的谈判及前途「第二部分是摘要」、恢复生产建设中国「讲话
摘要」）——删节是选集编辑所为，本篇原样保留并在题注里注明。

分档：全部「经典原著／1.0」，与库内既有周恩来 15 篇同档。
"""
import re
from pathlib import Path

import pytest

from content.book_chunks import BOOKS, all_book_chunks
from content.reading_extensions import extensions_for

TEXTS = Path(__file__).resolve().parents[2] / "sources" / "texts"

# 文件 → (work, author, 分档, 权重, 篇首识别行, 篇末溯源行)
WORKS = {
    "1-中共中央给红军第四军前委的指示信.txt": (
        "中共中央给红军第四军前委的指示信", "周恩来", "经典原著", 1.0,
        "四军前委并转全体同志：",
        "收入本书时个别段落没有选入",
    ),
    "1-坚决肃清党内一切非无产阶级的意识.txt": (
        "坚决肃清党内一切非无产阶级的意识", "周恩来", "经典原著", 1.0,
        "党的政治路线上许多不正确思想的来源",
        "这部分是周恩来同志起草的",
    ),
    "1-现时政治斗争中之我们.txt": (
        "现时政治斗争中之我们", "周恩来", "经典原著", 1.0,
        "我们既肯定而且坚信目前的政治争斗",
        "发表于中共两广区委机关刊物《人民周刊》第三十七期",
    ),
    "1-关于一九二四至二六年党对国民党的关系.txt": (
        "关于一九二四至二六年党对国民党的关系", "周恩来", "经典原著", 1.0,
        "国共合作后，孙中山先生在中国共产党的帮助下",
        "这是在重庆中共中央南方局干部学习会上所做的报告",
    ),
    "1-一年来的谈判及前途.txt": (
        "一年来的谈判及前途", "周恩来", "经典原著", 1.0,
        "一年来的情况很复杂，变化多端",
        "其中第二部分是摘要",
    ),
    "1-论中国的法西斯主义新专制主义.txt": (
        "论中国的法西斯主义——新专制主义", "周恩来", "经典原著", 1.0,
        "一 问题的提出和回答",
        "收入本书时第五部分有删节",
    ),
    "1-全国大反攻打倒蒋介石.txt": (
        "全国大反攻，打倒蒋介石", "周恩来", "经典原著", 1.0,
        "现在已进入大反攻时期",
        "本文是在陕北佳县神泉堡对中共中央直属单位干部、战士所做的关于时局问题的报告",
    ),
    "1-关于和平谈判问题的报告.txt": (
        "关于和平谈判问题的报告", "周恩来", "经典原著", 1.0,
        "各位朋友：今天特别请诸位来此聚会",
        "北平一些大学教授做的报告",
    ),
    "1-老区半老区的土地改革与整党工作.txt": (
        "老区半老区的土地改革与整党工作", "周恩来", "经典原著", 1.0,
        "根据各地最近数月的报告看来",
        "这是为中共中央起草的指示，经毛泽东同志修改过",
    ),
    "1-人民政协共同纲领草案的特点.txt": (
        "人民政协共同纲领草案的特点", "周恩来", "经典原著", 1.0,
        "草案，是新政治协商会议",
        "周恩来同志受党中央委派主持起草了人民政协的共同纲领",
    ),
    "1-恢复生产建设中国.txt": (
        "恢复生产，建设中国", "周恩来", "经典原著", 1.0,
        "同志们：我们全国工会工作会议开幕了",
        "这是在全国工会工作会议上的讲话摘要",
    ),
    "1-新民主主义的经济建设.txt": (
        "新民主主义的经济建设", "周恩来", "经典原著", 1.0,
        "新民主主义的经济建设是反对旧民主主义或旧资本主义的经济方针的。",
        "这是周恩来同志写的一个提纲",
    ),
}

# 每篇的关键句（须逐字出现在库内正文；含各篇自带删节／摘要的题注原文）
KEY_LINES = {
    "1-中共中央给红军第四军前委的指示信.txt": [
        "四军前委并转全体同志：",
        "党在军阀混战中，应该采取失败主义的策略，发动广大群众，反对军阀混战。",
        "前委要十分注意纠正军事同志以红军为革命本位的狭隘观念。",
        "收入本书时个别段落没有选入。",
    ],
    "1-坚决肃清党内一切非无产阶级的意识.txt": [
        "党的政治路线上许多不正确思想的来源，固然是客观环境的反映",
        "然而党的组织还没有布尔什维克化",
        "第一，极端民主化的倾向。",
    ],
    "1-现时政治斗争中之我们.txt": [
        "何以于国民党之外还有共产党的存在和活动",
        "我们既肯定而且坚信目前的政治争斗是应为打倒半封建势力",
        "不敢坚持无产阶级的领导权",
    ],
    "1-关于一九二四至二六年党对国民党的关系.txt": [
        "接受了我们党起草的宣言，使三民主义成为革命的三民主义，新三民主义。",
        "而且组织上也依靠我们",
        "我们在党务方面已毫无地位了",
    ],
    "1-一年来的谈判及前途.txt": [
        "斗争的双方，在斗争的基本方针上是绝不会让步和变动的。",
        "二 一年谈判的经验教训与将来的前途",
        "其中第二部分是摘要",
    ],
    "1-论中国的法西斯主义新专制主义.txt": [
        "一 问题的提出和回答",
        "对于蒋介石国民党亦即大地主大资产阶级统治的实质，多缺乏深刻的了解。",
        "所以对内总是反对人民，惧怕人民，压迫人民的。",
        "收入本书时第五部分有删节",
    ],
    "1-全国大反攻打倒蒋介石.txt": [
        "中国革命就是农村包围城市而后夺取城市。",
        "现在对，过去也对。",
        "主力打出去以后，地方武装起来",
    ],
    "1-关于和平谈判问题的报告.txt": [
        "国内和平协定八条二十四款，中心问题是接收和改编。",
        "我们要尽可能用和平方法来实现，但如果不能用和平方法，用战斗也一样要把它实现。",
        "中国新民主主义政治是四个阶级合作的。",
    ],
    "1-老区半老区的土地改革与整党工作.txt": [
        "大致应分为三类地区，并应根据三类地区的不同的情况，采取不同的工作方针。",
        "第一类地区，是土地改革较为彻底的地区。",
        "将工作迅速转入生产、整党和建立乡村民主生活上去。",
    ],
    "1-人民政协共同纲领草案的特点.txt": [
        "第一是中国人民民主统一战线的问题。",
        "第八是新民主主义的外交政策问题。",
        "建设一个独立、民主、和平、统一和富强的新中国。",
    ],
    "1-恢复生产建设中国.txt": [
        "在目前这样的形势下，我们工会动员全体工人阶级的口号是：恢复生产，建设新中国。",
        "第三是在私人企业中我们要团结民族资本家。",
        "这是在全国工会工作会议上的讲话摘要",
    ],
    "1-新民主主义的经济建设.txt": [
        "新民主主义的经济建设是反对旧民主主义或旧资本主义的经济方针的。",
        "1.无产阶级领导的经济还是资产阶级领导的经济；",
        "这是周恩来同志写的一个提纲",
    ],
}

# 章节 → 本批挂接的篇目
EXPECTED = {
    "sec_B_01": {"中共中央给红军第四军前委的指示信", "坚决肃清党内一切非无产阶级的意识"},
    "sec_B_02": {"全国大反攻，打倒蒋介石", "关于和平谈判问题的报告"},
    "sec_B_03": {"论中国的法西斯主义——新专制主义"},
    "sec_B_08": {"现时政治斗争中之我们", "关于一九二四至二六年党对国民党的关系",
                 "一年来的谈判及前途"},
    "sec_B_09": {"老区半老区的土地改革与整党工作"},
    "sec_C_02": {"人民政协共同纲领草案的特点", "恢复生产，建设中国", "新民主主义的经济建设"},
}

# 自带删节／摘要题注的四篇（删节是选集编辑所为，本篇原样保留）
EDITOR_CUT = {
    "1-中共中央给红军第四军前委的指示信.txt": "收入本书时个别段落没有选入",
    "1-论中国的法西斯主义新专制主义.txt": "收入本书时第五部分有删节",
    "1-一年来的谈判及前途.txt": "其中第二部分是摘要",
    "1-恢复生产建设中国.txt": "这是在全国工会工作会议上的讲话摘要",
}

DISPLAY_JARGON = re.compile(r"D\d{2,3}|TRIM|sec_[A-C]_\d\d|OCR|PDF|HTML|入库|镜像|分片|\.txt|\.md")


@pytest.mark.parametrize("fname", sorted(WORKS))
def test_d126_text_present_and_traceable(fname):
    path = TEXTS / fname
    assert path.exists(), f"缺正文文件：{fname}"
    t = path.read_text(encoding="utf-8")
    _work, _author, _tag, _score, head, tail = WORKS[fname]
    assert head in t[:1200], f"{fname}: 篇首识别行缺失「{head}」"
    assert tail in t, f"{fname}: 篇末溯源行缺失「{tail}」"
    assert len(t) > 600, f"{fname}: 正文过短（{len(t)} 字符），疑似只剩导读"
    assert "\n\n\n\n" not in t, f"{fname}: 出现连续空行，疑似拼接残留"


@pytest.mark.parametrize("fname", sorted(WORKS))
def test_d126_key_lines_verbatim(fname):
    txt = (TEXTS / fname).read_text(encoding="utf-8")
    # 正文里的〔NN〕编者注号不是原文文字，比对前连同空白一起剥掉
    flat = re.sub(r"\s+", "", re.sub(r"[〔\[]\d+[〕\]]", "", txt))
    for line in KEY_LINES[fname]:
        assert re.sub(r"\s+", "", line) in flat, f"{fname}: 关键句不逐字匹配「{line}」"


@pytest.mark.parametrize("fname", sorted(WORKS))
def test_d126_book_meta(fname):
    work, author, tag, score, _head, _tail = WORKS[fname]
    hits = [b for b in BOOKS if b["file"] == fname]
    assert len(hits) == 1, f"{fname}: BOOKS 里应恰好登记一次，实际 {len(hits)}"
    b = hits[0]
    assert b["work"] == work, f"{fname}: work 应为「{work}」，实际「{b['work']}」"
    assert b["author"] == author, f"{fname}: 作者应为「{author}」，实际「{b['author']}」"
    assert b["orthodoxy_tag"] == tag, f"{fname}: 分档应为「{tag}」，实际「{b['orthodoxy_tag']}」"
    assert b["authority_score"] == score, f"{fname}: 权重应为 {score}，实际 {b['authority_score']}"


def test_d126_prefix_and_slug_unique():
    mine = [b for b in BOOKS if b["file"] in WORKS]
    assert len(mine) == 12, f"本批条目应为 12 条，实际 {len(mine)}"
    prefixes = [b["id_prefix"] for b in BOOKS]
    slugs = [b["slug"] for b in BOOKS]
    assert len(set(prefixes)) == len(prefixes), "id_prefix 全库重复"
    assert len(set(slugs)) == len(slugs), "slug 全库重复"
    for b in mine:
        assert re.fullmatch(r"CH-[A-Z]{4}-", b["id_prefix"]), \
            f"id_prefix 形如「CH-XXXX-」：{b['id_prefix']}"


def test_d126_chunks_indexed():
    chunks = all_book_chunks()
    for fname, (work, *_rest) in WORKS.items():
        mine = [c for c in chunks if c.get("source") == work]
        assert mine, f"{fname}: 分片未进索引进（work={work}）"
        assert all(c["text"].strip() for c in mine), f"{fname}: 存在空分片"
        ids = [c["id"] for c in mine]
        assert len(set(ids)) == len(ids), f"{fname}: 分片 id 重复"


def test_d126_extensions_wired():
    all_works = {w for s in EXPECTED.values() for w in s}
    assert len(all_works) == 12
    for sid, works in EXPECTED.items():
        items = extensions_for(sid)
        local = {i.get("local_work") for i in items if i.get("local_work")}
        missing = works - local
        assert not missing, f"{sid}: 缺延伸阅读挂接 {sorted(missing)}"
        for i in items:
            if i.get("local_work") in all_works:
                assert i["kind"] == "classic", \
                    f"{sid}/《{i['title']}》: kind 应为 classic，实际「{i['kind']}」"
                assert i.get("points"), f"{sid}/《{i['title']}》: 缺要点"
                assert "一字未改" in i.get("caution", ""), \
                    f"{sid}/《{i['title']}》: caution 须写明「一字未改」"
                m = DISPLAY_JARGON.search(i.get("caution", ""))
                assert not m, f"{sid}/《{i['title']}》: caution 出现开发期术语「{m.group(0)}」"
    wired = {i.get("local_work") for sid in EXPECTED for i in extensions_for(sid)}
    assert all_works <= wired, f"未挂接：{sorted(all_works - wired)}"


def test_d126_sections_still_32():
    from content.routes import SECTIONS
    assert len(SECTIONS) == 32
    ids = {s["id"] for s in SECTIONS}
    assert set(EXPECTED) <= ids, f"挂接到了不存在的章节：{sorted(set(EXPECTED) - ids)}"


def test_d126_rebuild_matches_library():
    """从源页重新拼接必须与库内正文逐字相同（本批篇内一律不裁）。"""
    import importlib.util

    mp = Path(__file__).resolve().parents[2] / "scripts" / "import_mirror.py"
    spec = importlib.util.spec_from_file_location("import_mirror_d126", mp)
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


def test_d126_no_piece_is_trimmed():
    """本批十二篇一律不裁：源规格里不得出现在裁剪表内。"""
    import importlib.util

    mp = Path(__file__).resolve().parents[2] / "scripts" / "import_mirror.py"
    spec = importlib.util.spec_from_file_location("import_mirror_d126b", mp)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)

    trimmed = sorted(f for f in WORKS if f in mod.TRIM)
    assert trimmed == [], f"本批不应有任何裁剪，实际 {trimmed}"


@pytest.mark.parametrize("fname", sorted(EDITOR_CUT))
def test_d126_editorial_cut_note_kept(fname):
    """选集编辑留下的删节／摘要题注必须原样在正文里——删节不是本库所为，不能抹掉。"""
    t = (TEXTS / fname).read_text(encoding="utf-8")
    note = EDITOR_CUT[fname]
    assert note in t, f"{fname}: 题注「{note}」缺失，删节由来被抹掉了"
    assert "＊" in t, f"{fname}: 题注行应以「＊」起首"


def test_d126_quotes_verbatim():
    """延伸阅读里「」内的文字必须逐字出现在该条目自己的正文中。"""
    works = {w for s in EXPECTED.values() for w in s}
    fmap = {b["work"]: b["file"] for b in BOOKS}
    checked = 0
    for sid in EXPECTED:
        for it in extensions_for(sid):
            w = it.get("local_work")
            if w not in works:
                continue
            t = (TEXTS / fmap[w]).read_text(encoding="utf-8")
            t = re.sub(r"[〔\[]\d+[〕\]]", "", t)
            t = re.sub(r"\s+", "", t)
            for q in re.findall(r"「([^」]*)」", "".join(it["points"]) + it["intro"] + it["how_to_use"]):
                qq = re.sub(r"[〔\[]\d+[〕\]]", "", q)
                qq = re.sub(r"\s+", "", qq)
                checked += 1
                assert qq in t, f"{sid}/《{it['title']}》: 引文不逐字「{q}」"
    assert checked >= 30, f"逐字核对样本过少：{checked}"


def test_d126_zhouenlai_corpus_27():
    """周恩来在库内应为 27 篇（原 15 + 本批 12）。"""
    mine = [b for b in BOOKS if b["author"] == "周恩来"]
    assert len(mine) == 27, f"周恩来篇目应为 27，实际 {len(mine)}"
    files = {b["file"] for b in mine}
    assert set(WORKS) <= files, f"本批未全部进库：{sorted(set(WORKS) - files)}"


def test_d126_duplicates_free():
    """与既有延伸阅读条目、既有书目零重复。"""
    works = {w for s in EXPECTED.values() for w in s}
    titles = []
    for items in extensions_for.__globals__["READING_EXTENSIONS"].values():
        for it in items:
            if it.get("local_work") in works:
                titles.append(it["title"])
    assert len(titles) == len(set(titles)) == 12, f"挂接条目应为 12 条且标题唯一：{len(titles)}"


def test_d126_no_critical_material():
    """红线：本批不得出现批判位／争议分档，也不得混入黑名单一类材料。"""
    mine = [b for b in BOOKS if b["file"] in WORKS]
    for b in mine:
        assert b["orthodoxy_tag"] in {"经典原著", "正统"}, f"{b['file']}: 分档越界「{b['orthodoxy_tag']}」"
        assert b["author"] == "周恩来", f"{b['file']}: 作者应为周恩来"
