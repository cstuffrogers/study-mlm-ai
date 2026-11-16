"""原著正文分片回归：sources/texts 已入库正文应生成真实分片并进入内容提供器。

覆盖《大众哲学》（艾思奇）——现已入库正文；断言分片结构完整、id 唯一、可被
content_provider 检索（原著浏览 / 对话溯源共用）。不依赖 OCR 进行中的文件。
"""
import pytest

from content.book_chunks import BOOKS, all_book_chunks, available_works, stats
from services import content_provider


def test_book_chunks_generated():
    chunks = all_book_chunks()
    assert chunks, "至少应生成《大众哲学》原文分片"
    works = available_works()
    assert "大众哲学" in works


def test_dazhexue_chunk_structure():
    dz = [c for c in all_book_chunks() if c["source"] == "大众哲学"]
    assert len(dz) >= 380, f"《大众哲学》分片数异常: {len(dz)}"   # 60 字下限合并后 390→380
    c = dz[0]
    for field in ("id", "layer", "source", "source_location", "text", "orthodoxy_tag", "authority_score"):
        assert field in c and c[field] not in ("", None)
    assert c["layer"] == 1
    assert c["authority_score"] == 1.0
    assert c["logical_type"] == "primary_text"
    assert c["is_primary_text"] is True
    # 原文照录：正文非空且不是占位符
    assert len(c["text"]) >= 15


def test_chunk_ids_unique():
    ids = [c["id"] for c in all_book_chunks()]
    assert len(ids) == len(set(ids)), "分片 id 必须唯一"
    # 分片 id 一律以 CH-<书代号>- 开头（各书前缀不同，但都在 CH- 命名空间内）
    assert all(i.startswith("CH-") for i in ids), "分片 id 必须以 CH- 开头"


def test_new_classic_works_ingested():
    """路线 A/B/C 经典原著已从本地镜像入库并生成真实分片。"""
    works = set(available_works())
    for w in ("实践论", "矛盾论", "论人民民主专政", "新民主主义论",
              "论十大关系", "关于正确处理人民内部矛盾的问题",
              "哥达纲领批判", "国家与革命", "反对本本主义", "中国社会各阶级的分析",
              # D87 依据路径.txt 补齐的第一阶段马恩/列宁奠基原著
              "共产党宣言", "德意志意识形态", "法兰西内战", "资本论（第一卷节选）",
              "怎么办？", "帝国主义是资本主义的最高阶段", "共产主义运动中的“左派”幼稚病",
              # D88 依据书籍.md 补齐的第二批经典原著
              "1844年经济学哲学手稿", "雇佣劳动与资本", "《政治经济学批判》序言",
              "路德维希·费尔巴哈和德国古典哲学的终结", "家庭、私有制和国家的起源",
              "马克思主义的三个来源和三个组成部分", "湖南农民运动考察报告",
              "改造我们的学习", "整顿党的作风", "反对党八股",
              "在延安文艺座谈会上的讲话"):
        assert w in works, f"《{w}》未入库或未生成分片"
        assert len([c for c in all_book_chunks() if c["source"] == w]) >= 5


def test_content_provider_includes_books():
    works = content_provider.works()
    assert "大众哲学" in works
    allc = content_provider.all_chunks()
    # 提纲分片 + 正文分片 合并且不冲突
    assert len(allc) == len(set(c["id"] for c in allc))
    bw = content_provider.chunks_by_work("大众哲学")
    assert bw, "按著作名应能检索到《大众哲学》分片"


def test_stats_shape():
    s = stats()
    assert "books" in s and "chunk_count" in s and "by_book" in s
    assert s["by_book"].get("大众哲学", 0) >= 380


def test_short_chunks_merged_not_fragmented():
    """分片下限：问答体/目录体不再被切成一句一片的碎片。

    背景：合并前全库 20% 的分片短于 40 字（《苏联社会主义经济问题》1520 片平均
    29 字、《选集目录序言》1029 片平均 28 字）。这种碎片既不能单独阅读、也没有
    自足语义，做检索单位只会靠「短 + 词频」刷分。
    """
    chunks = all_book_chunks()
    short = [c for c in chunks if len(c["text"]) < 40]
    assert len(short) / len(chunks) < 0.01, f"短分片占比回升：{len(short)}/{len(chunks)}"
    from content.book_chunks import MIN_CHUNK_CHARS

    tiny = [c for c in chunks if len(c["text"]) < MIN_CHUNK_CHARS]
    assert len(tiny) / len(chunks) < 0.01, f"低于下限的分片仍占 {len(tiny)}/{len(chunks)}"


def test_merge_loses_no_text():
    """合并只改切点，不改字：每部书分片按序拼接 ≈ 原文段落按序拼接。"""
    import re

    from content.book_chunks import _clean_para, _looks_like_prose
    from content.text_loader import TextLoader

    loader = TextLoader()
    bywork: dict[str, list[dict]] = {}
    for c in all_book_chunks():
        bywork.setdefault(c["source"], []).append(c)

    def norm(s: str) -> str:
        return re.sub(r"\s+", "", s)

    checked = 0
    for meta in BOOKS:
        if meta["work"] not in bywork:
            continue
        got = norm("".join(c["text"] for c in bywork[meta["work"]]))
        # 原文侧：同样剥掉分片器会丢弃的「<15 字 / 不像散文」的行
        paras = [_clean_para(p.get("text", "")) for p in loader.read_paragraphs(meta["file"])]
        want = norm("".join(t for t in paras if len(t) >= 15 and _looks_like_prose(t)))
        assert got == want, (meta["work"], len(got), len(want))
        checked += 1
    assert checked >= 200, f"只核对了 {checked} 部，覆盖面不足"
