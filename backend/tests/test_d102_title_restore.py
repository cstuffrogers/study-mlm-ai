"""D102：早期 5 部多文件著作章节标题行修复 的门禁测试

对应 `sources/texts/SOURCE_MANIFEST.md` 附录四。核心事实：
  * 早期 22 部里有 5 部多文件拼接著作，因 html_to_lines() 的 strip_title_repeat
    误删了后续分文件的可见首行——共 36 个**合法独立章节标题行**，逐行复核均为
    非导航、非重复输出的真实标题（正文内容本来就在，只是没有篇章锚点）。
  * 修复方式：给这 5 部 SPECS 加 keep_titles=True，脚本化补回；原文一字未改。
  * 可回退：sources/_backup_d102_pretitle/ 保存修复前 5 部全文；
    `build(spec, keep_titles=False)` 逐字节等于备份；`--no-keep-titles` 可复现。
  * 分片数 / id 完全不变（text_loader 把短标题行作为 chapter_hint 剔除、不入正文段落），
    但分片的 source_location 章名归属得到修正。
"""
from __future__ import annotations

from pathlib import Path

from content.book_chunks import BOOKS, all_book_chunks
from content.routes import SECTIONS

TEXTS = Path(__file__).resolve().parents[2] / "sources" / "texts"
BACKUP = Path(__file__).resolve().parents[2] / "sources" / "_backup_d102_pretitle"

# D102 修复的 5 部（都不在 D101 裁剪 9 部内）
D102_FILES = (
    "3-唯物主义和经验批判主义.txt",
    "4-资本论第二卷.txt",
    "4-资本论第三卷.txt",
    "3-论一元论历史观的发展.txt",
    "3-思想起源论.txt",
)

# 逐部锁死补回的标题行（合计 36 个），尤其是《书籍.md》明文点名的重点篇。
D102_TITLES = {
    "3-唯物主义和经验批判主义.txt": (
        "第一章 经验批判主义的认识论和辩证唯物主义的认识论（一）",
        "第二章 经验批判主义的认识论和辩证唯物主义的认识论（二）",
        "第三章 辩证唯物主义的认识论和经验批判主义的认识论（三）",
        "第四章 作为经验批判主义的战友和继承者的哲学唯心主义者",
        "第五章 最近的自然科学革命和哲学唯心主义",
        "第六章 经验批判主义和历史唯物主义",
        "第四章第1节的补充",
    ),
    "4-资本论第二卷.txt": (
        "[第二版序言]",
        "第一篇 资本形态变化及其循环",  # 书籍.md 第 4 阶段明文重点篇
        "第二章 生产资本的循环",
        "第三章 商品资本的循环",
        "第四章 循环过程的三个公式",
        "第六章 流通费用",
        "第二篇 资本周转",
        "第八章 固定资本和流动资本",
        "第十五章 周转时间对预付资本量的影响",
        "第三篇 社会总资本的再生产和流通",
        "第十九章 前人对这个问题的阐述",
        "第二十章 简单再生产",
        "第二十一章 积累和扩大再生产",
    ),
    "4-资本论第三卷.txt": (
        "第二章 利润率",
        "第三章 利润率和剩余价值率的关系",
        "第四章 周转对利润率的影响",
        "第九章 一般利润率（平均利润率）的形成和商品价值转化为生产价格",
        "第三十六章 资本主义以前的状态",
        "第三十八章 级差地租：概论",
        "第三十九章 级差地租的第一形式（级差地租I）",
        "第四十四章 最坏耕地也有级差地租",
        "第四十五章 绝对地租",
        "第四十六章 建筑地段的地租。矿山地租。土地价格",
        "第四十七章 资本主义地租的产生",
    ),
    "3-论一元论历史观的发展.txt": (
        "第一章 十八世纪法国唯物主义",
        "第五章 现代唯物主义",
    ),
    "3-思想起源论.txt": (
        "卡尔·马克思的历史方法",
        "抽象思想的起源",
        "正义思想的起源",
    ),
}


def _load_import_module():
    import importlib.util
    p = Path(__file__).resolve().parents[2] / "scripts" / "import_mirror.py"
    spec = importlib.util.spec_from_file_location("import_mirror_d102", p)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


def test_d102_config_and_backup_well_formed():
    """5 部均标记 keep_titles=True；备份恰好是这 5 部；36 个标题行配置齐备。

    并锁死 `--no-keep-titles` 只作用于 D102 这 5 部：D100 那 3 部
    （哲学的贫困/两种策略/宁肯少些但要好些）自建库起就带 keep_titles=True，
    且 TRIM 边界依赖其标题行，不能被该开关剥掉（曾因此触发整库 dry-run 失败）。
    """
    mod = _load_import_module()
    specs = {s["file"]: s for s in mod.SPECS}
    assert set(D102_FILES) <= set(specs)
    assert all(specs[f].get("keep_titles") is True for f in D102_FILES)
    assert {p.name for p in BACKUP.glob("*.txt")} == set(D102_FILES)
    assert sum(len(v) for v in D102_TITLES.values()) == 36
    # 这 5 部不能同时是 D101 裁剪对象（互不干扰）
    assert not set(D102_FILES) & set(mod.TRIM)
    # 全局开关的作用域必须精确等于 D102 5 部
    assert set(mod.D102_TITLE_FILES) == set(D102_FILES)
    d100_keep = {"0-哲学的贫困.txt", "1-两种策略.txt", "5-宁肯少些但要好些.txt"}
    # 其中前 2 部同时是 D101 裁剪对象、TRIM 边界依赖标题行；第 3 部只保留标题行、不裁剪。
    assert {"0-哲学的贫困.txt", "1-两种策略.txt"} <= set(mod.TRIM)
    assert "5-宁肯少些但要好些.txt" not in mod.TRIM
    assert all(specs[f].get("keep_titles") is True for f in d100_keep)
    # 即使 keep_titles=False，D100 3 部仍须能正常 build + 命中 TRIM marker
    for f in d100_keep:
        s = specs[f]
        text, _ = mod.build(s, trim=True, keep_titles=False)
        assert text == (TEXTS / f).read_text(encoding="utf-8"), \
            f"{f} 被 --no-keep-titles 误改（D100 标题行必须保留）"


def test_d102_all_36_titles_restored():
    """36 个标题行作为独立行全部存在；修复前备份里独立行 0 命中。"""
    for f, titles in D102_TITLES.items():
        cur = {x.strip() for x in (TEXTS / f).read_text(encoding="utf-8").splitlines()}
        old = {x.strip() for x in (BACKUP / f).read_text(encoding="utf-8").splitlines()}
        for t in titles:
            assert t in cur, f"{f} 修复后缺标题行: {t}"
            assert t not in old, f"{f} 备份里已存在该标题行（修复无意义？）: {t}"
        assert (TEXTS / f).read_text(encoding="utf-8").count("\n\n\n\n") == 0, \
            f"{f} 段落结构被破坏（连续空行）"


def test_d102_reproducible_and_original_text_untouched():
    """keep_titles=False 逐字节复现备份；keep_titles=True 只新增标题行、正文逐行不变。"""
    mod = _load_import_module()
    specs = {s["file"]: s for s in mod.SPECS}
    for f in D102_FILES:
        s = specs[f]
        backup = (BACKUP / f).read_text(encoding="utf-8")
        before, _ = mod.build(s, trim=True, keep_titles=False)
        after, _ = mod.build(s, trim=True, keep_titles=True)
        assert before == backup, f"{f} 无法逐字节复现修复前产物"
        assert after == (TEXTS / f).read_text(encoding="utf-8"), f"{f} 现库与脚本产物不一致"
        # 修复后删去新增行，正文必须与修复前逐行一致
        nl, ol = after.splitlines(), before.splitlines()
        i = j = 0
        added = 0
        kept = []
        while i < len(ol) and j < len(nl):
            if ol[i] == nl[j]:
                kept.append(nl[j]); i += 1; j += 1
            else:
                added += 1; j += 1
        kept += nl[j:]
        assert i == len(ol), f"{f} 修复后丢失了原有正文行"
        assert kept == ol, f"{f} 正文被改写（不只是插入标题行）"
        assert added == 2 * len(D102_TITLES[f]), \
            f"{f} 新增行数异常：标题行+分隔空行应各 {len(D102_TITLES[f])} 行"


def test_d102_chunk_ids_unchanged_and_locations_improved():
    """分片数/id 不变；章名归属从空白变成真实章名。"""
    chunks = all_book_chunks()
    ids = [c["id"] for c in chunks]
    assert len(ids) == len(set(ids))
    assert len(chunks) == 23041  # 2026-11 分片器加入 60 字下限合并（原 28660；短分片 20%→0.3%，检索指标不变）；此前： …D124 +342（克鲁普斯卡娅 10 篇）；D125 +776（按章节缺口补 13 篇）；D126 +277（周恩来民主革命期 12 篇）；D127 +2142（考茨基 4 篇）
    assert len(BOOKS) == 229
    assert len(SECTIONS) == 32
    wp = [c for c in chunks if c["id"].startswith("CH-WP-")]
    # 《唯批》修复前 chapter_hint 为 0，修复后大量分片带真实章名
    named = sum(1 for c in wp if "第一章" in c["source_location"]
                or "第六章" in c["source_location"])
    assert named > 100, f"《唯批》章名归属未生效: {named}"
    # 《资本论》第三卷明文重点章可作为定位锚点
    assert any("第三十六章 资本主义以前的状态" in c["source_location"]
               for c in chunks if c["id"].startswith("CH-ZBL3-"))


def test_d102_other_specs_and_capital_postface_unchanged():
    """其余 38 部逐字节不受影响；《资本论》第一卷第二版跋仍只出现 1 次。"""
    mod = _load_import_module()
    for s in mod.SPECS:
        if s["file"] in D102_FILES:
            continue
        text, _ = mod.build(s, trim=True, keep_titles=True)
        assert text == (TEXTS / s["file"]).read_text(encoding="utf-8"), \
            f"非修复对象被改动: {s['file']}"
    cap = (TEXTS / "0-资本论节选.txt").read_text(encoding="utf-8")
    assert cap.count("\n第二版跋\n") == 1
