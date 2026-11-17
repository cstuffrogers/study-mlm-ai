"""原文读取器 — 从 sources/texts/*.txt 读取中文原文，自动检测编码

用法：
    from content.text_loader import TextLoader
    loader = TextLoader()
    text = loader.read("3-国家与革命.txt")

支持 UTF-8 / GBK 自动检测。章节按空行或"第X章"分隔。
"""
from __future__ import annotations

import re
from pathlib import Path

TEXTS_DIR = Path(__file__).resolve().parent.parent.parent / "sources" / "texts"

# 句末标点：硬换行还原时以「行尾是否落在句末」作为接续依据。
_SENT_END = "。！？；：”』）】…!?"

# 编注/说明行：单独成段，不要和前一行拼成一句（「说明：此文为发表时的原文。」）。
_PARA_START = re.compile(r"^(说明|注释|按语|附记|编者|译者)[：:]")

# 标题/条目行：即便行尾不是句末标点，也独立成段（章、节、编号条目、注释）。
_HEADING = re.compile(
    r"^("
    r"第[一二三四五六七八九十百零\d]+[章节篇编讲部]"
    r"|[一二三四五六七八九十]+[、．.]"
    r"|\d+[、．.]"
    r"|（[一二三四五六七八九十]+）"
    r"|\([一二三四五六七八九十]+\)"
    r"|附[录件]"
    r"|注\s*释"
    r")"
)

# 硬换行体判定：行尾多数不落在句末 + 行普遍很短。
# 为什么要有这一步——镜像/OCR 文本常把一段话按固定列宽硬回车，行间再塞空行。
# 若照「空行分段」读，每一行都成了一个段落：《苏联社会主义经济问题》被切成
# 633 片、平均 73 字、93% 以半句结尾（《论列宁主义的几个问题》209 片 / 90%）。
# 这种分片既读不通，也不能当检索单位，引用出来永远是半句话。
_WRAP_NOEND_RATIO = 0.6
_WRAP_AVG_CHARS = 90


def is_hard_wrapped(text: str) -> bool:
    """粗判一份原文是不是「硬换行 + 空行」体（只影响切分方式，不改字）。"""
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    if len(lines) < 20:
        return False
    no_end = sum(1 for ln in lines if ln[-1] not in _SENT_END) / len(lines)
    avg = sum(len(ln) for ln in lines) / len(lines)
    return no_end > _WRAP_NOEND_RATIO and avg < _WRAP_AVG_CHARS


# 句末标点后仍可能跟着「收尾符号」：镜像把 」』）】 单独排到了下一行。
# 拼句时要把它接回上一句，否则分段会以「”第二，…」「）这是…」开头。
_LEAD_CLOSERS = "”』）】》〉"


def reflow_hard_wraps(text: str) -> list[str]:
    """把硬换行的行拼回句子级段落——只动换行，一字不改。

    规则：一直往后拼，直到累计文本落在句末标点；标题/编号/注释行独立成段；
    若某段以收尾符号（”』）】…）开头，说明它是上一句的尾巴，接回去。
    """
    paras: list[str] = []
    cur = ""
    for line in (ln.strip() for ln in text.splitlines()):
        if not line:
            continue
        if _PARA_START.match(line) and len(line) < 40:
            if cur:
                paras.append(cur)
                cur = ""
            paras.append(line)
            continue
        if _HEADING.match(line) and len(line) < 40:
            if cur:
                paras.append(cur)
                cur = ""
            paras.append(line)
            continue
        cur = f"{cur}{line}" if cur else line
        if cur[-1] in _SENT_END:
            paras.append(cur)
            cur = ""
    if cur:
        paras.append(cur)
    # 收尾符号回到上一段末尾（只移动标点，不动字序）
    merged: list[str] = []
    for para in paras:
        if merged and para and para[0] in _LEAD_CLOSERS:
            k = 0
            while k < len(para) and para[k] in _LEAD_CLOSERS:
                k += 1
            merged[-1] = merged[-1] + para[:k]
            para = para[k:]
            if not para:
                continue
        if para:
            merged.append(para)
    return merged


# 章节标记正则：标题必须短且不含逗号。
#
# 修复前这里是行内写的 `re.match(r"^(第[一二三四五六七八九十百零\d]+[章节篇编].*?)$", para)`
# —— `.*?` 被 `$` 顶成「整行」，于是任何以「第一章/第一篇」开头的**整段正文**都被
# 当成章标题（实测 9 段，最长 327 字）。后果两层：
#   ① 那 9 段正文被 `continue` 掉，从未进分片（漏收原文）；
#   ② 假标题写进 current_chapter，后面所有段落继承它 → 256 片 source_location
#      长达数百字，引文出处直接串行。
# 中文标题极少含逗号，正文极少在 40 字内结束又无逗号——两条同时成立才认标题。
_CHAPTER_HEAD_RE = re.compile(
    r"^(第[一二三四五六七八九十百零两\d]+[章节篇编][^\n]{0,40})$"
)


def _is_chapter_head(para: str) -> bool:
    return bool(_CHAPTER_HEAD_RE.match(para)) and "，" not in para


class TextLoader:
    """从 sources/texts/ 读取中文原文"""

    def __init__(self, texts_dir: Path | str | None = None) -> None:
        self.texts_dir = Path(texts_dir) if texts_dir else TEXTS_DIR

    def list_files(self) -> list[str]:
        """列出可用的原文文件"""
        if not self.texts_dir.exists():
            return []
        return sorted(f.name for f in self.texts_dir.glob("*.txt"))

    def read(self, filename: str) -> str:
        """读取单个文件，自动检测编码"""
        path = self.texts_dir / filename
        if not path.exists():
            raise FileNotFoundError(f"原文文件不存在: {path}")
        raw = path.read_bytes()
        # 尝试 UTF-8 → GBK → utf-8-sig
        for enc in ("utf-8-sig", "utf-8", "gbk", "gb18030"):
            try:
                return raw.decode(enc)
            except UnicodeDecodeError:
                continue
        raise UnicodeDecodeError(
            "无法解码文件（尝试 utf-8/gbk/gb18030）: " + filename,
            raw, 0, 1, "all decoders failed"
        )

    def read_paragraphs(self, filename: str) -> list[dict]:
        """读取并按段落切分，返回 [{paragraph_id, text, chapter_hint}]

        切分策略：
          - "第X章"/"第X节" 标记作 chapter_hint
          - 空行分隔的连续文本块作一个段落
          - 硬换行体（镜像/OCR 按列宽硬回车）先把句子拼回段落，再按段落落片
          - 过短段落（<20 字）跳过
        """
        text = self.read(filename)
        paragraphs: list[dict] = []
        if is_hard_wrapped(text):
            raw_paras = reflow_hard_wraps(text)
        else:
            # 按空行切段
            raw_paras = re.split(r"\n\s*\n", text)
        current_chapter = ""
        for i, para in enumerate(raw_paras):
            para = para.strip()
            if not para:
                continue
            # 检测章节标记
            if _is_chapter_head(para):
                current_chapter = para
                continue
            # 跳过过短段落（目录、页码等）
            if len(para) < 20:
                continue
            paragraphs.append({
                "paragraph_id": f"{Path(filename).stem}-p{len(paragraphs)+1}",
                "text": para,
                "chapter_hint": current_chapter,
            })
        return paragraphs


if __name__ == "__main__":
    loader = TextLoader()
    files = loader.list_files()
    if not files:
        print("sources/texts/ 目录为空。")
        print("请按 sources/texts/README.md 放入中文原文文件。")
    else:
        print(f"发现 {len(files)} 个原文文件:")
        for f in files:
            paras = loader.read_paragraphs(f)
            print(f"  {f}: {len(paras)} 段")
