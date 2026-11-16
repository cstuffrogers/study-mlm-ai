"""原文读取器 — 从 sources/texts/*.txt 读取中文原文，自动检测编码

用法：
    from content.text_loader import TextLoader
    loader = TextLoader()
    text = loader.read("3-国家与革命.txt")

支持 UTF-8 / GBK 自动检测。章节按空行或"第X章"分隔。
"""
from __future__ import annotations

import os
import re
from pathlib import Path

TEXTS_DIR = Path(__file__).resolve().parent.parent.parent / "sources" / "texts"


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
          - 过短段落（<20 字）跳过
        """
        text = self.read(filename)
        paragraphs: list[dict] = []
        # 按空行切段
        raw_paras = re.split(r"\n\s*\n", text)
        current_chapter = ""
        for i, para in enumerate(raw_paras):
            para = para.strip()
            if not para:
                continue
            # 检测章节标记
            ch_match = re.match(r"^(第[一二三四五六七八九十百零\d]+[章节篇编].*?)$", para)
            if ch_match:
                current_chapter = ch_match.group(1)
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
