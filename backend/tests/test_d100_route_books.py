"""D100：设计文档点名欠账 + 三路线谱系补环 的门禁测试

对应 `.local/route_books_audit.md`。核心红线：
  1) 只补**可靠著作**：每条 classic/historical 若挂 `local_work`，必须指向真实入库正文；
     导读型必须带 caution 且不得带外链；
  2) **不新开章节**（32 章不变），不改动既有章节主文与既有 22 部正文；
  3) 版本/节选事实必须如实声明：合编、抽出成篇、合著、决议第一部分、卷本、非官方版本降档；
  4) 红线项不得因「补书」被放进正面路径：批判对象 7 本、托洛茨基系列、非官方拼接版。
"""
from __future__ import annotations

from pathlib import Path

from content.book_chunks import BOOKS, available_works
from content.reading_extensions import READING_EXTENSIONS, KIND_LABEL
from content.reading_extensions_d100 import D100_EXTENSIONS
from content.routes import SECTIONS

TEXTS = Path(__file__).resolve().parents[2] / "sources" / "texts"

# P0：设计文档点名但 D99 源表未落地的 5 部（+《资本论》节选缺篇）
P0_WORKS = (
    "我的修养要则",
    "加强调查研究",
    "关于党的“六大”的研究",
    "说真话，鼓真劲，做实事，收实效",
    "论联合政府",
)

# P1：三路线谱系补环（按路线分组，防止只补某一条路线）
P1_BY_ROUTE = {
    "sec_A_": ("《黑格尔法哲学批判》导言", "哲学的贫困", "社会主义从空想到科学的发展"),
    "sec_B_": ("进一步，退两步", "社会民主党在民主革命中的两种策略",
             "无产阶级革命和叛徒考茨基", "《共产党人》发刊词", "中国革命和中国共产党",
             "论持久战", "关于纠正党内的错误思想", "党委会的工作方法",
             "论列宁主义的几个问题"),
    # 七届二中全会报告是「革命→建设」的接口，按设计挂在 sec_C_02（非 B 路线）。
    "sec_C_": ("论粮食税", "论合作社", "宁肯少些，但要好些", "论联合政府",
             "在中国共产党第七届中央委员会第二次全体会议上的报告"),
}

_ALL_WORKS = set(available_works())


def test_d100_chapters_unchanged():
    """补书不膨胀章节：仍是 32 章，章节 id 与原主文一一对应。"""
    assert len(SECTIONS) == 32
    assert len({s["id"] for s in SECTIONS}) == 32
    assert {s["id"] for s in SECTIONS if s["route_id"] == "route_A"}
    assert {s["id"] for s in SECTIONS if s["route_id"] == "route_B"}
    assert {s["id"] for s in SECTIONS if s["route_id"] == "route_C"}


def test_d100_p0_pointed_by_design_docs_now_landed():
    """P0 五部现在既要入正文，也要在学习路径上可抵达。"""
    for w in P0_WORKS:
        assert w in _ALL_WORKS, f"P0 未入库正文: {w}"
        assert any(
            it.get("local_work") == w or w in it["title"]
            for items in READING_EXTENSIONS.values() for it in items
        ), f"P0 在学习路径上不可抵达: {w}"


def test_d100_capital_second_edition_postface_appended():
    """《资本论》第一卷节选补入「第二版跋」，且不重复追加、既有正文一字未动。"""
    text = (TEXTS / "0-资本论节选.txt").read_text(encoding="utf-8")
    assert text.count("\n第二版跋\n") == 1, "第二版跋应恰好补入一次（脚本须幂等）"
    # 跋的核心段落：与黑格尔辩证法划清界限
    assert "合理形态" in text and "移入人的头脑" in text
    # 既有节选首章与第二十四章仍在（追加不覆盖）
    assert "商品的两个因素" in text
    assert "资本主义私有制的丧钟就要" in text
    assert "剥夺者就要被剥夺了" in text


def test_d100_p1_genealogy_by_route():
    """三条路线都要补到谱系缺环，尤其 C 路线原本整段缺席的列宁建设探索。"""
    for prefix, works in P1_BY_ROUTE.items():
        landed = {
            it.get("local_work")
            for sid, items in READING_EXTENSIONS.items()
            if sid.startswith(prefix) for it in items
        }
        for w in works:
            assert w in _ALL_WORKS, f"{prefix} 谱系著作未入库正文: {w}"
            assert w in landed, f"{prefix} 谱系著作未挂到该路线章节: {w}"


def test_d100_extension_entries_well_formed():
    """D100 条目结构合法：字段齐、kind 合法、local_work 真实、导读型无外链。"""
    assert D100_EXTENSIONS, "D100 表不应为空"
    for sid, items in D100_EXTENSIONS.items():
        assert sid in {s["id"] for s in SECTIONS}, f"挂到不存在的章节: {sid}"
        seen: set[str] = set()
        for it in items:
            assert it["title"] not in seen, f"{sid} 重复条目"
            seen.add(it["title"])
            for key in ("title", "author", "kind", "intro", "points", "how_to_use", "caution"):
                assert it.get(key), f"{sid}/{it['title']} 缺字段 {key}"
            assert it["kind"] in KIND_LABEL, f"{sid}/{it['title']} kind 非法"
            local = it.get("local_work")
            if local:
                assert local in _ALL_WORKS, f"{sid}/{it['title']} local_work 未入库: {local}"
            else:
                assert not it.get("link"), f"{sid}/{it['title']} 导读型不得带外链"


def test_d100_version_and_excerpt_declarations():
    """版本/节选事实必须如实声明——不把近似材料冒充全文。"""
    def caution_of(keyword: str) -> str:
        hits = [
            it["caution"]
            for items in READING_EXTENSIONS.values() for it in items
            if keyword in it["title"]
        ]
        assert hits, f"找不到条目: {keyword}"
        return "\n".join(hits)

    assert "两则合编" in caution_of("《加强调查研究》")  # 实为两则、各带题解
    assert "抽出成篇" in caution_of("说真话，鼓真劲")     # 长篇讲话抽出的节选
    assert "合著" in caution_of("中国革命和中国共产党")     # 第一章他人起草
    assert "决议的第一部分" in caution_of("关于纠正党内的错误思想")  # 古田会议决议
    assert "结论的一部分" in caution_of("党委会的工作方法")   # 七届二中全会结论
    assert "毛选版" in caution_of("论联合政府")             # 排除未删改原始版
    assert "中文第 1 版第 23 卷" in caution_of("第二版跋")  # 与节选同版，不混版
    assert "图像版" in caution_of("唯物主义史论丛")         # 镜像无可靠全文，保留导读


def test_d100_unofficial_text_downgraded_to_historical():
    """1968《毛泽东思想万岁》版『读苏联教科书谈话』须降为历史文本·须对照批判。"""
    hits = [
        it for items in READING_EXTENSIONS.values() for it in items
        if "读苏联〈政治经济学教科书〉的谈话" in it["title"]
    ]
    assert hits, "原条目应保留（不得删除，只能降档）"
    assert all(it["kind"] == "historical" for it in hits)
    assert all("1968" in it["caution"] for it in hits)


def test_d100_redlines_not_turned_into_positive_readings():
    """红线项不得借『补书』进入正面路径（classic / local_work）。"""
    banned = (
        "伯恩斯坦", "卢卡奇", "葛兰西", "阿尔都塞", "托洛茨基", "哈耶克", "波普尔",
        "哈维", "齐泽克", "萨特", "韦伯", "光辉道路", "全面复辟", "社会帝国主义",
        "未删改原始版", "润之赤旗", "毛泽东思想万岁",
    )
    for sid, items in READING_EXTENSIONS.items():
        for it in items:
            blob = it["title"] + it.get("author", "") + it.get("intro", "")
            if it["kind"] == "classic" and it.get("local_work"):
                for word in banned:
                    assert word not in blob, f"红线词进入正面经典: {sid}/{it['title']} → {word}"


def test_d100_book_registration_unique_and_files_exist():
    """BOOKS 登记唯一、文件齐备、分片 id 全局唯一。

    著作数随批次递增：D87 建库 → … → D105 = 121 → **D107 = 122**
    （D107 补入《关于费尔巴哈的提纲》，修复 sec_A_02 长期无原文的问题）
    → **D116 = 127**（组织领导／群众路线谱系补环：3 篇毛泽东短篇 + 2 篇刘少奇节选）
    → **D117 = 129**（工人运动谱系补环：邓中夏《中国职工运动简史》节选 + 刘少奇 1926 年报告）
    → **D118 = 137**（建党前史 1918—1926：李大钊 6 篇 + 蔡和森 2 篇，全文照录）
    → **D119 = 147**（建党文献原文 1920—1925：《中共中央文件选集》第一册 10 篇，全文照录）
    → **D120 = 153**（周恩来建国后文献 1951—1963：6 篇，全文照录）
    → **D121 = 155**（普列汉诺夫前期哲学著作 2 篇：1898《个人在历史上的作用问题》、
    1895《奥古斯丹·梯叶里和唯物史观》，全文照录）
    → **D122 = 168**（妇女运动文献 13 篇：向警予 8 篇 + 党的三大／四大妇女决议
    2 篇 + 蔡特金 3 篇，全文照录）
    → **D123 = 190**（恽代英文献 22 篇：理论著作与讲演 12 篇 + 工运与苏维埃史料
    10 篇；两篇长篇按讲次／小节标题行裁为节选，其余全文照录）
    → **D124 = 200**（克鲁普斯卡娅「列宁怎样读书、研究、宣传」10 篇：整本
    《列宁是怎样写作学习的》按篇节选 7 篇 + 《论列宁》单篇 3 篇；篇内全文照录，
    节选只在「篇」这一级——本批无篇内裁剪，故不进 TRIM 表）。
    → **D125 = 213**（按九个章节的内容缺口补 13 篇：列宁 1917 年夺权三篇、
    马克思《论犹太人问题》、李大钊四篇、周恩来两篇、毛泽东宪法草案讲话、
    邓中夏《我们的力量》；《卡尔·马克思》只按小节标题取哲学部分）。
    → **D126 = 225**（周恩来民主革命期 12 篇，按六章内容缺口选：九月来信、
    肃清非无产阶级意识、全国大反攻、和平谈判、论中国的法西斯主义、现时政治
    斗争中之我们、党对国民党的关系、一年来的谈判及前途、老区半老区土改与
    整党、共同纲领特点、恢复生产、新民主主义的经济建设；全部全文照录）。
    → **D127 = 229**（考茨基 4 篇：1887《马克思的经济学说》全书照录，
    1892《爱尔福特纲领解说》/ 1898《土地问题》/ 1908《基督教之基础》按篇／章
    标题行裁为节选；四部一律记「正统／0.9」，不记经典原著）。
    """
    for key in ("file", "work", "id_prefix", "slug"):
        vals = [b[key] for b in BOOKS]
        assert len(vals) == len(set(vals)), f"BOOKS.{key} 有重复"
    for b in BOOKS:
        assert (TEXTS / b["file"]).exists(), f"正文文件缺失: {b['file']}"
    assert len(BOOKS) == len(_ALL_WORKS) == 229


# ============================================================================
# D101：方案 1「不是要原著的所有内容，符合要求的章节就保留」
# 9 部长篇按 TRIM 裁为章节节选；原文一字未改、边界均为章节标题行。
# ============================================================================
D101_TRIMMED = (
    "0-哲学的贫困.txt",
    "1-两种策略.txt",
    "5-中国革命和中国共产党.txt",
    "5-论联合政府.txt",
    "5-论持久战.txt",
    "0-社会主义从空想到科学的发展.txt",
    "1-进一步退两步.txt",
    "1-无产阶级革命和叛徒考茨基.txt",
    "5-论列宁主义的几个问题.txt",
)

# D103：同一机制（TRIM）用于「按合适章节节选」的 15 部新书（毛 8 / 列 2 / 斯 3 / 马 1 / 恩 1）。
# 《论国家》整页照录（无 TRIM），故不在本表内。
D103_TRIMMED = (
    "5-中国革命战争的战略问题.txt",
    "5-抗日游击战争的战略问题.txt",
    "5-战争和战略问题.txt",
    "5-井冈山的斗争.txt",
    "5-中国的红色政权为什么能够存在.txt",
    "5-论反对日本帝国主义的策略.txt",
    "5-学习和时局.txt",
    "5-在省市自治区党委书记会议上的讲话.txt",
    "1-评经济浪漫主义.txt",
    "1-马克思主义和语言学问题.txt",
    "1-马克思主义和民族问题.txt",
    "2-无政府主义还是社会主义.txt",
    "2-1848年至1850年的法兰西阶级斗争.txt",
    "2-德国农民战争.txt",
)

# D104：同一机制用于军事 / 过渡时期政治 / 经济政策 / 文化四块的 26 部
# （其中只有 3 部需按章节节选，其余为单篇全文，故不在本表内）。
D104_TRIMMED = (
    "1-大难临头出路何在.txt",
    "3-反杜林论政治经济学篇.txt",
    "3-自然辩证法辩证法作为科学.txt",
)

# D105：只删镜像页面沿页重复的卷名页头行（不删章节，故不开 segment 切区间）
D105_TRIMMED = ("4-剩余价值理论节选.txt",)

# D116：5 部均为「按章节标题行切区间」的真节选（3 篇毛短篇裁卷末注释，
# 2 篇刘少奇按小节保留）；裁剪前全文备份在 sources/_backup_d116_pretrim/。
D116_TRIMMED = (
    "5-关心群众生活注意工作方法.txt",
    "5-农村调查的序言和跋.txt",
    "5-组织起来.txt",
    "1-关于白区的党和群众工作.txt",
    "1-怎样进行群众工作.txt",
)

# D117：邓中夏《中国职工运动简史》按章节选（13 页拼接后只留著者申明 + 第五、七、九章），
# 裁剪前全文备份在 sources/_backup_d117_pretrim/；刘少奇 1926 年报告为全文照录，不在本表。
D117_TRIMMED = ("1-中国职工运动简史节选.txt",)
# D123：恽代英两篇长篇按讲次／小节标题行节选（其余 20 篇全文照录，不在此表）
D123_TRIMMED = (
    "1-中国民族革命运动史节选.txt",
    "1-答醒狮周报三十二期的质难节选.txt",
)
# D125：只有《卡尔·马克思》按小节标题取哲学部分（其余 12 篇全文照录，不在此表）
D125_TRIMMED = ("1-卡尔马克思传略和马克思主义概述节选.txt",)
# D127：考茨基 3 部长篇按篇／章标题行节选（1887《马克思的经济学说》篇幅较小、
# 全书照录，故不在本表）；裁剪前全文备份在 sources/_backup_d127_pretrim/。
D127_TRIMMED = (
    "1-爱尔福特纲领解说节选.txt",
    "1-土地问题节选.txt",
    "1-基督教之基础节选.txt",
)

# 每部必须保留的关键章节/概念；必须已删去的不相干细部
D101_KEEP = {
    "0-哲学的贫困.txt": ("第一章 科学的发现", "第一节 使用价值和交换价值的对立",
                       "第二章 政治经济学的形而上学", "第一节 方法"),
    "1-两种策略.txt": ("10．“革命公社”与无产阶级和农民的革命民主专政",
                     "13．结论。我们敢不敢胜利？", "革命民主专政"),
    "5-中国革命和中国共产党.txt": ("第三节 现代的殖民地、半殖民地和半封建社会",
                             "第二章 中国革命", "第五节 中国革命的性质", "第六节 中国革命的前途"),
    "5-论联合政府.txt": ("一 中国人民的基本要求", "四 中国共产党的政策",
                     "我们的一般纲领", "我们的具体纲领", "五 全党团结起来"),
    "5-论持久战.txt": ("问题的提起", "问题的根据", "持久战的三个阶段",
                    "亡国论是不对的，速胜论也是不对的", "能动性在战争中",
                    "兵民是胜利之本", "结 论"),
    "0-社会主义从空想到科学的发展.txt": ("马克思写的1880年法文版前言 〔253〕",
                                 "唯物主义历史观", "一", "二", "三"),
    "1-进一步退两步.txt": ("序言", "（七）党章。马尔托夫同志的草案",
                       "（九）党章第1条", "（十八）稍微谈谈辩证法。两个变革", "组织"),
    "1-无产阶级革命和叛徒考茨基.txt": ("考茨基怎样把马克思变成了庸俗的自由主义者",
                               "资产阶级民主和无产阶级民主", "苏维埃不得变成国家组织", "无产阶级专政"),
    "5-论列宁主义的几个问题.txt": ("六 关于社会主义在一个国家内胜利的问题",
                            "七 为社会主义建设的胜利而奋斗", "社会主义可能首先在少数"),
}
D101_DROP = {
    "0-哲学的贫困.txt": ("第二节 构成价值或综合价值", "第五节 罢工和工人同盟"),
    "1-两种策略.txt": ("9．什么是在革命时期做一个持极端反对派态度的政党？",
                     "补充说明再论解放派，再论新火星派"),
    "5-中国革命和中国共产党.txt": ("第一节 中华民族", "第二节 古代的封建社会"),
    "5-论联合政府.txt": ("二 国际形势和国内形势", "三 抗日战争中的两条路线", "第一 彻底消灭日本侵略者"),
    "5-论持久战.txt": ("驳亡国论", "犬牙交错的战争", "运动战，游击战，阵地战", "注释"),
    "0-社会主义从空想到科学的发展.txt": ("1882年德文第一版序言 〔257〕", "1892年英文版导言 〔260〕"),
    "1-进一步退两步.txt": ("（一）代表大会的准备", "（十三）选举。代表大会的结束", "附录"),
    "1-无产阶级革命和叛徒考茨基.txt": ("立宪会议和苏维埃共和国", "附录一", "附录二"),
    "5-论列宁主义的几个问题.txt": ("一 列宁主义的定义", "五 无产阶级专政体系中的党和工人阶级"),
}


def _load_import_module():
    """以文件路径加载 scripts/import_mirror.py（不是包，避免污染 sys.path 命名）。"""
    import importlib.util
    p = Path(__file__).resolve().parents[2] / "scripts" / "import_mirror.py"
    spec = importlib.util.spec_from_file_location("import_mirror_d101", p)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


def test_d101_trim_config_well_formed():
    """TRIM 恰好 9 部；每段区间合法、marker 唯一命中、边界在章节标题行。

    注意：marker 必须相对**裁剪前全文**（备份）校验；裁剪后文件里已无这些边界标题。
    """
    mod = _load_import_module()
    assert set(mod.TRIM) == (set(D101_TRIMMED) | set(D103_TRIMMED)
                             | set(D104_TRIMMED) | set(D105_TRIMMED)
                             | set(D116_TRIMMED) | set(D117_TRIMMED)
                             | set(D123_TRIMMED) | set(D125_TRIMMED)
                             | set(D127_TRIMMED))
    root = Path(__file__).resolve().parents[2] / "sources"
    backups = {f: root / "_backup_d101_pretrim" for f in D101_TRIMMED}
    backups.update({f: root / "_backup_d103_pretrim" for f in D103_TRIMMED})
    backups.update({f: root / "_backup_d104_pretrim" for f in D104_TRIMMED})
    backups.update({f: root / "_backup_d105_pretrim" for f in D105_TRIMMED})
    backups.update({f: root / "_backup_d116_pretrim" for f in D116_TRIMMED})
    backups.update({f: root / "_backup_d117_pretrim" for f in D117_TRIMMED})
    backups.update({f: root / "_backup_d123_pretrim" for f in D123_TRIMMED})
    backups.update({f: root / "_backup_d125_pretrim" for f in D125_TRIMMED})
    backups.update({f: root / "_backup_d127_pretrim" for f in D127_TRIMMED})
    for f, cfg in mod.TRIM.items():
        assert cfg["desc"], f"{f} 缺 desc"
        lines = (backups[f] / f).read_text(encoding="utf-8").splitlines()
        stripped = [x.strip() for x in lines]
        prev = 0
        for start, sn, end, en in cfg["segments"]:
            i = mod._nth_line(stripped, start, sn, f)
            j = len(lines) if end is None else mod._nth_line(stripped, end, en, f)
            assert i >= prev and j > i, f"{f} 区间倒序/重叠 L{i}..L{j}"
            assert lines[i].strip(), f"{f} start 不是章节标题行"
            assert end is None or lines[j].strip(), f"{f} end 不是章节标题行"
            prev = j


def test_d101_trim_reproduces_current_texts():
    """从备份全文按 TRIM 重切，必须与现库逐字节一致（原文一字未改、可复现）。"""
    mod = _load_import_module()
    backup = Path(__file__).resolve().parents[2] / "sources" / "_backup_d101_pretrim"
    assert {p.name for p in backup.glob("*.txt")} == set(D101_TRIMMED), \
        "备份应且只应含 9 部裁剪前全文"
    for f in D101_TRIMMED:
        full = (backup / f).read_text(encoding="utf-8")
        cur = (TEXTS / f).read_text(encoding="utf-8")
        assert len(cur) < len(full), f"{f} 未裁剪"
        assert 0.15 < len(cur) / len(full) < 0.80, \
            f"{f} 裁剪比例异常: {len(cur)/len(full):.2%}"
        assert mod.apply_trim(f, full) == cur, f"{f} 裁剪结果不可复现（原文被改写？）"
    # 其余著作不属于本轮裁剪范围，且文件齐备
    from content.book_chunks import BOOKS as _BOOKS
    assert len(_BOOKS) == 229
    assert all((TEXTS / b["file"]).exists() for b in _BOOKS)


def test_d101_kept_and_dropped_sections():
    """保留章节必须在、裁去的细部必须不在（原文一字未改，仅整章删除）。"""
    for f, kws in D101_KEEP.items():
        t = (TEXTS / f).read_text(encoding="utf-8")
        for k in kws:
            assert k in t, f"{f} 误删关键章节: {k}"
        assert "\n\n\n\n" not in t, f"{f} 段落结构被破坏（连续空行）"
    for f, kws in D101_DROP.items():
        # 按「独立章节标题行」判断：正文里正常提及这些词不算残留（如目录、行文举例）。
        lines = [x.strip() for x in (TEXTS / f).read_text(encoding="utf-8").splitlines()]
        for k in kws:
            assert k not in lines, f"{f} 仍残留应裁章节标题: {k}"


def test_d101_cautions_declare_excerpt():
    """9 部对应的延伸阅读 caution 必须声明「节选」，不得再声称全文。"""
    hit = {}
    for items in D100_EXTENSIONS.values():
        for it in items:
            hit[it["title"]] = it
    mapping = {
        "《哲学的贫困》（1847）": "0-哲学的贫困.txt",
        "《社会主义从空想到科学的发展》（1880）": "0-社会主义从空想到科学的发展.txt",
        "《进一步，退两步》（1904）": "1-进一步退两步.txt",
        "《论列宁主义的几个问题》（1926）": "5-论列宁主义的几个问题.txt",
        "《无产阶级革命和叛徒考茨基》（1918）": "1-无产阶级革命和叛徒考茨基.txt",
        "《社会民主党在民主革命中的两种策略》（1905）": "1-两种策略.txt",
        "《论持久战》（1938）": "5-论持久战.txt",
        "《中国革命和中国共产党》（1939）": "5-中国革命和中国共产党.txt",
        "《论联合政府》（1945）": "5-论联合政府.txt",
    }
    assert len(mapping) == len(D101_TRIMMED)
    for title, f in mapping.items():
        assert title in hit, f"缺延伸阅读条目: {title}"
        c = hit[title].get("caution", "")
        assert "节选" in c, f"{title} caution 未声明节选"
        # 读者向文案：不暴露 D101 / TRIM 等开发标记，只声明节选范围
        assert "D101" not in c and "TRIM" not in c, f"{title} caution 暴露了开发标记: {c[:60]}"
        assert "一字未改" in c, f"{title} caution 未声明原文一字未改"
        assert "全文" not in c.replace("全文备份", "").replace("全文（", "") or "裁为节选" in c, \
            f"{title} caution 仍可能声称全文: {c[:80]}"


def test_d101_book_registration_and_chunk_ids_still_valid():
    """裁剪不改著作数/前缀，分片 id 仍全局唯一。"""
    from content.book_chunks import all_book_chunks
    chunks = all_book_chunks()
    ids = [c["id"] for c in chunks]
    assert len(ids) == len(set(ids))
    assert len(BOOKS) == len(_ALL_WORKS) == 229
    assert len(SECTIONS) == 32

# 依赖 sources/texts/ 原著正文；无正文时由 conftest.py 自动跳过。
import pytest

pytestmark = pytest.mark.needs_texts
