"""从 D 盘「中文马克思主义文库」镜像照录原著正文 → sources/texts/*.txt

红线：
  * 只收镜像里确有中文全文的著作；不伪造、不改写、不补写。
  * 抽取只做「技术清洗」：解码、去 HTML 标签/站点导航、去页码页眉、
    空白归一、全角数字/拉丁字母归一化（PDF 文字层），不增删实质文字。
  * 每部著作的来源、版本、页/文件范围记入 sources/texts/SOURCE_MANIFEST.md。
  * 「目录页 / 书目页 / 无文字层扫描 PDF」不算全文，不入库。

用法：
  python scripts/import_mirror.py --dry-run      # 输出到 .local/mirror_extract/ 供人工抽查
  python scripts/import_mirror.py --write       # 正式写入 sources/texts/
  python scripts/import_mirror.py --pdf-probe   # 只打印 PDF 文字层探测结果
  python scripts/import_mirror.py --dry-run --no-trim  # 生成裁剪前全文，用于复核/回退

D101 章节裁剪：9 部长篇按「符合路线的章节」照录保留，见下方 TRIM。
  裁剪只删整段、不改写一字；边界全部落在章节标题行，不切段中。
  裁剪前的 D100 全文已备份在 sources/_backup_d101_pretrim/。
  SPECS 里这 9 部的 note 已同步改为「节选·保留哪些章」口径。

D102 章节标题修复：早期 5 部多文件著作（唯批 / 资本论二、三卷 / 一元论历史观 /
  思想起源论）曾被误删 36 个分文件首行章节标题，已给这 5 部加 keep_titles=True
  脚本化补回（只加回照录的标题行，不改写任何正文）。裁剪前备份在
  sources/_backup_d102_pretitle/；命令行加 --no-keep-titles 可逐字节复现修复前产物。

Windows 原生路径（MSYS 的 /d/... 传给 Python os.walk 会得 0 文件）。
"""
from __future__ import annotations

import argparse
import html
import os
import re
import sys
from pathlib import Path

# 镜像根目录：默认指向本机下载的离线镜像，可用环境变量 XXMZ_MIRROR 覆盖。
# 开源后其他人没有这个路径，必须自己指定；指向 …/www.marxists.org/chinese 这一级。
MIRROR = Path(
    os.getenv(
        "XXMZ_MIRROR",
        r"D:\BaiduNetdiskDownload\中文马克思主义文库网站镜像压缩包"
        r"\中文马克思主义文库\www.marxists.org\chinese",
    )
)
ROOT = Path(__file__).resolve().parent.parent
TEXTS = ROOT / "sources" / "texts"
DRY = ROOT / ".local" / "mirror_extract"

# 站点导航 / 翻页链接 / 页码 —— 非正文，剔除
_NAV_PAT = re.compile(
    r"^(?:中文马克思主义文库\s*-&gt;|中文马克思主义文库\s*->|"
    r"上一篇|回目录|下一篇|上一页|目录|下一页|返回|首页|Top\s*$)", re.I)
_NAV_ANY = re.compile(r"中文马克思主义文库\s*(?:-&gt;|->)")
# D118：部分作者目录页（如 `lidazhao/`）的面包屑被网页断成两行——
#   「中文马克思主义文库」\n「-> 李大钊」
# 与单行形式「中文马克思主义文库 -> 李大钊」同属站点导航；两行都剔除。
_NAV_SPLIT = re.compile(r"^(?:中文马克思主义文库|->\s*\S{1,24})$")
_PAGE_NUM = re.compile(r"^[\s\d\u3000\uff10-\uff19ivxlcdmIVXLCDM\W]{0,12}$")

# D119：部分作者页（如 `chenduxiu/`、`xiangjingyu/`）末尾带站点志愿者的录入致谢行，
# 形如「感谢 先知在1917 收集、录入及校对」「感谢 骨质增生的GM 录入及校对」。
# 这是文库网站自己的贡献者署名，不是原著正文，也不见于任何纸质版本——按站点噪声剔除。
# 限定：整行以「感谢/鸣谢」开头、长度 ≤60、且含录入/校对字样，避免误删正文句子；
# 只含「收集、整理」的旧有行（如《论列宁主义基础》篇末）不动，保证既有正文零 diff。
_SITE_CREDIT = re.compile(r"^(?:感谢|鸣谢)[^。；]{0,50}(?:录入|校对)")


def decode_html(path: Path) -> str:
    raw = path.read_bytes()
    m = re.search(rb"charset\s*=\s*[\"']?\s*([\w\-]+)", raw[:4096].lower())
    enc = m.group(1).decode("ascii", "replace") if m else "gb18030"
    if enc in ("gb2312", "gbk", "gb18030", "big5"):
        enc = "gb18030"
    try:
        s = raw.decode(enc, errors="replace")
    except LookupError:
        s = raw.decode("gb18030", errors="replace")
    return s


def html_to_lines(path: Path, *, strip_title_repeat: bool = True) -> list[str]:
    """HTML → 自然段落行（保留原文文字，只去标签/导航/空白）。

    strip_title_repeat：剔除网页顶部把 <title> 再输出一遍的重复行。
    ⚠️ 多文件拼接时仅第一个文件可为 True：后续分文件的可见首行往往正是
    「第一章/第一节/序言」等**章节标题**，与该文件 <title> 相同却属于正文，
    误删会让拼接后的原著失去篇章结构（D100 补录时发现并修正）。
    """
    s = decode_html(path)
    # 站点 <title> 元数据行（形如「《列宁全集》第十八卷——第一章 …」）：不是正文，剔除。
    # 网页正文里通常紧接着重复一遍真正的章节标题，故不会丢正文。
    title_meta = re.search(r"(?is)<title[^>]*>(.*?)</title>", s)
    site_title = html.unescape(re.sub(r"<[^>]+>", " ", title_meta.group(1))) if title_meta else ""
    site_title = re.sub(r"[ \t\r\f\v\u00a0\u3000]+", " ", site_title).strip()
    s = re.sub(r"(?is)<title[^>]*>.*?</title>", " ", s)
    # 网页顶部常把 title 再作为 <h1>/可见行输出一遍
    title_first = site_title.split("——", 1)[-1].strip() if "——" in site_title else ""

    # 仅去非正文块；注释里的文字属于该版本正文，保留
    s = re.sub(r"(?is)<script.*?</script>|<style.*?</style>|<!--.*?-->", " ", s)
    s = re.sub(r"(?i)<br\s*/?>|</p>|</div>|</tr>|</h[1-6]>|</li>|</td>|</blockquote>", "\n", s)
    s = re.sub(r"(?s)<[^>]+>", " ", s)
    s = html.unescape(s)
    s = s.replace("\xa0", " ")
    # 空白归一（不动中文字符）
    s = re.sub(r"[ \t\r\f\v\u00a0\u3000]+", " ", s)
    lines: list[str] = []
    for ln in s.split("\n"):
        ln = ln.strip()
        if not ln:
            continue
        if strip_title_repeat:
            if site_title and ln == site_title:
                continue
            if title_first and ln == title_first and len(lines) == 0:
                continue
        if _NAV_ANY.search(ln) or _NAV_PAT.match(ln) or _NAV_SPLIT.match(ln):
            continue
        if _SITE_CREDIT.match(ln) and len(ln) <= 60:
            continue
        if ln in ("上一篇 回目录 下一篇", "上一页 目录 下一页", "回目录 下一篇"):
            continue
        if re.fullmatch(r"[<\s>\-—·\d\W]{0,20}", ln):
            continue
        lines.append(ln)
    return lines


def pdf_lines(page_range: tuple[int, int], pdf_rel: str) -> list[str]:
    """PDF 文字层 → 行（保留印刷折行，交由 merge_pdf_lines 合段）。

    清洗只作用于「非正文的版面噪声」：页眉、印刷页码、◇页码◇、分隔线、
    PUA 私用区造字、全角 ASCII 字符（U+FF01–U+FF5E → ASCII，不碰汉字与中文标点）。
    不改动任何正文汉字。
    """
    import fitz  # PyMuPDF

    path = MIRROR / pdf_rel
    doc = fitz.open(str(path))
    out: list[str] = []
    cjk = lambda s: sum(1 for c in s if "\u4e00" <= c <= "\u9fff")
    for pno in range(page_range[0] - 1, min(page_range[1], doc.page_count)):
        txt = doc[pno].get_text("text", sort=True)
        for ln in txt.split("\n"):
            ln = ln.strip()
            if not ln:
                continue
            # 私用区造字（PDF 字体映射残留，不是汉字）→ 去掉该字符
            ln = "".join(c for c in ln if not (0xE000 <= ord(c) <= 0xF8FF))
            ln = re.sub(r"◇\s*\d+\s*◇", " ", ln)      # 跨页印刷页码
            ln = re.sub(r"[—\-─=＝]{4,}", " ", ln)     # 分隔线／目录点线
            # 全角 ASCII → 半角（只作用于 FF01-FF5E 的 ASCII 对应字符，不碰中文标点/汉字）
            ln = "".join(
                chr(ord(c) - 0xFEE0) if 0xFF01 <= ord(c) <= 0xFF5E else c
                for c in ln)
            ln = ln.replace("\u3000", " ")
            # 页眉：独立一行的卷名/书名（不含正文，且无句读）
            if cjk(ln) <= 12 and re.fullmatch(
                    r"[\s\d]*(?:马克思恩格斯选集|斯大林全集|苏联社会主义经济问题|"
                    r"目\s*录|第[一二三四]卷说明)[\s\d]*", ln):
                continue
            # 交替页眉混在正文行首（如「马克思恩格斯选集 本卷开篇…」）：只去掉页眉词
            ln = re.sub(r"^\s*(?:马克思恩格斯选集|斯大林全集|苏联社会主义经济问题)\s+(?=\S)", "", ln)
            if re.fullmatch(r"[\s\d]{1,10}", ln):       # 纯印刷页码
                continue
            ln = re.sub(r"[ \t]{2,}", " ", ln).strip()
            if ln:
                out.append(ln)
    doc.close()
    return out


def merge_pdf_lines(lines: list[str], max_chars: int = 900) -> list[str]:
    """PDF 印刷折行逐行照录，不合并、不改字。

    与 HTML 抽取保持一致：每一行成为一个 txt 自然段，由 text_loader 按空行切分。
    折行造成的「一句多行」在阅读器里仍是连续的独立分片，不影响原文真实性；
    强行按标点合段反而会把目录条目、标题与正文黏成一团。
    """
    return [ln for ln in lines if ln]


# ---------------------------------------------------------------------------
# 入库清单：每部著作 = 一个 txt，来源文件按顺序列出（照录，不拼接别的著作）
# ---------------------------------------------------------------------------
SPECS: list[dict] = [
    # ===== 必读 5 本 =====
    dict(
        file="0-马克思恩格斯选集目录.txt",
        work="马克思恩格斯选集（四卷本·目录序言）", author="马克思恩格斯",
        prefix="CH-MES-", slug="mes",
        pdf=[("pdf/marx-engels/mes01.pdf", 1, 16),
             ("pdf/marx-engels/mes02.pdf", 1, 19),
             ("pdf/marx-engels/mes03.pdf", 1, 16),
             ("pdf/marx-engels/mes04.pdf", 1, 20)],
        note="《马克思恩格斯选集》中文第2版四卷本（人民出版社）目录 + 各卷说明。"
             "按《书籍.md》第0阶段要求「翻阅目录序言即可」入库，非四卷全文；"
             "PDF 文字层为带文字层扫描版，全角数字/拉丁字母按 U+FF01–U+FF5E 归一，剔除页眉页码。",
    ),
    dict(
        file="3-唯物主义和经验批判主义.txt",
        work="唯物主义和经验批判主义", author="列宁",
        prefix="CH-WP-", slug="wp",
        html=["lenin-cworks/18/003.html", "lenin-cworks/18/004.html",
              "lenin-cworks/18/005.html", "lenin-cworks/18/006.html",
              "lenin-cworks/18/007.html", "lenin-cworks/18/008.html",
              "lenin-cworks/18/009.html", "lenin-cworks/18/010.html",
              "lenin-cworks/18/011.html"],
        keep_titles=True,  # D102：补回各分文件被误删的章节标题行（7 个）
        note="《列宁全集》中文第2版第18卷：代绪论、第一至六章、结论、第四章第1节补充。"
             "不含卷首凡例、涅夫斯基论文、年表、目录。",
    ),
    dict(
        file="3-反杜林论哲学篇.txt",
        work="反杜林论（哲学篇）", author="恩格斯",
        prefix="CH-FDL-", slug="fdl",
        html=["marx-engels-2/26/001.html", "marx-engels-2/26/002.html",
              "marx-engels-2/26/003.html"],
        note="《马恩全集》中文第2版第26卷：三个版本的序言、引论、第一编 哲学。"
             "按必读要求只收哲学篇，未收第二/三编及《反杜林论》准备材料。",
    ),
    dict(
        file="4-资本论第二卷.txt",
        work="资本论（第二卷）", author="马克思",
        prefix="CH-ZBL2-", slug="zbl2",
        html=[f"marx-engels/24/{i:03d}.html" for i in (1, 2, 3, 4, 5, 6, 8, 9, 10, 17, 20, 21, 22, 23)],
        keep_titles=True,  # D102：补回「第一篇 资本形态变化及其循环」等 13 个标题行
        note="《资本论》第二卷**节选**：按《书籍.md》第4阶段要求「重点第1篇资本形态变化」"
             "及第3篇社会总资本再生产，从《马恩全集》中文第1版第24卷选 14 篇"
             "（恩格斯序、第二版序言、第一篇第1—6章、第二篇引言/第8/17章、第三篇引言/第19—21章）。"
             "按章节原样裁剪，不改写正文；未收其余各章、卷末人名/文献/名目索引。",
    ),
    dict(
        file="4-资本论第三卷.txt",
        work="资本论（第三卷）", author="马克思",
        prefix="CH-ZBL3-", slug="zbl3",
        html=[f"marx-engels/25/{i:03d}.html" for i in (1, 2, 3, 4, 5, 9, 10, 11, 37, 38, 39, 40, 45, 46, 47, 48)],
        keep_titles=True,  # D102：补回 11 个章节标题行
        note="《资本论》第三卷**节选**：按《书籍.md》第4阶段要求「重点第1篇/第6篇」，"
             "从《马恩全集》中文第1版第25卷选 16 篇（恩格斯序、第一篇第1—5章、"
             "第二篇第8—11章、第六篇第37—40章、第七篇第45—48章）。"
             "按章节原样裁剪，不改写正文；未收其余各章、增补、卷末索引。",
    ),

    # ===== 延伸阅读：马恩短篇 =====
    dict(file="0-在马克思墓前的讲话.txt", work="在马克思墓前的讲话", author="恩格斯",
         prefix="CH-MQJ-", slug="mqj", html=["engels/mia-chinese-engels-18830317.html"],
         note="恩格斯《在马克思墓前的讲话》（1883-03-17），镜像单篇页，含译文附注与悼词草稿附录。"),
    dict(file="0-工资价格和利润.txt", work="工资、价格和利润", author="马克思",
         prefix="CH-GZJG-", slug="gzjg", html=["marx/marxist.org-chinese-marx-1865-5.html"],
         note="马克思《工资、价格和利润》（1865），镜像单篇全文页。"),
    dict(file="0-论权威.txt", work="论权威", author="恩格斯",
         prefix="CH-LQW-", slug="lqw", html=["engels/marxist.org-chinese-engels-1872-1873.html"],
         note="恩格斯《论权威》（1872-1873），镜像单篇全文页，含译注。"),
    dict(file="2-路易波拿巴的雾月十八日.txt", work="路易·波拿巴的雾月十八日", author="马克思",
         prefix="CH-WY-", slug="wy", html=["marx-engels2/02/09.html"],
         note="《马克思恩格斯文集》第2卷所收《路易·波拿巴的雾月十八日》全文（含文集注释）。"),
    dict(file="2-给维伊查苏利奇的复信草稿.txt", work="给维·伊·查苏利奇的复信草稿", author="马克思",
         prefix="CH-ZSLQ-", slug="zslq", html=["marx-engels/19/055.html"],
         note="《马恩全集》第19卷所收《给维·伊·查苏利奇的复信草稿》页（含四个草稿与全集注释）。"),
    dict(file="3-自然辩证法导言.txt", work="自然辩证法（导言）", author="恩格斯",
         prefix="CH-ZR-", slug="zr", html=["engels/marxist.org-chinese-engels-1875.html"],
         note="恩格斯《自然辩证法》导言单篇页。按延伸阅读要求只收导言（节选），未收全集第20卷全卷。"),
    dict(file="2-1857-1858年经济学手稿.txt", work="1857-1858年经济学手稿（大纲）", author="马克思",
         prefix="CH-DG-", slug="dg",
         html=[f"marx-engels-2/30/{i:03d}.html" for i in (3, 4, 5, 6, 7, 10, 13, 15, 17)],
         note="《马恩全集》中文第2版第30卷所收 1857—1858 年经济学手稿**节选**："
             "《政治经济学批判》导言 + 《政治经济学批判（1857—1858年手稿）》9 个长章。"
             "按章节原样裁剪，不改写正文；未收第31卷所收后半部、卷末注释/索引。"),

    # ===== 延伸阅读：普列汉诺夫 / 拉法格 =====
    dict(file="3-论一元论历史观的发展.txt", work="论一元论历史观的发展", author="普列汉诺夫",
         prefix="CH-YYL-", slug="yyl",
         html=["plekhanov/1895/00a.html", "plekhanov/1895/00b.html",
               "plekhanov/1895/01.html", "plekhanov/1895/02.html",
               "plekhanov/1895/05.html"],
         keep_titles=True,  # D102：补回第一/五章标题行（2 个）
         note="普列汉诺夫《论一元论历史观的发展问题》（1895）**节选**：译者序言、第二/三版序言、"
             "第一章、第二章、第五章。按章节原样裁剪，不改写正文；未收第三/四章、结论、附录。"),
    dict(file="3-思想起源论.txt", work="思想起源论", author="拉法格",
         prefix="CH-SXQY-", slug="sxqy",
         html=["lafargue/1909/00.html", "lafargue/1909/01.html",
               "lafargue/1909/02.html", "lafargue/1909/03.html"],
         keep_titles=True,  # D102：补回 3 个篇章标题行（《卡尔·马克思的历史方法》等）
         note="拉法格《思想起源论——卡尔·马克思的经济决定论》（1909）**节选**：梅林代序 + "
             "第一章《卡尔·马克思的历史方法》 + 第二/三章《抽象思想的起源》《正义思想的起源》。"
             "按章节原样裁剪，不改写正文；未收第四至六章。"),

    # ===== 延伸阅读：列宁 / 斯大林 =====
    dict(file="1-论列宁主义基础.txt", work="论列宁主义基础", author="斯大林",
         prefix="CH-LLN-", slug="lln", html=["stalin/mia-chinese-stalin-192404.html"],
         note="斯大林《论列宁主义基础——在斯维尔德洛夫大学的讲演》（1924-04），镜像单篇全文页。"),

    # ===== 延伸阅读：毛泽东 / 周恩来 =====
    dict(file="5-星星之火可以燎原.txt", work="星星之火，可以燎原", author="毛泽东",
         prefix="CH-XXZH-", slug="xxzh", html=["maozedong/marxist.org-chinese-mao-19300105.html"],
         note="毛泽东《星星之火，可以燎原》（1930-01-05），镜像单篇全文页，含人民出版社题解与注释。"),
    dict(file="5-关于领导方法的若干问题.txt", work="关于领导方法的若干问题", author="毛泽东",
         prefix="CH-LDFF-", slug="ldff", html=["maozedong/marxist.org-chinese-mao-19430601.html"],
         note="毛泽东《关于领导方法的若干问题》（1943-06-01），镜像单篇全文页。"),
    dict(file="1-在白色恐怖下如何健全党的组织工作.txt", work="在白色恐怖下如何健全党的组织工作",
         author="周恩来", prefix="CH-BSKB-", slug="bskb", html=["zhouenlai/005.html"],
         note="周恩来《在白色恐怖下如何健全党的组织工作》（1929-03-25），镜像单篇全文页。"),
    dict(file="1-怎样做一个好的领导者.txt", work="怎样做一个好的领导者",
         author="周恩来", prefix="CH-HLDZ-", slug="hldz", html=["zhouenlai/023.html"],
         note="周恩来《怎样做一个好的领导者》（1943-04-22），镜像单篇全文页。"),
    dict(file="1-反对官僚主义.txt", work="反对官僚主义", author="周恩来",
         prefix="CH-FGL-", slug="fgl", html=["zhouenlai/142.html"],
         note="周恩来《反对官僚主义》（1963-05-29），镜像单篇全文页。"),
    dict(
        file="5-苏联社会主义经济问题.txt",
        work="苏联社会主义经济问题", author="斯大林",
        prefix="CH-SHJ-", slug="shj",
        pdf=[("pdf/russian_communists/stalin/nz1-20.pdf", 6298, 6366)],
        note="《斯大林全集》中文版第二十卷所收《苏联社会主义经济问题》全文（PDF 页 6298—6366）："
             "《对于和1951年十一月讨论会有关的经济问题的意见》 + 答诺特京同志 + "
             "《关于尔·德·雅罗申科同志的错误》 + 答萨宁娜和文热尔两同志。"
             "据卷内目录精确裁取，剔除页眉『斯大林全集 第二十卷』、印刷页码、◇页码◇、分隔线；"
             "保留该卷编者脚注。下一篇《答美国一些地方报纸编辑提出的问题》自 6367 页起，未收。",
    ),
    dict(file="5-读苏联政治经济学教科书的谈话.txt", work="读苏联《政治经济学教科书》的谈话",
         author="毛泽东", prefix="CH-DJKS-", slug="djks",
         html=[f"maozedong/1968/4-{i}.html" for i in range(175, 180)],
         note="版本声明：镜像所收为 1968 年汉版《毛泽东思想万岁》中的《苏联〈政治经济学教科书〉"
             "阅读笔记（社会主义部分、第三版）》五篇（第一至四部分 + 补遗），不是通行的『谈话』整理稿。"
             "内容同源但篇名/版本不同，引用须注明版本。"),

    # ===== D100 补录（P0：设计文档点名但路径未落地）=====
    dict(file="1-我的修养要则.txt", work="我的修养要则", author="周恩来",
         prefix="CH-XYYZ-", slug="xyyz", html=["zhouenlai/021.html"],
         note="周恩来《我的修养要则》（1943-03-18），《周恩来选集》上卷官版单篇页，"
             "含题解『本文是在重庆红岩整风学习时写的』。七条全文，无删节。"),
    dict(file="1-加强调查研究.txt", work="加强调查研究", author="周恩来",
         prefix="CH-JQDC-", slug="jqdc", html=["zhouenlai/132.html"],
         note="《周恩来选集》下卷官版页（1961 年 3 月、5 月），**两则合编、各带题解**："
             "〈调查研究，实事求是〉（1961-03-19，题解注明系中共中央工作会议中南、华北小组会上的讲话节录）"
             "＋〈关于食堂和评工记分等问题的调查〉（1961-05-07，题解注明系河北邯郸农村调查期间"
             "给毛泽东的电话汇报记录）。篇名『加强调查研究』为选集编者所拟，"
             "与《路径.txt》所写『怎样进行调查研究』非同名文献；题解与注释照录。"),
    dict(file="1-关于党的六大的研究.txt", work="关于党的“六大”的研究", author="周恩来",
         prefix="CH-LD-", slug="ldyj", html=["zhouenlai/026.html"],
         note="周恩来 1944-03-03/04 在延安中央党校所作报告，《周恩来选集》上卷官版长篇全文，"
             "含题解与编号注释。"),
    dict(file="1-说真话鼓真劲做实事收实效.txt", work="说真话，鼓真劲，做实事，收实效", author="周恩来",
         prefix="CH-SZH-", slug="szh", html=["zhouenlai/135.html"],
         note="《周恩来选集》下卷官版页（1962-02-03）。题解明示：系在中共中央扩大的工作会议"
             "福建组会上讲话的**第四个问题『检讨的目的』抽出成篇**，属节选而非长篇讲话全文；"
             "题解与编号注释照录。"),
    dict(file="5-论联合政府.txt", work="论联合政府", author="毛泽东",
         prefix="CH-LHZF-", slug="lhzf",
         html=["maozedong/marxist.org-chinese-mao-19450424.html"],
         note="毛泽东 1945-04-24 在中共七大所作政治报告，《毛泽东选集》第三卷版。"
             "**D101 按学习路线裁为节选**：只保留「一 中国人民的基本要求」、第四章总论与"
             "「我们的一般纲领／具体纲领」、第五章全党团结；裁去形势分析、两条路线论战、"
             "逐条具体政策与 29 条尾注。原文一字未改，边界均为章节标题行。"
             "**只用毛选版**；镜像另有 marxist.org-chinese-mao-19450424aa.html 为『未删改原始版』"
             "（编者按自述收入毛选时曾大幅修改），版本不同，不入库。"),

    # ===== D100 补录（P1·A 组：马恩经典，补思想转变链）=====
    dict(file="0-黑格尔法哲学批判导言.txt", work="《黑格尔法哲学批判》导言", author="马克思",
         prefix="CH-HGDF-", slug="hgdf", html=["marx-engels2/01/01.html"],
         note="《马克思恩格斯文集》第 1 卷所收马克思《〈黑格尔法哲学批判〉导言》（1844）全文，"
             "含文集编者注。镜像另有 marx/marxist.org-chinese-marx-1843.html（全集第 1 卷版），本条取文集版。"),
    dict(file="0-哲学的贫困.txt", work="哲学的贫困", author="马克思",
         prefix="CH-ZXPK-", slug="zxpk", keep_titles=True,
         html=[f"marx-engels/04/{i:03d}.html" for i in (11, 12, 13, 14)],
         note="《马恩全集》中文第 1 版第 4 卷所收《哲学的贫困。答蒲鲁东先生的『贫困的哲学』》（1847），"
             "按 4 个 HTML 文件顺序照录拼接。**D101 裁为节选**：保留题名/题解/序言、"
             "第一章第一节「使用价值和交换价值的对立」、第二章第一节「方法」；裁去价值论细部与"
             "分工/机器、竞争、地租、罢工等专论。原文一字未改，边界均为章节标题行。"
             "注意 marx-engels2/01/17.html 本身也是**节选**，不得当全文。"),
    dict(file="0-社会主义从空想到科学的发展.txt", work="社会主义从空想到科学的发展", author="恩格斯",
         prefix="CH-KXDX-", slug="kxdx", html=["marx-engels2/03/21.html"],
         note="《马克思恩格斯文集》第 3 卷所收恩格斯《社会主义从空想到科学的发展》（1880）。"
             "**D101 裁为节选**：保留题名页、马克思写的 1880 年法文版前言、正文「一／二／三」"
             "三章及文集注释；裁去 1882 德文第一版序言、1891 德文第四版序言、1892 英文版导言"
             "（与 A 路线唯物史观主线重复）。原文一字未改，边界均为章节标题行。"),

    # ===== D100 补录（P1·B 组：列宁组织/策略链 + 中国革命道路定型）=====
    dict(file="1-进一步退两步.txt", work="进一步，退两步", author="列宁",
         prefix="CH-JYTB-", slug="jytb", html=["lenin-cworks/08/028.html"],
         note="《列宁全集》中文第 2 版第 8 卷所收《进一步，退两步（我们党内的危机）》（1904）。"
             "**D101 裁为节选**：保留卷首/序言、第（七）—（九）节「党章第1条」与组织原则"
             "（民主集中制原始论证）、第（十八）节「稍微谈谈辩证法。两个变革」；裁去代表大会"
             "逐日记录、选举细节、会后派别斗争与附录。原文一字未改，边界均为章节标题行。"),
    dict(file="1-两种策略.txt", work="社会民主党在民主革命中的两种策略", author="列宁",
         prefix="CH-LZCL-", slug="lzcl", keep_titles=True,
         html=["lenin/190506-07/00.html"] + [f"lenin/190506-07/{i:02d}.html" for i in range(1, 15)],
         note="《列宁全集》所收《社会民主党在民主革命中的两种策略》（1905-06/07），"
             "依目录 index.html 顺序拼接 15 个 HTML 文件。**D101 裁为节选**：保留卷首题解/注释、"
             "第 10 节「『革命公社』与无产阶级和农民的革命民主专政」、第 13 节结论"
             "「我们敢不敢胜利？」；裁去 1—9、11、12 节俄国内派别论战细节与「补充说明」。"
             "原文一字未改，边界均为章节标题行。lenin-cworks/11/001.html 仅为目录页，勿误取。"),
    dict(file="1-无产阶级革命和叛徒考茨基.txt", work="无产阶级革命和叛徒考茨基", author="列宁",
         prefix="CH-KCJJ-", slug="kcjj", html=["lenin-cworks/35/055.html"],
         note="《列宁全集》中文第 2 版第 35 卷所收《无产阶级革命和叛徒考茨基》（1918）。"
             "**D101 裁为节选**：保留题名/目录、序言、「考茨基怎样把马克思变成了庸俗的自由主义者」、"
             "「资产阶级民主和无产阶级民主」、「苏维埃不得变成国家组织」（无产阶级专政与民主的"
             "主体论证）；裁去「立宪会议和苏维埃共和国」及其后各节、经济分析辩驳与两个附录。"
             "原文一字未改，边界均为章节标题行。"),
    dict(file="5-共产党人发刊词.txt", work="《共产党人》发刊词", author="毛泽东",
         prefix="CH-FKC-", slug="fkc",
         html=["maozedong/marxist.org-chinese-mao-19391004.html"],
         note="毛泽东《〈共产党人〉发刊词》（1939-10-04），《毛泽东选集》第二卷版全文（含题解与注释）。"),
    dict(file="5-中国革命和中国共产党.txt", work="中国革命和中国共产党", author="毛泽东",
         prefix="CH-ZGGM-", slug="zggm",
         html=["maozedong/marxist.org-chinese-mao-193912.html"],
         note="《毛泽东选集》第二卷版（1939-12）。**题解明示系合著、第一章由其他几个同志起草经毛泽东修改**，"
             "引用须声明合著性质。**D101 裁为节选**：保留题名/合著题解、第一章第三节"
             "「现代的殖民地、半殖民地和半封建社会」（国情判断）与第二章「中国革命」全章；"
             "裁去第一、二节古代社会史料细部与卷末注释。原文一字未改，边界均为章节标题行。"),
    dict(file="5-论持久战.txt", work="论持久战", author="毛泽东",
         prefix="CH-LJCZ-", slug="ljcz",
         html=["maozedong/marxist.org-chinese-mao-193805b.html"],
         note="毛泽东 1938-05 在延安抗日战争研究会的讲演，《毛泽东选集》第二卷版。"
             "**D101 裁为节选**：保留「问题的提起」「问题的根据」、「亡国论是不对的，速胜论也是不对的」"
             "与「持久战的三个阶段」、「能动性在战争中」、「兵民是胜利之本」与结论；裁去驳亡国论"
             "细部、犬牙交错/具体战役部署、运动战等军事技术章与尾注。原文一字未改，边界均为章节标题行。"),
    dict(file="5-关于纠正党内的错误思想.txt", work="关于纠正党内的错误思想", author="毛泽东",
         prefix="CH-JZDN-", slug="jzdn",
         html=["maozedong/marxist.org-chinese-mao-192912.html"],
         note="《毛泽东选集》第一卷版全文。题解明示为 1929-12 古田会议（红四军第九次党代会）"
             "**决议的第一部分**，引用须声明篇目来源；含题解与注释。"),
    dict(file="5-党委会的工作方法.txt", work="党委会的工作方法", author="毛泽东",
         prefix="CH-DWH-", slug="dwh",
         html=["maozedong/marxist.org-chinese-mao-19490313.html"],
         note="《毛泽东选集》第四卷版全文（1949-03-13）。题解明示为毛泽东在七届二中全会上"
             "所作**结论的一部分**，引用须声明；含题解。"),
    dict(file="5-七届二中全会报告.txt", work="在中国共产党第七届中央委员会第二次全体会议上的报告",
         author="毛泽东", prefix="CH-QJEZ-", slug="qjez",
         html=["maozedong/marxist.org-chinese-mao-19490305.html"],
         note="毛泽东 1949-03-05 报告，《毛泽东选集》第四卷版全文（含题解与注释）。"
             "与《党委会的工作方法》（同次会议结论的一部分）配套。"),

    # ===== D100 补录（P1·C 组：列宁—斯大林建设探索，接上 C 路线断环）=====
    dict(file="5-论粮食税.txt", work="论粮食税", author="列宁",
         prefix="CH-LSS-", slug="lss", html=["lenin-cworks/41/018.html"],
         note="《列宁全集》中文第 2 版第 41 卷所收《论粮食税（新政策的意义及其条件）》（1921-04-21）全文，含全集注释。"),
    dict(file="5-论合作社.txt", work="论合作社", author="列宁",
         prefix="CH-HZS-", slug="hzs", html=["lenin-cworks/43/100.html"],
         note="《列宁全集》中文第 2 版第 43 卷所收《论合作社》（1923-01-04/06）全文。"
             "注意 maozedong/1968/2-004.html 是毛泽东同名讲话，已排除。"),
    dict(file="5-宁肯少些但要好些.txt", work="宁肯少些，但要好些", author="列宁",
         prefix="CH-NKSX-", slug="nksx", keep_titles=True,
         html=["lenin-cworks/43/102.html", "lenin-cworks/43/103.html"],
         note="《列宁全集》中文第 2 版第 43 卷两篇配套文献："
             "《我们怎样改组工农检查院（向党的第十二次代表大会提出的建议）》（1923-01-23）"
             "＋《宁肯少些，但要好些》（1923-03-02），按卷内顺序拼接。"),
    dict(file="5-论列宁主义的几个问题.txt", work="论列宁主义的几个问题", author="斯大林",
         prefix="CH-LLNWT-", slug="llnwt",
         pdf=[("pdf/russian_communists/stalin/nz1-20.pdf", 2425, 2483)],
         note="《斯大林全集》中文版第 8 卷所收《论列宁主义的几个问题》（1926-01），"
             "据 1—20 卷合订 PDF 卷内目录精确裁取（物理页 2425—2483，七节齐全，PDF 有文字层）；"
             "剔除页眉『斯大林全集』、印刷页码、◇页码◇、分隔线，按页照录不改写。"
             "**D101 再按学习路线裁为节选**：保留题名/刊印说明、第六节"
             "「关于社会主义在一个国家内胜利的问题」、第七节「为社会主义建设的胜利而奋斗」；"
             "裁去前五节列宁主义定义与党内反对派论战。原文一字未改，边界均为章节标题行。"),
    # ===== D103 补录（用户 2026-11：都入，但按「合适的章节」节选入库，不整篇照录）=====
    # —— 毛泽东 8 篇：全部《毛泽东选集》官方版，按哲学/方法论章节裁剪，挂 B/C 路线 ——
    dict(file="5-中国革命战争的战略问题.txt", work="中国革命战争的战略问题", author="毛泽东",
         prefix="CH-ZGZM-", slug="zgzm",
         html=["maozedong/marxist.org-chinese-mao-193612.html"],
         note="《毛泽东选集》第一卷版（1936-12）。**D103 裁为节选**：保留第一章「如何研究战争」全章"
             "（战争规律是发展的／战争的目的在于消灭战争／战略问题是研究战争全局的规律的东西／"
             "重要的问题在善于学习）、第二章「中国共产党和中国革命战争」、第三章「中国革命战争的特点」"
             "全章、第四章「“围剿”和反“围剿”——中国内战的主要形式」；"
             "裁去第五章「战略防御」全部战术诸节（积极防御、反“围剿”的准备、战略退却、战略反攻、"
             "反攻开始、集中兵力、运动战、速决战、歼灭战）与卷末注释。"
             "原文一字未改，边界均为章节标题行。"),
    dict(file="5-抗日游击战争的战略问题.txt", work="抗日游击战争的战略问题", author="毛泽东",
         prefix="CH-KRYJ-", slug="kryj",
         html=["maozedong/marxist.org-chinese-mao-193805.html"],
         note="《毛泽东选集》第二卷版（1938-05）。**D103 裁为节选**：保留第一章「为什么提起游击战争的"
             "战略问题」、第二章「战争的基本原则是保存自己消灭敌人」、第三章「抗日游击战争的六个"
             "具体战略问题」、第四章「主动地灵活地有计划地执行防御战中的进攻战、持久战中的速决战、"
             "内线作战中的外线作战」（辩证法的军事运用）；裁去第五章「和正规战争相配合」、"
             "第六章「建立根据地」、第七章战略防御与进攻、第八章向运动战发展、第九章指挥关系与卷末注释。"
             "原文一字未改，边界均为章节标题行。"),
    dict(file="5-战争和战略问题.txt", work="战争和战略问题", author="毛泽东",
         prefix="CH-ZZZL-", slug="zzzl",
         html=["maozedong/marxist.org-chinese-mao-19381106.html"],
         note="《毛泽东选集》第二卷版（1938-11-06，中共六届六中全会报告的一部分）。"
             "**D103 裁为节选**：保留「一 中国的特点和革命」、「三 中国共产党的战争史」、"
             "「四 国内战争和民族战争中党的军事战略的转变」、「五 抗日游击战争的战略地位」；"
             "裁去「二 中国国民党的战争史」、「六 注意研究军事问题」与卷末注释。"
             "原文一字未改，边界均为章节标题行。"),
    dict(file="5-井冈山的斗争.txt", work="井冈山的斗争", author="毛泽东",
         prefix="CH-JGSD-", slug="jgsd",
         html=["maozedong/marxist.org-chinese-mao-19281125.html"],
         note="《毛泽东选集》第一卷版（1928-11-25，写给中共中央的报告）。"
             "**D103 裁为节选**：保留题解、「湘赣边界的割据和八月失败」、「割据地区的现势」、"
             "「土地问题」、「政权问题」、「党的组织问题」、「革命性质问题」、「割据地区问题」；"
             "裁去「军事问题」细部与卷末注释。原文一字未改，边界均为章节标题行。"),
    dict(file="5-中国的红色政权为什么能够存在.txt", work="中国的红色政权为什么能够存在？", author="毛泽东",
         prefix="CH-HSZQ-", slug="hszq",
         html=["maozedong/marxist.org-chinese-mao-19281005.html"],
         note="《毛泽东选集》第一卷版（1928-10-05，湘赣边界党的第二次代表大会决议的一部分）。"
             "**D103 裁为节选**：保留「一 国内的政治状况」、「二 中国红色政权发生和存在的原因」"
             "（农村包围城市道路的理论原点）、「五 经济问题」；裁去「三 湘赣边界的割据和八月的失败」、"
             "「四 湘赣边界的割据局面在湘鄂赣三省的地位」、「六 军事根据地问题」与卷末注释。"
             "原文一字未改，边界均为章节标题行。"),
    dict(file="5-论反对日本帝国主义的策略.txt", work="论反对日本帝国主义的策略", author="毛泽东",
         prefix="CH-FDRB-", slug="fdrb",
         html=["maozedong/marxist.org-chinese-mao-19351227.html"],
         note="《毛泽东选集》第一卷版（1935-12-27，瓦窑堡会议后陕北党的活动分子会议报告）。"
             "**D103 裁为节选**：保留「目前政治形势的特点」（各阶级分析）、「民族统一战线」、"
             "「人民共和国」、「国际援助」四节全文；裁去卷末注释。原文一字未改，边界均为章节标题行。"),
    dict(file="5-学习和时局.txt", work="学习和时局", author="毛泽东",
         prefix="CH-XXSJ-", slug="xxsj",
         html=["maozedong/marxist.org-chinese-mao-19440412.html"],
         note="《毛泽东选集》第三卷版（1944-04-12，延安高级干部会议讲演）。"
             "**D103 裁为节选**：只收正文三节（一、二、三），即「放下包袱、开动机器」的"
             "认识论与整风总结；**刻意不收网页所附《关于若干历史问题的决议》**——"
             "该决议属党的文献而非毛泽东著作，另有 sec_C 官方文献议题，避免与原著混编。"
             "裁去附录与卷末注释。原文一字未改，边界均为章节标题行。"),
    dict(file="5-在省市自治区党委书记会议上的讲话.txt", work="在省市自治区党委书记会议上的讲话",
         author="毛泽东", prefix="CH-SSWJ-", slug="sswj",
         html=["maozedong/marxist.org-chinese-mao-195701.html"],
         note="《毛泽东选集》第五卷版（1957-01，一月十八日与一月二十七日两次讲话）。"
             "**D103 裁为节选**：保留「一 一月十八日的讲话」全文与「二 一月二十七日的讲话」前五点"
             "（含「第四点，百花齐放，百家争鸣」与「第五点，闹事问题」，社会主义社会矛盾的具体分析）；"
             "裁去「第六点，法制问题」及其后的农业问题、出版信息与卷末注释。"
             "原文一字未改，边界均为章节标题行。"),

    # —— 列宁 2 篇（补 A 路线「哲学/国家学说」与早期民粹派批判）——
    dict(file="1-论国家.txt", work="论国家", author="列宁",
         prefix="CH-LGJ-", slug="lgj",
         html=["lenin-cworks/37/004.html"],
         note="《列宁全集》中文第 2 版第 37 卷所收《论国家——在斯维尔德洛夫大学的讲演》"
             "（1919-07-11）全文，含全集注释。是《国家与革命》的通俗讲授版，"
             "适合 sec_A（国家学说）与 B 路线对照读。"),
    dict(file="1-评经济浪漫主义.txt", work="评经济浪漫主义", author="列宁",
         prefix="CH-PJJL-", slug="pjjl",
         html=["lenin-cworks/02/009.html"],
         note="《列宁全集》中文第 2 版第 2 卷所收《评经济浪漫主义（西斯蒙第和我国的西斯蒙第主义者）》"
             "（1896-08—1897-03）。**D103 裁为节选**：保留「第二章 浪漫主义者对资本主义的"
             "批评的性质」全章（批判民粹派／小资产阶级浪漫主义的方法论示范）；"
             "裁去第一章对西斯蒙第国民收入论、国内市场理论的经济学史长篇考据。"
             "原文一字未改，边界均为章节标题行。"),

    # —— 斯大林 3 篇（补哲学前史与上层建筑专论）——
    dict(file="1-马克思主义和语言学问题.txt", work="马克思主义和语言学问题", author="斯大林",
         prefix="CH-YYX-", slug="yyx",
         html=["stalin/mia-chinese-stalin-1950.html"],
         note="斯大林《马克思主义和语言学问题》（1950-06—08，就语言学讨论所写的三篇答复）。"
             "**D103 裁为节选**：保留「论语言学中的马克思主义」全文（基础与上层建筑、"
             "语言无阶级性的经典论述）；裁去后两篇答复（「论语言学的几个问题」「答同志们」）"
             "与卷末注。原文一字未改，边界均为章节标题行。"),
    dict(file="1-马克思主义和民族问题.txt", work="马克思主义和民族问题", author="斯大林",
         prefix="CH-MZWT-", slug="mzwt",
         html=["stalin/marxist.org-chinese-stalin-1912.html"],
         note="斯大林《马克思主义和民族问题》（1913，署名科·斯大林，载《启蒙》杂志）。"
             "**D103 裁为节选**：保留民族的定义、民族运动与无产阶级斗争关系、"
             "「七 俄国的民族问题」；裁去前六节对奥地利社会民主党民族文化自治论的逐条驳斥细部。"
             "原文一字未改，边界均为章节标题行。"),
    dict(file="2-无政府主义还是社会主义.txt", work="无政府主义还是社会主义？", author="斯大林",
         prefix="CH-WZF-", slug="wzf",
         html=["stalin/mia-chinese-stalin-190606-07.html"],
         note="斯大林《无政府主义还是社会主义？》（1906-06—07）。**D103 裁为节选**："
             "保留「一 辩证方法」全节（辩证唯物主义原理的通俗系统表述）；"
             "裁去「二 唯物主义」中篇与「三 无产阶级社会主义」下篇及卷末注。"
             "原文一字未改，边界均为章节标题行。"),

    # —— 马克思 / 恩格斯各 1 篇 ——
    dict(file="2-1848年至1850年的法兰西阶级斗争.txt", work="1848年至1850年的法兰西阶级斗争",
         author="马克思", prefix="CH-FLGJ-", slug="flgj",
         html=["marx-engels2/02/04.html"],
         note="《马克思恩格斯文集》第 2 卷所收《1848 年至 1850 年的法兰西阶级斗争》。"
             "（恩格斯 1895 年导言是独立文献，不在本页，本库不收，避免与正篇混编。）"
             "**D103 裁为节选**：保留「一 1848 年的六月失败」与「四 1850 年普选权的废除」"
             "（含「革命死了！——革命万岁！」与革命社会主义宣言段）；裁去第二、三节事件经过细部"
             "与卷末注释。原文一字未改，边界均为章节标题行。"),
    dict(file="2-德国农民战争.txt", work="德国农民战争", author="恩格斯",
         prefix="CH-DGNS-", slug="dgns",
         html=["marx-engels2/02/06.html"],
         note="《马克思恩格斯文集》第 2 卷所收恩格斯《德国农民战争》（1850）。"
             "**D103 裁为节选**：保留恩格斯 1874 年序言与第一章「德国的情形」"
             "（唯物史观分析农民战争的阶级结构）；裁去中间各章战争史叙述与卷末注释。"
             "原文一字未改，边界均为章节标题行。"),

    # ========================================================================
    # D104：P0 + P1 批次（26 部，按合适章节节选，不整篇照录）
    # 用户口径（2026-11）：与 D103 相同 —— 只挑与路线章节对得上的章节入库，
    # 不整篇照录；裁剪见下方 TRIM，边界一律落在章节标题行，原文一字不改。
    # ========================================================================
    # —— P0-1 军事与策略：十大军事原则 ——
    dict(file="5-目前形势和我们的任务.txt", work="目前形势和我们的任务", author="毛泽东",
         prefix="CH-MQXS-", slug="mqxs",
         html=["maozedong/marxist.org-chinese-mao-19471225.html"],
         note="《毛泽东选集》第 4 卷所收《目前形势和我们的任务》（1947-12-25 杨家沟会议报告）"
              "全文，含题解与卷末注释。八节完整：第三条即「十大军事原则」，"
              "第六条讲「三大经济纲领」（没收官僚资本、平分土地、保护民族工商业）。"),
    # —— P0-2 历史唯物主义基石：劳动创造人 ——
    dict(file="3-劳动在从猿到人的转变中的作用.txt", work="劳动在从猿到人的转变中的作用",
         author="恩格斯", prefix="CH-LL-", slug="ll",
         html=["marx-engels-2/26/017.html"],
         note="《马恩全集》中文第 2 版第 26 卷《自然辩证法》［自然界和社会］所收"
              "《劳动在从猿到人的转变中的作用》全文（手稿残篇，止于「手稿到此中断」），"
              "含全集编者注。只剥掉卷名／篇名两行导航，正文与注释一字未改。"),
    # —— P0-3 过渡时期阶级分析 ——
    dict(file="1-无产阶级专政时代的经济和政治.txt", work="无产阶级专政时代的经济和政治",
         author="列宁", prefix="CH-ZZJJ-", slug="zzjj",
         html=["lenin-cworks/37/049.html"],
         note="《列宁全集》中文第 2 版第 37 卷所收《无产阶级专政时代的经济和政治》"
              "（1919-10-30）全文，含全集注释。社会主义与资本主义两条道路、五种经济成分、"
              "「阶级还存在、阶级斗争并未结束」的经典定性，是 C 路线过渡时期的总说明。"),
    # —— P0-4 民族与殖民地问题（国际战略）——
    dict(file="1-民族和殖民地问题提纲初稿.txt", work="民族和殖民地问题提纲初稿", author="列宁",
         prefix="CH-MZTG-", slug="mztg",
         html=["lenin/marxist.org-chinese-lenin-19200605.html"],
         note="列宁《民族和殖民地问题提纲初稿——为共产国际第二次代表大会草拟的》"
              "（1920-06-05）全文，取自「列宁选集」网页（按手稿刊印并据清样校订），含注释。"
              "压迫民族／被压迫民族的划分、殖民地革命必须由无产阶级政党领导、"
              "落后国家可以越过资本主义阶段——中国革命国际定位的直接理论来源。"),
    dict(file="1-民族和殖民地问题委员会的报告.txt", work="民族和殖民地问题委员会的报告",
         author="列宁", prefix="CH-MZBG-", slug="mzbg",
         html=["lenin/marxist.org-chinese-lenin-19200726.html"],
         note="列宁《民族和殖民地问题委员会的报告》（1920-07-26 共产国际二大）全文，含注释。"
              "与《提纲初稿》配套：交代委员会讨论中的修正与「一切民族解放运动都属资产阶级民主性质"
              "而非共产主义运动」的表述边界。"),
    # —— P0-5 思想战线 ——
    dict(file="1-论战斗唯物主义的意义.txt", work="论战斗唯物主义的意义", author="列宁",
         prefix="CH-ZDWM-", slug="zdwm",
         html=["lenin-cworks/43/004.html"],
         note="《列宁全集》中文第 2 版第 43 卷所收《论战斗唯物主义的意义》"
              "（1922-03-12）全文，含全集注释。共产党人与彻底唯物主义者联盟、"
              "无神论宣传、与自然科学家结成战斗联盟，是「思想工作总结」的方法论文献。"),
    # —— P0-6 农业社会主义改造经典 ——
    dict(file="3-法德农民问题.txt", work="法德农民问题", author="恩格斯",
         prefix="CH-FDNM-", slug="fdnm",
         html=["marx-engels/22/078.html"],
         note="《马恩全集》中文第 1 版第 22 卷所收恩格斯《法德农民问题》（1894-11）全文，"
              "含卷末注释。小农的两重性、合作社＋示范＋国家帮助的改造路径、"
              "「绝不以暴力剥夺小农」的原则——农业合作化理论的源头文本。"),
    # —— P0-7 老三篇（价值取向层）——
    dict(file="5-为人民服务.txt", work="为人民服务", author="毛泽东",
         prefix="CH-WRM-", slug="wrm",
         html=["maozedong/marxist.org-chinese-mao-19440908.html"],
         note="《毛泽东选集》第 3 卷所收《为人民服务》（1944-09-08 张思德追悼讲演）全文，"
              "含题解与卷末注释。"),
    dict(file="5-纪念白求恩.txt", work="纪念白求恩", author="毛泽东",
         prefix="CH-BQE-", slug="bqe",
         html=["maozedong/marxist.org-chinese-mao-19391221.html"],
         note="《毛泽东选集》第 2 卷所收《纪念白求恩》（1939-12-21）全文，含题解与注释。"),
    dict(file="5-愚公移山.txt", work="愚公移山", author="毛泽东",
         prefix="CH-YGYS-", slug="ygys",
         html=["maozedong/marxist.org-chinese-mao-19450611.html"],
         note="《毛泽东选集》第 3 卷所收《愚公移山》（1945-06-11 七大闭幕词）全文，"
              "含题解与卷末注释。"),

    # —— P1-1 反修正主义：理论战线 ——
    dict(file="1-马克思主义和修正主义.txt", work="马克思主义和修正主义", author="列宁",
         prefix="CH-MZXS-", slug="mzxs",
         html=["lenin-cworks/17/003.html"],
         note="《列宁全集》中文第 2 版第 17 卷所收《马克思主义和修正主义》"
              "（1908-04-03 以前）全文，含全集注释。修正主义在哲学、经济学、政治学三方面的"
              "完整定义，与《唯物主义和经验批判主义》互为表里。"),
    # —— P1-2 帝国主义与机会主义分裂 ——
    dict(file="1-帝国主义和社会主义运动中的分裂.txt", work="帝国主义和社会主义运动中的分裂",
         author="列宁", prefix="CH-DGFL-", slug="dgfl",
         html=["lenin-cworks/28/005.html"],
         note="《列宁全集》中文第 2 版第 28 卷所收《帝国主义和社会主义运动中的分裂》"
              "（1916-08 以前）全文，含全集注释。垄断高额利润→工人贵族→机会主义的社会经济根源，"
              "《帝国主义是资本主义的最高阶段》的政治补充。"),
    # —— P1-3 新经济政策：政治经济学说明 ——
    dict(file="1-十月革命四周年.txt", work="十月革命四周年", author="列宁",
         prefix="CH-SYSN-", slug="sysn",
         html=["lenin-cworks/42/045.html"],
         note="《列宁全集》中文第 2 版第 42 卷所收《十月革命四周年》（1921-10-14）全文，"
              "含全集注释。承认「直接过渡」失败、改用「改良主义式」办法的自我总结。"),
    dict(file="1-论黄金在目前和社会主义完全胜利后的作用.txt",
         work="论黄金在目前和在社会主义完全胜利后的作用", author="列宁",
         prefix="CH-LHJ-", slug="lhj",
         html=["lenin-cworks/42/062.html"],
         note="《列宁全集》中文第 2 版第 42 卷所收《论黄金在目前和在社会主义完全胜利后的"
              "作用》（1921-11-05）全文，含全集注释。「为了学会用革命办法退却」、"
              "国家资本主义与商业的提法，新经济政策最坦诚的理论交代。"),
    # —— P1-4 国家垄断资本主义（战时经济向社会主义过渡的物质前提）——
    dict(file="1-大难临头出路何在.txt", work="大难临头，出路何在？", author="列宁",
         prefix="CH-DNLT-", slug="dnlt",
         html=["lenin-cworks/32/027.html"],
         note="《列宁全集》中文第 2 版第 32 卷所收《大难临头，出路何在？》（1917-09）"
              "**节选**：保留题名、原书目录、饥荒逼近／政府不起作用／"
              "监督办法是众所周知和轻而易举的／银行国有化／辛迪加国有化／取消商业秘密／"
              "强迫参加联合组织／调节消费；裁去「政府破坏民主组织的工作」及其后的财政破产、"
              "革命民主派两节与卷末注释。原文一字未改，边界均为章节标题行。"),
    # —— P1-5 农业合作化（中国实践）——
    dict(file="5-关于农业合作化问题.txt", work="关于农业合作化问题", author="毛泽东",
         prefix="CH-NYHZ-", slug="nyhz",
         html=["maozedong/marxist.org-chinese-mao-19550731.html"],
         note="《毛泽东选集》第 5 卷所收《关于农业合作化问题》（1955-07-31 省市自治区"
              "党委书记会议报告）全文十二节，含题解与卷末注释。"),
    # —— P1-6 阶级分析范本（极短，直接可背）——
    dict(file="5-怎样分析农村阶级.txt", work="怎样分析农村阶级", author="毛泽东",
         prefix="CH-ZYFX-", slug="zyfx",
         html=["maozedong/marxist.org-chinese-mao-193310.html"],
         note="《毛泽东选集》第 1 卷所收《怎样分析农村阶级》（1933-10，中央工农民主政府"
              "划分农村阶级成分的标准）全文，含题解与注释。地主／富农／中农／贫农／工人"
              "五节的判定标准，一字可操作。"),
    # —— P1-7 战术原则 ——
    dict(file="5-集中优势兵力各个歼灭敌人.txt", work="集中优势兵力，各个歼灭敌人",
         author="毛泽东", prefix="CH-JZYS-", slug="jzys",
         html=["maozedong/marxist.org-chinese-mao-19460916.html"],
         note="《毛泽东选集》第 4 卷所收《集中优势兵力，各个歼灭敌人》（1946-09-16"
              "中央军委指示）全文，含题解与卷末注释。十大军事原则的战术版。"),
    # —— P1-8 统战与政策策略 ——
    dict(file="5-论政策.txt", work="论政策", author="毛泽东",
         prefix="CH-LZC-", slug="lzc",
         html=["maozedong/marxist.org-chinese-mao-19401225.html"],
         note="《毛泽东选集》第 2 卷所收《论政策》（1940-12-25 中共中央对党内指示）全文，"
              "含题解与卷末注释。「有理、有利、有节」与各项具体政策的分界。"),
    dict(file="5-目前抗日统一战线中的策略问题.txt", work="目前抗日统一战线中的策略问题",
         author="毛泽东", prefix="CH-KRTJ-", slug="krtj",
         html=["maozedong/marxist.org-chinese-mao-19400311.html"],
         note="《毛泽东选集》第 2 卷所收《目前抗日统一战线中的策略问题》"
              "（1940-03-11 延安高级干部会议报告提纲）全文，含题解与卷末注释。"
              "发展进步势力、争取中间势力、孤立顽固势力的完整表述。"),
    dict(file="5-将革命进行到底.txt", work="将革命进行到底", author="毛泽东",
         prefix="CH-JGM-", slug="jgm",
         html=["maozedong/marxist.org-chinese-mao-19481230.html"],
         note="《毛泽东选集》第 4 卷所收《将革命进行到底》（1949 年新年献词）全文，"
              "含题解与卷末注释。「农夫与蛇」比喻与革命彻底性的政治表述。"),
    # —— P1-9 文化／意识形态上层建筑 ——
    dict(file="5-在中国共产党全国宣传工作会议上的讲话.txt",
         work="在中国共产党全国宣传工作会议上的讲话", author="毛泽东",
         prefix="CH-XCGZ-", slug="xcgz",
         html=["maozedong/marxist.org-chinese-mao-19570312.html"],
         note="《毛泽东选集》第 5 卷所收《在中国共产党全国宣传工作会议上的讲话》"
              "（1957-03-12）全文，含卷末注释。知识分子改造、意识形态工作的方针与界限。"),
    dict(file="5-应当重视电影武训传的讨论.txt", work="应当重视电影《武训传》的讨论",
         author="毛泽东", prefix="CH-WXC-", slug="wxc",
         html=["maozedong/marxist.org-chinese-mao-19510520.html"],
         note="《毛泽东选集》第 5 卷所收《应当重视电影〈武训传〉的讨论》"
              "（1951-05-20 为《人民日报》写的社论节录）全文，含题解。"
              "用唯物史观评价历史人物与文艺作品的方法论示范。"),
    dict(file="5-大量吸收知识分子.txt", work="大量吸收知识分子", author="毛泽东",
         prefix="CH-ZSFZ-", slug="zsfz",
         html=["maozedong/marxist.org-chinese-mao-19391201.html"],
         note="《毛泽东选集》第 2 卷所收《大量吸收知识分子》（1939-12-01 中共中央决定）"
              "全文，含题解与卷末注释。知识分子政策与「没有知识分子的参加，革命的胜利是"
              "不可能的」的判断。"),
    # —— P1-10 两部马恩节选：政治经济学对象＋暴力论、辩证法专论 ——
    dict(file="3-反杜林论政治经济学篇.txt", work="反杜林论（政治经济学篇·节选）",
         author="恩格斯", prefix="CH-FDL2-", slug="fdl2",
         html=["marx-engels-2/26/004.html"],
         note="《马恩全集》中文第 2 版第 26 卷《反杜林论》第二编 政治经济学"
              "**节选**：保留「一 对象和方法」（政治经济学的对象与广义／狭义定义）、"
              "「二 暴力论」「三 暴力论（续）」「四 暴力论（续完）」；"
              "裁去价值论、简单劳动和复合劳动、资本和剩余价值、《批判史》论述各节与卷末注释。"
              "原文一字未改，边界均为章节标题行。与既有「反杜林论（哲学篇）」同版同卷。"),
    dict(file="3-自然辩证法辩证法作为科学.txt", work="自然辩证法（辩证法作为科学·节选）",
         author="恩格斯", prefix="CH-ZRB2-", slug="zrb2",
         html=["marx-engels-2/26/014.html"],
         note="《马恩全集》中文第 2 版第 26 卷《自然辩证法》［辩证法作为科学］"
              "**节选**：保留「辩证法」（辩证法的一般性质、三大规律的经典表述）与"
              "「偶然性和必然性」；裁去［札记和片断］其余条目与［认识］以下各篇及注释。"
              "原文一字未改，边界均为章节标题行。"),

    # ===== D105：帝国主义论三源头 + 资本论相对剩余价值三章 + 剩余价值理论 + 神圣家族 =====
    # —— 马恩全集第 26 卷（I）（III）：《剩余价值理论》（《资本论》第四卷）——
    dict(file="4-剩余价值理论节选.txt", work="剩余价值理论（节选）", author="马克思",
         prefix="CH-SYZ-", slug="syz",
         html=["marx-engels/26-1/001.html", "marx-engels/26-1/002.html",
               "marx-engels/26-1/004.html", "marx-engels/26-1/006.html",
               "marx-engels/26-1/021.html", "marx-engels/26-1/022.html",
               "marx-engels/26-3/040.html", "marx-engels/26-3/041.html",
               "marx-engels/26-3/042.html", "marx-engels/26-3/043.html",
               "marx-engels/26-3/044.html"],
         keep_titles=True, keep_first_title=True,
         note="《马恩全集》中文第 1 版第 26 卷（I）（III）《剩余价值理论》（即《资本论》第四卷）"
              "**节选**：第 I 分册保留题名页、[总的评论]、[第二章] 重农学派、"
              "[第四章] 关于生产劳动和非生产劳动的理论（全文）、资本的生产性／生产劳动、"
              "《资本论》第二部分计划草稿；第 III 分册保留「收入及其源泉。庸俗政治经济学」"
              "（三位一体公式与拜物教批判）；裁去斯密／李嘉图学派的其余考据章节、"
              "第 II 分册地租与费用价格诸章与各分册卷末注释。原文一字未改，"
              "只删未选文件；页面重复出现的「第二十六卷（I）」页头行按行删除。"),
    # —— 马恩全集第 2 卷：神圣家族 ——
    dict(file="1-神圣家族节选.txt", work="神圣家族（节选）", author="马克思、恩格斯",
         prefix="CH-SDJZ-", slug="sdjz",
         html=["marx-engels/02/001.html", "marx-engels/02/007.html",
               "marx-engels/02/010.html"],
         keep_titles=True, keep_first_title=True,
         note="《马恩全集》中文第 1 版第 2 卷《神圣家族，或对批判的批判所做的批判》"
              "**节选**：保留「序言」、「第六章 绝对的批判的批判或布鲁诺先生所体现的"
              "批判的批判」（含（ｄ）对法国唯物主义的批判的战斗——马克思唯物史观形成"
              "链上的一环）与「第九章 批判的末日的审判」；裁去第一至五、七、八章"
              "对鲍威尔兄弟、施里加《巴黎的秘密》的逐节批判与卷末注释。原文一字未改。"),
    # —— 卢森堡《资本积累论》（三联书店 1959 年版，彭尘舜／吴纪先译）——
    dict(file="1-资本积累论节选.txt", work="资本积累论（节选）", author="罗莎·卢森堡",
         prefix="CH-ZBJL-", slug="zbjl",
         html=["rosa-luxemburg/1913/00.html"]
              + [f"rosa-luxemburg/1913/{i:02d}.html" for i in range(1, 10)]
              + [f"rosa-luxemburg/1913/{i}.html" for i in range(25, 33)],
         keep_titles=True, keep_first_title=True,
         note="罗莎·卢森堡《资本积累论》（1913）**节选**，据「中文马克思主义文库」转录的"
              "生活·读书·新知三联书店 1959 年版（彭尘舜、吴纪先译）：保留「原序」、"
              "第一编 再生产问题（第一至九章：对马克思简单／扩大再生产图式的分析与批评）"
              "与第三编 积累的历史诸条件（第二十五至三十二章：资本主义与非资本主义环境的"
              "关系、国际借款、保护关税、军国主义）；裁去第二编「本问题的历史发展」"
              "（第十至二十四章西斯蒙第、洛贝尔图、俄国「合法马克思主义」论战史）与译后记。"
              "原文一字未改，只删未选章节。"),
    # —— 布哈林《世界经济与帝国主义》（1917，列宁作序）——
    dict(file="1-世界经济与帝国主义.txt", work="世界经济与帝国主义", author="布哈林",
         prefix="CH-SJJJ-", slug="sjjj",
         html=["bukharin/1917/00a.html", "bukharin/1917/00b.html"]
              + [f"bukharin/1917/{i:02d}.html" for i in range(1, 16)],
         keep_titles=True, keep_first_title=True,
         note="布哈林《世界经济与帝国主义》（1917，通译《世界经济和帝国主义》）全文，"
              "据「中文马克思主义文库」转录本：列宁序、作者序、四篇十五章俱全"
              "（世界经济的涵义与发展／资本国际化／资本民族化与关税、原料、资本输出／"
              "帝国主义是扩大的再生产／竞争手段与国家政权／「超帝国主义」论批判／"
              "战争的经济进化／世界经济与无产阶级社会主义／结论），含卷末注释。"
              "原文一字未改。"),
    # —— 希法亭《金融资本》（商务印书馆 1994 年版，福民等译）——
    dict(file="1-金融资本节选.txt", work="金融资本（节选）", author="鲁道夫·希法亭",
         prefix="CH-JRZB-", slug="jrzb",
         html=["reference-books/rudolf-hilferding-1910/00.html"]
              + [f"reference-books/rudolf-hilferding-1910/{x}.html"
                 for x in ("05", "06", "07", "10", "12", "14", "15",
                           "22", "23", "25")],
         keep_titles=True, keep_first_title=True,
         note="鲁道夫·希法亭《金融资本——资本主义最新发展的研究》（1910）**节选**，"
              "据「中文马克思主义文库·参考图书」转录的商务印书馆 1994 年版（福民等译）："
              "保留「前言」、第五章 银行和产业信用、第六章 利息率、第七章 股份公司"
              "（第二篇 资本的动员。虚拟资本）、第十章 银行资本和银行利润、"
              "第十二章 卡特尔和托拉斯、第十四章 资本向金融资本的转化、"
              "第十五章 资本主义垄断的价格决定。金融资本的历史趋势、"
              "第二十二章 资本输出和争取经济区的斗争、第二十三章 金融资本和各阶级、"
              "第二十五章 无产阶级和帝国主义；裁去货币信用理论前四章、证券交易所／商品"
              "交易所、利润率平均化、危机四章与商业政策一章。原文一字未改，只删未选章节。"),
    # —— 马克思《关于费尔巴哈的提纲》（马恩全集中文第 1 版第 3 卷）——
    # 学习路线 sec_A_02「马克思本人登场：实践与新唯物主义」长期缺原文：
    # 该节 12 个知识点的 source_chunk_id 是历史占位符（CH-ME-TH-01-1 等），
    # 15 道题的溯源全部锚在导读（GUIDE-sec_A_02）。本批补入权威中译全文。
    dict(file="0-关于费尔巴哈的提纲.txt", work="关于费尔巴哈的提纲", author="马克思",
         prefix="CH-MLTH-", slug="mlth",
         html=["marx-engels/03/001.html"],
         note="马克思《关于费尔巴哈的提纲》，据「中文马克思主义文库」转录的"
              "《马克思恩格斯全集》中文第 1 版第 3 卷（人民出版社 1960 年版）："
              "含（1）恩格斯于 1888 年作为《费尔巴哈和德国古典哲学的终结》单行本"
              "附录首次发表的定本十一条，（2）全集编者附译的 1845 年手稿本（标题"
              "「关于费尔巴哈」）十一条，（3）写作与发表版记，（4）卷末注释〔1〕。"
              "全文照录，未作节选——本篇极短且是学习路线地基章节的唯一原文依据。"
              "着重点（原文黑体／斜体）在转写中表现为该词两侧空格，与库内既有"
              "同类转写（《论权威》《在马克思墓前的讲话》等）口径一致。"),
    # ===== D116：组织领导 / 群众路线谱系补环（3 篇毛泽东 + 2 篇刘少奇）=====
    # 立项依据：B 路线「组织领导（sec_B_04）」与「调查研究（sec_B_05）」两章
    # 缺三块原始文本 ——(1) 群众路线的奠基篇（1934 关心群众生活）、(2) 调查研究
    # 的自述篇（1941 《农村调查》序言和跋）、(3) 库内零本刘少奇（白区党群工作线）。
    # 红线核对：均为《毛泽东选集》《刘少奇选集》官版收录篇目，可溯源、无黑名单
    # 组织来源、不属批判对象；镜像版本带原书注释（可核对出处）。
    dict(file="5-关心群众生活注意工作方法.txt", work="关心群众生活，注意工作方法",
         author="毛泽东", prefix="CH-GXXZ-", slug="gxxz",
         html=["maozedong/marxist.org-chinese-mao-19340127.html"],
         note="毛泽东《关心群众生活，注意工作方法》（1934 年 1 月 27 日，第二次全国工农兵"
              "代表大会结论的一部分），据「中文马克思主义文库」转录的《毛泽东选集》第 1 卷"
              "（人民出版社 1991 年第 2 版）版本：保留题注、两个问题的全部正文；"
              "裁去卷末 6 条注释。原文一字未改。"),
    dict(file="5-农村调查的序言和跋.txt", work="《农村调查》的序言和跋",
         author="毛泽东", prefix="CH-NCDC-", slug="ncdc",
         html=["maozedong/marxist.org-chinese-mao-194134.html"],
         note="毛泽东《〈农村调查〉的序言和跋》（1941 年 3 月 17 日序、4 月 19 日跋），"
              "据「中文马克思主义文库」转录的《毛泽东选集》第 3 卷（人民出版社 1991 年"
              "第 2 版）版本：保留序与跋的全部正文；裁去卷末 6 条注释。原文一字未改。"),
    dict(file="5-组织起来.txt", work="组织起来", author="毛泽东",
         prefix="CH-ZZQL-", slug="zzql",
         html=["maozedong/marxist.org-chinese-mao-19431129.html"],
         note="毛泽东《组织起来》（1943 年 11 月 29 日在中共中央招待陕甘宁边区劳动英雄"
              "大会上的讲话），据「中文马克思主义文库」转录的《毛泽东选集》第 3 卷"
              "（人民出版社 1991 年第 2 版）版本：保留题注与全部正文；裁去卷末 5 条注释。"
              "原文一字未改。"),
    dict(file="1-关于白区的党和群众工作.txt", work="关于白区的党和群众工作",
         author="刘少奇", prefix="CH-BQDH-", slug="bqdh",
         html=["liushaoqi/marxist.org-chinese-lsq-193705.html"],
         note="刘少奇《关于白区的党和群众工作》（1937 年 5 月在延安举行的白区党代表会议上的"
              "报告），据「中文马克思主义文库」转录的《刘少奇选集》上卷（人民出版社 1981 年"
              "版）版本：《选集》本身只收入原报告十一部分中的四部分，本库再节选其中"
              "「党和群众的关系」「公开工作和秘密工作的联系」「党的转变」前四节（至"
              "『干部问题』小节之前）；裁去「彻底的转变」（1935—1937 年政策背景）一节、"
              "「党的转变」后五节与卷末 4 条注释。原文一字未改，只删未选章节。"),
    dict(file="1-怎样进行群众工作.txt", work="怎样进行群众工作", author="刘少奇",
         prefix="CH-ZYQZ-", slug="zyqz",
         html=["liushaoqi/marxist.org-chinese-lsq-19361015.html"],
         note="刘少奇《怎样进行群众工作——给群众工作的同志们一封信》（1936 年 10 月 15 日），"
              "据「中文马克思主义文库」转录的《刘少奇选集》上卷（人民出版社 1981 年版）版本："
              "保留开篇「创造条件」部分与（一）党与群众组织的关系、（二）民主的工作方式、"
              "（三）公开与半公开的工作方式、（四）公开干部与党团四节；裁去（五）群众团体"
              "的不同性质、（六）抗日救国人民阵线与结尾口号，以及卷末注释。"
              "原文一字未改，只删未选章节。"),
    # ===== D117：工人运动谱系补环（2 部）=====
    # 立项依据：库内「工会／职工运动／罢工」一条线全是 0 部——只在教科书叙述与
    # 《矛盾论》注释里被顺带提到，于是 `sec_B_01`（建党原则）只讲欧洲建党、
    # `sec_B_04`（组织领导）只讲党对群众的领导，没有「党在工人中怎么建组织」的原文。
    # 红线核对：邓中夏系中共早期领导人、烈士，该书写于 1930 年莫斯科，1949 年后
    # 人民出版社／工人出版社多次重印，属党内自述史学著作；刘少奇《工人阶级在革命中
    # 的地位与职工运动方针》收《刘少奇选集》上卷，均为官版谱系，不命中黑名单。
    dict(file="1-中国职工运动简史节选.txt", work="中国职工运动简史（1919—1926）节选",
         author="邓中夏", prefix="CH-ZGYD-", slug="zgyd",
         keep_titles=True, keep_first_title=True,
         html=["dengzhongxia/1930book/marxist.org-chinese-gong-1930a.html"]
              + [f"dengzhongxia/1930book/marxist.org-chinese-gong-1930-{i}.html"
                 for i in range(1, 14)],
         note="邓中夏《中国职工运动简史（1919—1926）》据「中文马克思主义文库」转录全书"
              "（1930 年 6 月著于莫斯科，著者申明＋十三章）：本库只收与学习路线对得上的"
              "三章——第五章「第一次全国劳动大会及劳动立法运动」（党以中国劳动组合"
              "书记部名义召集全国劳动大会、劳动立法运动）、第七章「京汉路大罢工——"
              "“二七”惨杀」（罢工经过与「没有一个强大的共产党」的教训）、第九章"
              "「职工运动复兴期」；并保留著者申明（作者自述本书只成上卷）。"
              "裁去第一至四章、第六章、第八、十至十三章及全书目录页；"
              "原文一字未改，只删未选章节。"),
    dict(file="1-工人阶级在革命中的地位与职工运动方针.txt",
         work="工人阶级在革命中的地位与职工运动方针", author="刘少奇",
         prefix="CH-GRJD-", slug="grjd",
         html=["liushaoqi/marxist.org-chinese-lsq-192605.html"],
         note="刘少奇《工人阶级在革命中的地位与职工运动方针》（1926 年 5 月，"
              "在第三次全国劳动大会上的报告），据「中文马克思主义文库」转录的"
              "《刘少奇选集》上卷（人民出版社 1981 年版）版本：全文照录（十节），"
              "未作节选；镜像页无卷末注释。"),

    # ===== D118：建党前史（1919—1924）——李大钊 6 篇 + 蔡和森 2 篇 =====
    # 立项依据：D117 之后库内最早的中文文献仍是 1925 年《中国社会各阶级的分析》，
    # 1918—1924 这段「马克思主义怎样进入中国、党怎样从讨论组变成组织」完全空白；
    # `sec_A_06`（共产党宣言入门）、`sec_A_07`（唯物史观创立）、`sec_B_01`（建党原则）
    # 三章只能讲欧洲源头，讲不到中国这一环。本批只取可溯源到原刊（篇末带原刊名、
    # 卷期、署名）的篇目，不做二手转述、不拼凑。
    # 红线核对：李大钊（1927 年遇难）、蔡和森（1931 年遇难）均为党史正面人物，
    # 所选篇目均为马克思主义在中国传播与建党的正面文献，不命中黑名单四条，
    # 不涉路线斗争叙事。
    dict(file="1-法俄革命之比较观.txt", work="法俄革命之比较观", author="李大钊",
         prefix="CH-FLG-", slug="flg",
         html=["lidazhao/marxist.org-chinese-lee-19180701.html"],
         note="李大钊《法俄革命之比较观》（1918 年 7 月 1 日，载《言治》季刊第 3 册，"
              "署名李大钊），据「中文马克思主义文库」转录：全文照录，未作节选，"
              "篇末原刊出处、署名与两条译注均保留。"),
    dict(file="1-庶民的胜利.txt", work="庶民的胜利", author="李大钊",
         prefix="CH-SMD-", slug="smd",
         html=["lidazhao/marxist.org-chinese-lee-19181015.html"],
         note="李大钊《庶民的胜利》（1918 年 10 月 15 日，载《新青年》第 5 卷第 5 号，"
              "署名守常），据「中文马克思主义文库」转录：全文照录，未作节选，"
              "篇末原刊出处与署名保留。"),
    dict(file="1-Bolshevism的胜利.txt", work="Bolshevism的胜利", author="李大钊",
         prefix="CH-BLS-", slug="bls",
         html=["lidazhao/marxist.org-chinese-lee-19181015A.html"],
         note="李大钊《Bolshevism 的胜利》（1918 年 10 月 15 日，载《新青年》第 5 卷"
              "第 5 号，署名李大钊），据「中文马克思主义文库」转录：全文照录，"
              "未作节选，篇末原刊出处与署名保留；文中人名译法与 1918 年原文一致。"),
    dict(file="1-再论问题与主义.txt", work="再论问题与主义", author="李大钊",
         prefix="CH-ZLWT-", slug="zlwt",
         html=["lidazhao/marxist.org-chinese-lee-19190817.html"],
         note="李大钊《再论问题与主义》（1919 年 8 月 17 日，致胡适的信，"
              "载《每周评论》第 35 号），据「中文马克思主义文库」转录：全文照录，"
              "未作节选（四节俱全），篇末写作地点、日期与原刊出处保留。"),
    dict(file="1-由经济上解释中国近代思想变动的原因.txt",
         work="由经济上解释中国近代思想变动的原因", author="李大钊",
         prefix="CH-JJBD-", slug="jjbd",
         html=["lidazhao/marxist.org-chinese-lee-19200101.html"],
         note="李大钊《由经济上解释中国近代思想变动的原因》（1920 年 1 月 1 日，"
              "载《新青年》第 7 卷第 2 号，署名李大钊），据「中文马克思主义文库」转录："
              "全文照录，未作节选，篇末原刊出处与署名保留。"),
    dict(file="1-唯物史观在现代史学上的价值.txt",
         work="唯物史观在现代史学上的价值", author="李大钊",
         prefix="CH-WWSG-", slug="wwsg",
         html=["lidazhao/02.html"],
         note="李大钊《唯物史观在现代史学上的价值》（1920 年 12 月 1 日，"
              "载《新青年》第 8 卷第 4 号），据「中文马克思主义文库」转录："
              "全文照录，未作节选，篇末原刊出处保留。"),
    dict(file="1-马克思学说与中国无产阶级.txt", work="马克思学说与中国无产阶级",
         author="蔡和森", prefix="CH-CMZS-", slug="cmzs",
         html=["caihesen/mia-chinese-chs-19210211.html"],
         note="蔡和森《马克思学说与中国无产阶级》（1921 年 2 月 11 日致陈独秀的信，"
              "写于法国蒙达尼，原载 1921 年 8 月 1 日《新青年》第 9 卷第 4 号），"
              "据「中文马克思主义文库」转录：全文照录，未作节选，篇末写作地点、"
              "日期与原刊出处保留。"),
    dict(file="1-关于中国共产党的组织和党内生活向共产国际的报告.txt",
         work="关于中国共产党的组织和党内生活向共产国际的报告（部分）",
         author="蔡和森", prefix="CH-CDBG-", slug="cdbg",
         html=["caihesen/mia-chinese-chs-19260210.html"],
         note="蔡和森《关于中国共产党的组织和党内生活向共产国际的报告》"
              "（1926 年 2 月 10 日）：据「中文马克思主义文库」转录。"
              "原报告六万余字，1987 年《中央档案馆丛刊》第 2、3 期分期刊出；"
              "镜像所据为第 3 期（第二部分，一万一千余字），并把中共党史出版社"
              "2004 年版《中国共产党第四次全国代表大会》摘录本中有、而第二部分"
              "所无的内容另编为「第一部分（摘）」。本库按镜像转录全文照录"
              "（含该页「说明」与 24 条译注），未作节选；报告属残本这一层已在"
              "正文「说明」里如实保留。"),
    # ===== D119：建党文献原文（1920—1925）——《中共中央文件选集》第一册 =====
    # 立项依据：D118 补了「建党前史」的个人著述（李大钊、蔡和森），但库里没有一份
    # 党的**本体文件**——纲领、决议、章程、组织问题议决案全缺，`sec_B_01`（建党原则）
    # 与 `sec_B_04`（组织工作）只能讲列宁的党、讲不到中国党自己的组织构造。
    # 书源：D 盘镜像 `reference-books/ccp-1921-1949/01/`，即中央档案馆编
    # 《中共中央文件选集》第一册（中共中央党校出版社 1989 年版）的录入文本，
    # 每篇篇末都带「根据一九二二年七月印行的《中国共产党第二次全国大会决议案》刊印」
    # 一类的刊印依据，可逐篇溯源到原始版本。
    # 口径：10 篇全部**全文照录**（含页内「说明」「注释」与卷末注文），不设节选、
    # 不留裁剪备份、不改一字；标题行后站点加的 `[1]` 上标是网页脚注锚（对应篇末注释
    # 首条），按原样保留，不做增删。
    # 红线核对：本批为 1920—1925 年党的公开文件与中央通告，是党史正面文献，
    # 不命中 `READING_BLACKLIST` 四条；不属于第 6 阶段批判对象，不作路线斗争叙事。
    dict(file="1-中国共产党第一个纲领.txt", work="中国共产党第一个纲领",
         author="中国共产党第一次全国代表大会", prefix="CH-DYGL-", slug="dygl",
         html=["reference-books/ccp-1921-1949/01/001.html"],
         note="《中国共产党第一个纲领》（一九二一年七月，中国共产党第一次全国代表大会"
              "文件），据「中文马克思主义文库」转录的《中共中央文件选集》第一册"
              "（中央档案馆编，中共中央党校出版社）版本：全文照录（十五条），"
              "未作节选；篇末「译自中共驻共产国际代表团档案的俄文稿」一行与 6 条注释"
              "（对照英文稿的异文说明）均按原样保留。"),
    dict(file="1-中国共产党第一个决议.txt", work="中国共产党第一个决议",
         author="中国共产党第一次全国代表大会", prefix="CH-DYJY-", slug="dyjy",
         html=["reference-books/ccp-1921-1949/01/002.html"],
         note="《中国共产党第一个决议》（一九二一年七月，中国共产党第一次全国代表大会"
              "文件），据「中文马克思主义文库」转录的《中共中央文件选集》第一册版本："
              "全文照录（六节：工人组织、宣传、工人学校、工会组织的研究机构、对现有"
              "政党的态度、党与第三国际的联系），未作节选；篇末来源行与 4 条注释保留。"),
    dict(file="1-中国共产党宣言.txt", work="中国共产党宣言",
         author="中国共产党上海发起组", prefix="CH-ZGCD-", slug="zgcd",
         html=["reference-books/ccp-1921-1949/01/124.html"],
         note="《中国共产党宣言》（一九二〇年十一月，上海共产党早期组织起草），"
              "据「中文马克思主义文库」转录的《中共中央文件选集》第一册版本："
              "全文照录（共产主义者的理想、共产主义者的目的、阶级斗争的最近状态"
              "三部分），未作节选；篇首说明（含「这宣言之中文原稿不能在此地找到，"
              "所以兄弟把他从英文稿翻译出来」一段）、一九二一年十二月十日张国焘的"
              "英文签字与篇末 3 条注释均保留。此件是中国共产党最早的纲领性文件。"),
    dict(file="1-中国共产党章程.txt", work="中国共产党章程",
         author="中国共产党第二次全国代表大会", prefix="CH-DZZC-", slug="dzzc",
         html=["reference-books/ccp-1921-1949/01/018.html"],
         note="《中国共产党章程》（一九二二年七月，中国共产党第二次全国代表大会"
              "文件），据「中文马克思主义文库」转录的《中共中央文件选集》第一册版本："
              "全文照录（六章二十九条：党员、组织、会议、纪律、经费、附则），"
              "未作节选；篇末「根据一九二二年七月印行的《中国共产党第二次全国大会"
              "决议案》刊印」一行保留。"),
    dict(file="1-关于共产党的组织章程决议案.txt",
         work="关于共产党的组织章程决议案",
         author="中国共产党第二次全国代表大会", prefix="CH-ZZZC-", slug="zzzc",
         html=["reference-books/ccp-1921-1949/01/017.html"],
         note="《关于共产党的组织章程决议案》（一九二二年七月，中国共产党第二次"
              "全国代表大会文件），据「中文马克思主义文库」转录的《中共中央文件选集》"
              "第一册版本：全文照录，未作节选；篇末刊印依据一行保留。"
              "该决议案是「中国共产党是无产阶级的先锋军、是实行革命的群众党」"
              "这一组织定性最早的正式表述。"),
    dict(file="1-关于民主的联合战线的议决案.txt",
         work="关于“民主的联合战线”的议决案",
         author="中国共产党第二次全国代表大会", prefix="CH-LHZX-", slug="lhzx",
         html=["reference-books/ccp-1921-1949/01/011.html"],
         note="《关于「民主的联合战线」的议决案》（一九二二年七月，中国共产党第二次"
              "全国代表大会文件），据「中文马克思主义文库」转录的《中共中央文件选集》"
              "第一册版本：全文照录，未作节选；篇末刊印依据一行保留。"
              "文件名里的引号按通行排印方式写作「民主的联合战线」，未加书名号。"),
    dict(file="1-关于妇女运动的决议.txt", work="关于妇女运动的决议",
         author="中国共产党第二次全国代表大会", prefix="CH-FNYD-", slug="fnyd",
         html=["reference-books/ccp-1921-1949/01/016.html"],
         note="《关于妇女运动的决议》（一九二二年七月，中国共产党第二次全国代表大会"
              "文件），据「中文马克思主义文库」转录的《中共中央文件选集》第一册版本："
              "全文照录，未作节选；篇末刊印依据一行保留。这是中国共产党第一个"
              "关于妇女运动的正式决议。"),
    dict(file="1-中国共产党第二次全国大会宣言.txt",
         work="中国共产党第二次全国大会宣言",
         author="中国共产党第二次全国代表大会", prefix="CH-EDXY-", slug="edxy",
         html=["reference-books/ccp-1921-1949/01/019.html"],
         note="《中国共产党第二次全国大会宣言》（一九二二年七月），据「中文马克思主义"
              "文库」转录的《中共中央文件选集》第一册版本：全文照录（三部分：国际"
              "帝国主义宰制下之中国、中国政治经济现状与受压迫的劳苦群众、中国共产党的"
              "任务及其目前的奋斗），未作节选；篇末署名日期、"
              "「根据一九二六年印行的《中国共产党五年来之政治主张》刊印」来源行与"
              "3 条注释保留。首次提出反帝反封建的民主革命纲领（最低纲领）。"),
    dict(file="1-党内组织及宣传教育问题议决案.txt",
         work="党内组织及宣传教育问题议决案",
         author="中共中央执行委员会扩大会议", prefix="CH-DNZJ-", slug="dnzj",
         html=["reference-books/ccp-1921-1949/01/050.html"],
         note="《党内组织及宣传教育问题议决案》（一九二四年五月，中共中央执行委员会"
              "扩大会议文件），据「中文马克思主义文库」转录的《中共中央文件选集》"
              "第一册版本：全文照录，未作节选；篇末「根据一九二四年五月二十日出版的"
              "《中国共产党党报》第三号刊印」一行保留。"),
    dict(file="1-对于组织问题之议决案.txt", work="对于组织问题之议决案",
         author="中国共产党第四次全国代表大会", prefix="CH-ZZWT-", slug="zzwt",
         html=["reference-books/ccp-1921-1949/01/078.html"],
         note="《对于组织问题之议决案》（一九二五年一月，中国共产党第四次全国代表大会"
              "文件），据「中文马克思主义文库」转录的《中共中央文件选集》第一册版本："
              "全文照录，未作节选；篇末「根据一九二五年二月印行的《中国共产党第四次"
              "全国大会议决案及宣言》刊印」一行保留。"),

    # ===== D120：周恩来建国后文献 6 篇（《周恩来选集》下卷体系） =====
    # 立项依据：库里已有周恩来 7 篇（`CH-HLDZ-`/`CH-FGL-`/`CH-BSKB-`/`CH-XYYZ-`/
    # `CH-JQDC-`/`CH-LD-`/`CH-SZH-`），全部挂 `sec_B_04`，且以 1920—40 年代与
    # 1960 年代初的组织/作风文献为主。建国后那批「政权形态、知识分子、文艺」
    # 的一手文献仍是空的：`sec_C_03`（论人民民主专政）只有 2 条延伸阅读，
    # `sec_C_06`（国家的起源）3 条，`sec_C_07`（上层建筑与文艺）缺 1960 年代
    # 文艺政策的第一手讲话。
    # 书源：镜像 `zhouenlai/`（《周恩来选集》下卷录入文本），每篇篇末带
    # 「＊这是……」的选集编者说明（会议、日期、节录情况），可逐篇溯源。
    # 口径：6 篇**全文照录**（含 [NNN] 注释锚与篇末编者说明），不设节选、不改一字。
    dict(file="1-专政要继续民主要扩大.txt", work="专政要继续，民主要扩大", author="周恩来",
         prefix="CH-ZYMS-", slug="zyms", html=["zhouenlai/122.html"],
         note="周恩来《专政要继续，民主要扩大》（一九五六年七月二十一日），据「中文马克思主义文库」"
              "转录的《周恩来选集》下卷版本：全文照录，未作节选；篇末「＊这是在中国共产党"
              "上海市第一次代表大会上的讲话节录」一行保留。"),
    dict(file="1-关于知识分子问题的报告.txt", work="关于知识分子问题的报告", author="周恩来",
         prefix="CH-ZSFT-", slug="zsft", html=["zhouenlai/119.html"],
         note="周恩来《关于知识分子问题的报告》（一九五六年一月十四日），据「中文马克思主义文库」"
              "转录的《周恩来选集》下卷版本：全文照录，未作节选；[NNN] 形式的注释锚与"
              "篇末编者说明保留。报告首次作出「知识分子的绝大部分已经成为国家工作人员、"
              "已经为社会主义服务」的判断，并提出「向现代科学进军」。"),
    dict(file="1-论知识分子问题.txt", work="论知识分子问题", author="周恩来",
         prefix="CH-LZSF-", slug="lzsf", html=["zhouenlai/136.html"],
         note="周恩来《论知识分子问题》（一九六二年三月二日），据「中文马克思主义文库」"
              "转录的《周恩来选集》下卷版本：全文照录，未作节选；篇末「＊这是对在广州召开的"
              "全国科学工作、戏剧创作等会议代表的讲话」说明保留。与一九五六年报告构成"
              "知识分子阶级属性判断的两次表述。"),
    dict(file="1-在文艺工作座谈会和故事片创作会议上的讲话.txt",
         work="在文艺工作座谈会和故事片创作会议上的讲话", author="周恩来",
         prefix="CH-WYZT-", slug="wyzt", html=["zhouenlai/134.html"],
         note="周恩来《在文艺工作座谈会和故事片创作会议上的讲话》（一九六一年六月十九日），"
              "据「中文马克思主义文库」转录的《周恩来选集》下卷版本：全文照录（引言＋"
              "物质生产与精神生产、阶级斗争与统一战线、为谁服务、文艺规律、遗产与创造、"
              "领导、话剧问题七节），未作节选；文中 [NNN] 注释锚保留。"),
    dict(file="1-学习毛泽东.txt", work="学习毛泽东", author="周恩来",
         prefix="CH-XXMZ-", slug="xxmzd", html=["zhouenlai/057.html"],
         note="周恩来《学习毛泽东》（一九四九年五月七日），据「中文马克思主义文库」转录的"
              "《周恩来选集》上卷版本：本文为该报告第三部分的节录（选集编者说明已写明），"
              "本库按镜像照录该节录全文，未再作裁剪；篇末「＊这是在中华全国青年第一次"
              "代表大会上的报告第三部分的节录」说明保留。"),
    dict(file="1-切实执行婚姻法保护妇女合法权益.txt",
         work="切实执行婚姻法，保护妇女合法权益", author="周恩来",
         prefix="CH-HYF-", slug="hyf", html=["zhouenlai/106.html"],
         note="周恩来《切实执行婚姻法，保护妇女合法权益》（一九五一年九月二十六日），"
              "据「中文马克思主义文库」转录的《周恩来选集》下卷版本：全文照录，未作节选；"
              "与一九二二年《关于妇女运动的决议》构成「纲领文件→政权实践」的一条线。"),

    # ------------------------------------------------------------------
    # D121：普列汉诺夫前期（1883—1903 马克思主义时期）哲学著作 2 篇。
    # 只收前期：1903 年二大后转孟什维克、一战护国主义、1917 年反对十月革命
    # 那条线的文字一律不入；《在祖国的一年》永为争议版本。
    # 书源：镜像 `plekhanov/`，两篇的篇首/篇末都自带中译版本说明（见各条 note），
    # 这一批唯一按「篇首版本说明」溯源，而不是按篇末编者附记溯源的。
    # 口径：全文照录，不设 TRIM、不改一字；注释锚与译者注原样保留。
    dict(file="1-个人在历史上的作用问题.txt", work="个人在历史上的作用问题",
         author="普列汉诺夫", prefix="CH-GRZY-", slug="grzy",
         html=["plekhanov/marxist.org-chinese-Plekhanov-1898.html"],
         drop_leading=("普列汉诺夫", "个人在历史上的作用问题"),
         note="普列汉诺夫《个人在历史上的作用问题》（1898），据「中文马克思主义文库」转录的"
              "中央编译出版社《普列汉诺夫读本》重新编译本（该本以《普列汉诺夫哲学著作选集》"
              "所录版本为底本）：全文照录，未作节选；篇首「按：本文以基尔桑诺夫为笔名发表在……"
              "《科学评论》杂志1898年第3、4期上」一段与篇末「说明：本文为中央编译出版社……"
              "重新编译的版本」一段均保留，尾注为普列汉诺夫原注、①②③与[五][六][七]为编译者所加。"),
    dict(file="1-奥古斯丹·梯叶里和唯物史观.txt", work="奥古斯丹·梯叶里和唯物史观",
         author="普列汉诺夫", prefix="CH-TYL-", slug="tyl",
         html=["plekhanov/mia-chinese-plekhanov-189511.html"],
         drop_leading=("奥古斯丹·梯叶里和唯物史观",),
         note="普列汉诺夫《奥古斯丹·梯叶里和唯物史观》（1895年11月，王荫庭译），据「中文马克思主义"
              "文库」转录：篇首「原文登载在1895年11月《社会变化》杂志上，收录于《格·瓦·普列汉诺夫"
              "全集》俄文第2版第8卷第9—25页。中译文来自《马列主义研究资料》1982年第2辑」一行保留；"
              "全文照录，未作节选，[NN] 注释为译者原注。"),

    # ------------------------------------------------------------------
    # D122：妇女运动文献 13 篇——向警予 8 篇 + 党的三大/四大妇女决议 2 篇
    # + 蔡特金 3 篇。
    # 选篇口径：只收「妇女解放与劳动解放」这条马列主义主线上的文献；
    # 柯伦泰整批不收（中译全是当代志愿者从俄文/英文新译，无一份可溯源到
    # 正式中文出版物；且《工人反对派》《给有翼的爱若斯让路吧》属被列宁
    # 批判的路线与思潮）。蔡特金《罗莎·卢森堡对俄国革命的态度》亦不收
    # （为卢森堡对俄国革命的批评辩护，涉重大政治争议）。
    # 书源：镜像 `xiangjingyu/`（1920—1925 原刊文字，篇末带「载《向导》第X期」
    # 「载《妇女周报》第X号」等原刊出处）、`clara-zetkin/`（1950—60 年代中译）。
    # 口径：13 篇全文照录，不设 TRIM、不改一字；原刊出处行、译注一律保留。
    dict(file="1-女子解放与改造的商榷.txt", work="女子解放与改造的商榷", author="向警予",
         prefix="CH-NJSF-", slug="njsf",
         html=["xiangjingyu/mia-chinese-xjy-19200526.html"],
         note="向警予《女子解放与改造的商榷》（1920年5月26日于巴黎），据「中文马克思主义文库」"
              "转录的《少年中国》1920年第二卷第二期原文：全文照录，未作节选；篇末「一九二○年"
              "五月二十六日巴黎」与「载《少年中国》1920年第二卷第二期」两行保留。"),
    dict(file="1-留法女生对海外大学之要求.txt", work="留法女生对海外大学之要求", author="向警予",
         prefix="CH-LFNS-", slug="lfns",
         html=["xiangjingyu/mia-chinese-xjy-19210530.html"],
         note="向警予《留法女生对海外大学之要求》（1921年5月30日），据「中文马克思主义文库」转录的"
              "湖南《大公报》1921年7月20—26日原文：全文照录，未作节选；篇末刊载出处行保留。"),
    dict(file="1-中国知识妇女的三派.txt", work="中国知识妇女的三派", author="向警予",
         prefix="CH-ZSSP-", slug="zssp",
         html=["xiangjingyu/mia-chinese-xjy-19231128.html"],
         note="向警予《中国知识妇女的三派》（1923年11月28日），据「中文马克思主义文库」转录的"
              "《妇女周报》第十五号原文：全文照录，未作节选；篇末刊载出处行保留。"),
    dict(file="1-对于万国女权同盟大会的感想.txt", work="对于万国女权同盟大会的感想", author="向警予",
         prefix="CH-WGNQ-", slug="wgnq",
         html=["xiangjingyu/mia-chinese-xjy-19231201.html"],
         note="向警予《对于万国女权同盟大会的感想》（1923年12月1日），据「中文马克思主义文库」"
              "转录的《前锋》第二期原文：全文照录，未作节选；篇末「载《前锋》第二期」保留。"),
    dict(file="1-中国妇女运动杂评.txt", work="中国妇女运动杂评（从六月到八月）", author="向警予",
         prefix="CH-FNYP-", slug="fnyp",
         html=["xiangjingyu/mia-chinese-xjy-19231201a.html"],
         note="向警予《中国妇女运动杂评（从六月到八月）》（1923年12月1日），据「中文马克思主义文库」"
              "转录的《前锋》第二期原文：全文照录，未作节选；篇末「载《前锋》第二期」保留。"),
    dict(file="1-今后中国妇女的国民革命运动.txt", work="今后中国妇女的国民革命运动",
         author="向警予", prefix="CH-FNGM-", slug="fngm",
         html=["xiangjingyu/mia-chinese-xjy-19240101.html"],
         note="向警予《今后中国妇女的国民革命运动》（1924年1月1日），据「中文马克思主义文库」"
              "转录的《妇女周报》第十卷第一号原文：全文照录，未作节选；篇末刊载出处行保留。"),
    dict(file="1-丝厂女工团结起来.txt", work="丝厂女工团结起来", author="向警予",
         prefix="CH-SCTJ-", slug="sctj",
         html=["xiangjingyu/mia-chinese-xjy-19231121.html"],
         note="向警予《丝厂女工团结起来》（1923年11月21日），据「中文马克思主义文库」转录的"
              "《妇女周报》第十四号原文：全文照录，未作节选；篇末刊载出处行保留。"),
    dict(file="1-妇女运动的基础.txt", work="妇女运动的基础", author="向警予",
         prefix="CH-FNJC-", slug="fnjc",
         html=["xiangjingyu/mia-chinese-xjy-19250413.html"],
         note="向警予《妇女运动的基础》（1925年4月13日），据「中文马克思主义文库」转录的"
              "《妇女周报》第八十一号原文：全文照录，未作节选；篇末刊载出处行保留。"),
    dict(file="1-中共三大关于妇女运动的决议案.txt", work="中国共产党第三次全国代表大会关于妇女运动的决议案",
         author="中国共产党第三次全国代表大会", prefix="CH-SDFN-", slug="sdfn",
         html=["xiangjingyu/mia-chinese-xjy-192306.html"],
         note="《中国共产党第三次全国代表大会关于妇女运动的决议案》（1923年6月），据「中文马克思主义"
              "文库」转录：全文照录，未作节选；篇末中央档案馆编《中国共产党第二次至第六次全国代表大会"
              "文件汇编》（1981年版）所加按语保留。"),
    dict(file="1-中共四大对于妇女运动之议决案.txt", work="中国共产党第四次全国代表大会对于妇女运动之议决案",
         author="中国共产党第四次全国代表大会", prefix="CH-SIFN-", slug="sifn",
         html=["xiangjingyu/mia-chinese-xjy-192502.html"],
         note="《中国共产党第四次全国代表大会对于妇女运动之议决案》（1925年2月），据「中文马克思主义"
              "文库」转录：全文照录，未作节选；篇末中央档案馆编《中国共产党第二次至第六次全国代表大会"
              "文件汇编》（1981年版）所加按语保留。"),
    dict(file="1-关于妇女劳动问题.txt", work="关于妇女劳动问题", author="克拉拉·蔡特金",
         prefix="CH-FNLD-", slug="fnld",
         html=["clara-zetkin/mia-chinese-clara-zetkin-18890719.html"],
         note="克拉拉·蔡特金《关于妇女劳动问题》（1889年7月19日，第二国际成立大会发言），据「中文"
              "马克思主义文库」转录：篇首「说明：1889年7月在巴黎召开了国际社会主义者代表大会即"
              "第二国际成立大会……」一段与篇末「节选自《第二国际第一次代表大会文件》」一行保留；"
              "全文照录，未作节选。"),
    dict(file="1-无产阶级妇女们准备起来.txt", work="无产阶级妇女们，准备起来！",
         author="克拉拉·蔡特金", prefix="CH-ZBQL-", slug="zbql",
         html=["clara-zetkin/mia-chinese-clara-zetkin-19140805.html"],
         note="克拉拉·蔡特金《无产阶级妇女们，准备起来！》（1914年8月5日），据「中文马克思主义文库」"
              "转录：篇首「原文原载于1914年8月5日《平等》杂志第23期，斯图加特版。中译文译自库钦斯基"
              "《第一次世界大战与德国社会民主党》，1957年德文版」一行保留；全文照录，未作节选。"),
    dict(file="1-列宁给全世界妇女的遗教.txt", work="列宁给全世界妇女的遗教",
         author="克拉拉·蔡特金", prefix="CH-LNYJ-", slug="lnyj",
         html=["clara-zetkin/mia-chinese-clara-zetkin-1933.html"],
         note="克拉拉·蔡特金《列宁给全世界妇女的遗教》（1933年，为纪念国际妇女节而写；宋城 译），"
              "据「中文马克思主义文库」转录：篇首「译者：宋城」与「俄文版说明：……」一段（苏联出版"
              "方所加，含 1960 年代表述）保留；[NN] 译者注原文保留；全文照录，未作节选。"),

    # ===== D123 恽代英文献补录（22 篇，1925—1930）=====
    # 书源：镜像 `yundaiying/`。39 篇里按「符合马列毛思想 + 落在学习路线节点上」筛 22 篇：
    # 收理论著作与讲演 12 篇、工人运动与苏维埃史料 10 篇（含就义前给党组织的信）。
    # 不收：报刊短评 6 篇（《红旗》署「稚宜」的新闻体时评，非理论文献）、
    # 私人文字 7 篇（致柳亚子书信、《广东的青年劳动军人》抒情文、《主义》
    # 《为自己的利益而奋斗》宣传短论、《学生的背水阵》《告愤激的国民》
    # 《辟三种洋奴的论调》《革命势力与反革命势力》、《国民党中央及各省区代表
    # 联席会议之经过》会议报告）。
    # 口径：长篇按「合适章节」节选（中国民族革命运动史、答《醒狮周报》质难），
    # 其余为单篇报刊文全文照录，一字未改；篇末「载……」「署名……」行与注释保留。
    dict(file="1-中国民族革命运动史节选.txt", work="中国民族革命运动史（节选）",
         author="恽代英", prefix="CH-MZGM-", slug="mzgm",
         html=["yundaiying/mia-chinese-ydy-1926a.html"],
         note="恽代英《中国民族革命运动史》（1926 年在广州的讲演，当年由中华全国总工会、"
              "省港罢工委员会教育宣传委员会印行；据广州国光书店 1927 年 3 月初版单行本排印）。"
              "**D123 裁为节选**：保留题名、（一九二六年）系年、原书说明行、讲次目录全七讲，"
              "以及第五讲「辛亥革命运动」、第六讲「五四运动前后的国民党」、第七讲「五卅运动」"
              "三讲全文；裁去第一至四讲（由反清复明运动至鸦片战争／鸦片战争及其影响／"
              "由太平天国运动至康梁变法／义和团与八国联军）正文。"
              "原文一字未改，边界均为讲次标题行。"),
    dict(file="1-世界革命与中国革命.txt", work="世界革命与中国革命（讲演大纲）",
         author="恽代英", prefix="CH-SJGM-", slug="sjgm",
         html=["yundaiying/mia-chinese-ydy-1926.html"],
         note="恽代英《世界革命与中国革命（讲演大纲）》（1926 年），据国民革命军第一军"
              "第三师政治部出版单行本排印：全文照录，未作节选——三节（革命的意义／"
              "中国的革命运动／我们的革命势力）本身就是纲目体，裁任何一节都会断掉"
              "「敌友我」对照；篇末「据……单行本排印」与「署名：恽代英」两行保留。"),
    dict(file="1-革命之障碍.txt", work="革命之障碍", author="恽代英",
         prefix="CH-GMZA-", slug="gmza",
         html=["yundaiying/mia-chinese-ydy-192604.html"],
         note="恽代英《革命之障碍》（1926 年 4 月在黄埔军校的讲演），据「中文马克思主义文库」"
              "转录的《黄埔潮》半周刊第 46—52 期原文：全文照录，未作节选；篇末"
              "「载《黄埔潮》半周刊第 46—52 期」与「恽代英讲 李鸣柯、缪芸人笔记」两行保留。"),
    dict(file="1-国民革命与阶级斗争.txt", work="国民革命与阶级斗争", author="恽代英",
         prefix="CH-GMJJ-", slug="gmjj",
         html=["yundaiying/mia-chinese-ydy-19260825.html"],
         note="恽代英《国民革命与阶级斗争》（1926 年 8 月 25 日讲演），据「中文马克思主义文库」"
              "转录的《革命生活》第 17 期原文：全文照录，未作节选；篇末"
              "「载《革命生活》第 17 期」与「恽代英讲 林焕源笔记」两行保留。"),
    dict(file="1-与李琯卿君论新国家主义.txt", work="与李琯卿君论新国家主义", author="恽代英",
         prefix="CH-LGQJ-", slug="lgqj",
         html=["yundaiying/mia-chinese-ydy-19250404.html"],
         note="恽代英《与李琯卿君论新国家主义》（1925 年 4 月 4 日），据「中文马克思主义文库」"
              "转录的《中国青年》第 73 期原文：全文照录，未作节选（篇首两问"
              "「中国有无产阶级专政的可能性么？」「为什么在国民革命运动中主张阶级争斗？」"
              "即全文两节，节选会失去问答体的完整性）；篇末「载……」「署名：代英」两行保留。"),
    dict(file="1-答醒狮周报三十二期的质难节选.txt", work="答《醒狮周报》三十二期的质难（节选）",
         author="恽代英", prefix="CH-XSZB-", slug="xszb",
         html=["yundaiying/mia-chinese-ydy-19250718.html"],
         note="恽代英《答〈醒狮周报〉三十二期的质难》（1925 年 7 月 18 日），据「中文马克思主义"
              "文库」转录的《中国青年》第 82 期原文。**D123 裁为节选**：保留「一 民族解放运动"
              "决不是甚么『国家主义』」与「二 谁能担保革命者不『出卖』救国事业」两节全文；"
              "裁去「三 联俄便是倚赖外力么？」与「四 答余家菊君的五个问题」两节"
              "（关乎联俄与具体问答，与国家主义论战主线不直接对读）。"
              "原文一字未改，边界均为小节标题行；篇末「载……」「署名：代英」与注① 保留。"),
    dict(file="1-读孙文主义之哲学的基础.txt", work="读《孙文主义之哲学的基础》", author="恽代英",
         prefix="CH-SWZY-", slug="swzy",
         html=["yundaiying/mia-chinese-ydy-19250808.html"],
         note="恽代英《读〈孙文主义之哲学的基础〉》（1925 年 8 月 8 日），据「中文马克思主义文库」"
              "转录的《中国青年》第 87 期原文：全文照录，未作节选；篇末「载……」"
              "「署名：代英」两行保留。"),
    dict(file="1-民族革命中的共产党.txt", work="民族革命中的共产党", author="恽代英",
         prefix="CH-MZGC-", slug="mzgc",
         html=["yundaiying/mia-chinese-ydy-19250822.html"],
         note="恽代英《民族革命中的共产党》（1925 年 8 月 22 日），据「中文马克思主义文库」"
              "转录的《中国青年》第 89 期原文：全文照录，未作节选（五条对共产党的疑问"
              "逐条作答，缺一条即断链）；篇末「载……」「署名：F.M.」两行保留。"),
    dict(file="1-为什么产业无产阶级最富于革命性.txt", work="为什么产业无产阶级最富于革命性？",
         author="恽代英", prefix="CH-CYGM-", slug="cygm",
         html=["yundaiying/mia-chinese-ydy-19260206.html"],
         note="恽代英《为什么产业无产阶级最富于革命性？》（1926 年 2 月 6 日），据「中文马克思"
              "主义文库」转录的《黄埔潮》半周刊第 34 期原文：全文照录，未作节选；"
              "篇末「载……」「署名：代英」两行保留。"),
    dict(file="1-中国劳动阶级斗争第一幕.txt", work="中国劳动阶级斗争第一幕", author="恽代英",
         prefix="CH-LDJJ-", slug="ldjj",
         html=["yundaiying/mia-chinese-ydy-19250207.html"],
         note="恽代英《中国劳动阶级斗争第一幕》（1925 年 2 月 7 日，记「二七」二周年），"
              "据「中文马克思主义文库」转录的《中国青年》第 65 期原文：全文照录，"
              "未作节选；篇末「载……」「署名：F.M.」与注① 保留。"),
    dict(file="1-上海日纱厂罢工中所得的教训.txt", work="上海日纱厂罢工中所得的教训",
         author="恽代英", prefix="CH-RSCB-", slug="rscb",
         html=["yundaiying/mia-chinese-ydy-19250314.html"],
         note="恽代英《上海日纱厂罢工中所得的教训》（1925 年 3 月 14 日），据「中文马克思主义"
              "文库」转录的《中国青年》第 70 期原文：全文照录，未作节选（四条教训"
              "逐一对应，缺一条即失去调查结论的完整链条）；篇末「载……」「署名：但一」保留。"),
    dict(file="1-五卅运动与阶级争斗.txt", work="五卅运动与阶级争斗", author="恽代英",
         prefix="CH-WSJJ-", slug="wsjj",
         html=["yundaiying/mia-chinese-ydy-19251128.html"],
         note="恽代英《五卅运动与阶级争斗》（1925 年 11 月 28 日，答《中国青年》读者重良的信），"
              "据「中文马克思主义文库」转录：全文照录，未作节选；篇末注〔1〕〔2〕〔3〕保留"
              "（篇内无「载……」行，出处见读者来信与答文的刊物关系，篇首「重良：」即来信者名）。"),
    dict(file="1-农民中的宣传组织工作.txt", work="农民中的宣传组织工作", author="恽代英",
         prefix="CH-NMXC-", slug="nmxc",
         html=["yundaiying/mia-chinese-ydy-19251229.html"],
         note="恽代英《农民中的宣传组织工作》（1925 年 12 月 29 日），据「中文马克思主义文库」"
              "转录的《中国青年》第 106 期原文：全文照录，未作节选（宣传工作三方面"
              "与组织工作各环节是操作手册式的整体）；篇末「载……」「署名：代英」保留。"),
    dict(file="1-怎样做一个共产党员.txt", work="怎样做一个共产党员？", author="恽代英",
         prefix="CH-ZYCD-", slug="zycd",
         html=["yundaiying/mia-chinese-ydy-19261001.html"],
         note="恽代英《怎样做一个共产党员？》（1926 年 10 月 1 日），据「中文马克思主义文库」"
              "转录的《少年先锋》第 1 卷第 4 期原文：全文照录，未作节选（党员标准"
              "逐条列举，删任何一条都会漏掉标准）；篇末「载……」「署名：代英」保留。"),
    dict(file="1-什么是机会主义.txt", work="什么是机会主义？", author="恽代英",
         prefix="CH-JHZY-", slug="jhzy",
         html=["yundaiying/mia-chinese-ydy-19270122.html"],
         note="恽代英《什么是机会主义？》（1927 年 1 月 22 日），据「中文马克思主义文库」"
              "转录的《中国青年》第 151 期原文：全文照录，未作节选；篇末「载……」"
              "「署名：F．M．」两行保留。"),
    dict(file="1-我们的战略.txt", work="我们的战略", author="恽代英",
         prefix="CH-WMDZ-", slug="wmdz",
         html=["yundaiying/mia-chinese-ydy-19250808a.html"],
         note="恽代英《我们的战略》（1925 年 8 月 8 日），据「中文马克思主义文库」转录的"
              "《中国青年》第 88 期原文：全文照录，未作节选（五条战略逐条递进，"
              "即是这篇文章的骨架）；篇末「载……」「署名：F.M.」两行保留。"),
    dict(file="1-苏维埃的建立.txt", work="苏维埃的建立", author="恽代英、李立三",
         prefix="CH-SWEA-", slug="swea",
         html=["yundaiying/mia-chinese-ydy-192802.html"],
         note="恽代英、李立三合著《苏维埃的建立》（1928 年 2 月），据《恽代英全集》转录"
              "（镜像页头「〔 来源 〕《恽代英全集》」一行保留）：全文照录，未作节选；"
              "**引用须声明合著性质**，不得只署恽代英一人。"),
    dict(file="1-广州暴动与工会.txt", work="广州暴动与工会", author="恽代英",
         prefix="CH-GZBQ-", slug="gzbq",
         html=["yundaiying/mia-chinese-ydy-192801.html"],
         note="恽代英《广州暴动与工会》（1928 年初），据「中文马克思主义文库」转录的"
              "广东省委机关刊物《红旗》1928 年初版原文：全文照录，未作节选；"
              "篇首说明行（恽代英在广州苏维埃政府中任秘书长、本文作于起义后）与"
              "篇末「载广东《红旗》，1928 年初出版」「署名：恽代英」三行保留。"),
    dict(file="1-闽西苏维埃的过去与将来.txt", work="闽西苏维埃的过去与将来", author="恽代英",
         prefix="CH-MXSW-", slug="mxsw",
         html=["yundaiying/mia-chinese-ydy-19300326.html"],
         note="恽代英《闽西苏维埃的过去与将来》（1930 年 3 月 26 日），据「中文马克思主义文库」"
              "转录的《红旗》第 87 期原文：全文照录，未作节选；篇末「载……」"
              "「署名：代英」两行保留。"),
    dict(file="1-请看闽西农民造反的成绩.txt", work="请看闽西农民造反的成绩——福建通信",
         author="恽代英", prefix="CH-KMXN-", slug="kmxn",
         html=["yundaiying/mia-chinese-ydy-19300312.html"],
         note="恽代英《请看闽西农民造反的成绩——福建通信》（1930 年 3 月 12 日），据"
              "「中文马克思主义文库」转录的《红旗》第 83 期原文：全文照录，未作节选；"
              "篇首说明行（1930 年 2 月以中央代表身份到厦门指导中共福建省第二次代表大会、"
              "当时未署名、同年 5 月编入《中国苏维埃》时署名「代英」）与篇末「载……」保留。"),
    dict(file="1-中东路问题与一般流行的错误意见.txt", work="中东路问题与一般流行的错误意见",
         author="恽代英", prefix="CH-ZDLW-", slug="zdlw",
         html=["yundaiying/mia-chinese-ydy-19290731-0807.html"],
         note="恽代英《中东路问题与一般流行的错误意见》（1929 年 7 月 31 日、8 月 7 日），"
              "据「中文马克思主义文库」转录的《红旗》第 35、37 期原文：全文照录，"
              "未作节选；篇末「载《红旗》第 35、37 期」「署名：稚宜」两行保留。"),
    dict(file="1-在狱中给党组织的信.txt", work="在狱中给党组织的信（附《狱中诗》）",
         author="恽代英", prefix="CH-YZDX-", slug="yzdx",
         html=["yundaiying/mia-chinese-ydy-193005.html"],
         note="恽代英《在狱中给党组织的信》（附《狱中诗》，1930 年 5 月），据「中文马克思主义"
              "文库」转录的《革命烈士诗抄》（中国青年出版社出版）：全文照录，未作节选；"
              "这是写给党组织的信、不是私人往来，故收；篇首说明行（1930 年 5 月 6 日"
              "被捕、化名王作林等）与篇末「载《革命烈士诗抄》」「中国青年出版社出版」"
              "与注① 保留。"),

    # ===== D124 克鲁普斯卡娅「列宁怎样读书、研究、宣传」10 篇 =====
    # 立项依据：库里已有克鲁普斯卡娅 0 篇，而三个路线都在讲「怎么学、怎么研究、
    # 怎么讲给群众听」，却没有任何一份「列宁本人的读书方法与宣传工作方法」的
    # 第一手回忆——`sec_B_10`（实事求是：改造我们的学习）只有毛泽东 1941 年报告，
    # `sec_B_05`（调查研究）只有《反对本本主义》，方法论的「示范样本」是空的。
    # 书源两处：
    # · `krupskaya/on-lenin-2/`——人民出版社 1973 年版《列宁是怎样写作学习的》
    #   整本 11 篇（写作、研究、宣传、图书馆、外国语），本批按篇级**节选 7 篇**
    #   （裁去《列宁的编辑工作》《列宁著作中的〈资本论〉》《纪念列宁的〈唯物主义
    #   和经验批判主义〉一书出版二十五周年》《列宁的方针》4 篇）；
    # · `krupskaya/on-lenin/`——《论列宁》（1979 年俄文第 4 版）单篇，中译见
    #   《马列著作编译资料》第 15／16 辑，收 3 篇（研究马克思主义、列宁是科学
    #   工作者、列宁如何对待博物馆工作）。
    # 边界（写死）：`on-education/`（591,773 汉字）、`reminiscences-of-lenin/`
    # （375,855 汉字）与顶层私人书信一律不收——教育专题与生平回忆不属于
    # 「读书／研究／宣传方法」这个窄口。
    # 口径：10 篇篇内**全文照录、一字未改**，不设章内裁剪（篇内无小节标题行，
    # 硬裁会违反「边界必须落在标题行」这条红线）；节选只发生在篇这一级。
    dict(file="1-列宁是宣传家和鼓动家.txt", work="列宁是宣传家和鼓动家",
         author="娜·康·克鲁普斯卡娅", prefix="CH-KPLJ-", slug="kplj",
         html=["krupskaya/on-lenin-2/01.html"],
         note="娜·康·克鲁普斯卡娅《列宁是宣传家和鼓动家》（1933 年），据「中文马克思主义文库」"
              "转录的人民出版社 1973 年版《列宁是怎样写作学习的》文本：本批按篇从该书 11 篇中"
              "选 7 篇（整本节选），篇内全文照录、未作裁剪，一字未改；篇内「列宁是宣传家」"
              "「列宁是鼓动家」两个小标题与「弗·伊·列宁」题记、篇末「写于1933年」"
              "「载于娜·康·克鲁普斯卡娅：《列宁是宣传家和鼓动家》」两行、[NN] 编者注保留。"),
    dict(file="1-列宁论善于为工农群众写作.txt", work="列宁论善于为工农群众写作",
         author="娜·康·克鲁普斯卡娅", prefix="CH-KPGZ-", slug="kpgz",
         html=["krupskaya/on-lenin-2/03.html"],
         note="娜·康·克鲁普斯卡娅《列宁论善于为工农群众写作》（1930 年），据「中文马克思主义文库」"
              "转录的人民出版社 1973 年版《列宁是怎样写作学习的》文本：整本节选 7 篇之一，"
              "篇内全文照录、一字未改；篇末「写于1930年」「载于娜·康·克鲁普斯卡娅：《列宁是党的"
              "报刊的编辑和组织者》」两行与 [NN] 编者注保留。"),
    dict(file="1-列宁怎样研究马克思的著作.txt", work="列宁怎样研究马克思的著作",
         author="娜·康·克鲁普斯卡娅", prefix="CH-KPYJ-", slug="kpyj",
         html=["krupskaya/on-lenin-2/04.html"],
         note="娜·康·克鲁普斯卡娅《列宁怎样研究马克思的著作》（1933 年），据「中文马克思主义文库」"
              "转录的人民出版社 1973 年版《列宁是怎样写作学习的》文本：整本节选 7 篇之一，"
              "篇内全文照录、一字未改（本篇 9,700 余字、通篇为连续叙述、无小节标题行，"
              "按「边界必须落在标题行」的规矩不作章内裁剪）；篇末「写于1933年」"
              "「载于娜·康·克鲁普斯卡娅：《学习列宁那样工作》」两行与 [NN] 编者注保留。"),
    dict(file="1-创造性的研究过程.txt", work="创造性的研究过程",
         author="娜·康·克鲁普斯卡娅", prefix="CH-CZXJ-", slug="czxj",
         html=["krupskaya/on-lenin-2/06.html"],
         note="娜·康·克鲁普斯卡娅《创造性的研究过程》（1923 年），据「中文马克思主义文库」转录的"
              "人民出版社 1973 年版《列宁是怎样写作学习的》文本：整本节选 7 篇之一，篇内全文照录、"
              "一字未改；篇末「写于1923年」「载于娜·康·克鲁普斯卡娅：《关于弗·伊·列宁的最后两篇"
              "文章——〈宁肯少些，但要好些〉和〈我们对工农检查院应该怎么办？〉》」两行保留。"),
    dict(file="1-理论联系实际的学风.txt", work="理论联系实际的学风",
         author="娜·康·克鲁普斯卡娅", prefix="CH-LLLX-", slug="lllx",
         html=["krupskaya/on-lenin-2/07.html"],
         note="娜·康·克鲁普斯卡娅《理论联系实际的学风》，据「中文马克思主义文库」转录的人民出版社"
              "1973 年版《列宁是怎样写作学习的》文本：整本节选 7 篇之一，篇内全文照录、一字未改；"
              "本篇引列宁 1894 年《什么是「人民之友」……》中「研究，宣传，组织」一段，是全书"
              "篇名所本；篇末 [NN] 编者注保留。"),
    dict(file="1-列宁怎样利用图书馆.txt", work="列宁怎样利用图书馆",
         author="娜·康·克鲁普斯卡娅", prefix="CH-KPTU-", slug="kptu",
         html=["krupskaya/on-lenin-2/10.html"],
         note="娜·康·克鲁普斯卡娅《列宁怎样利用图书馆》（1932 年），据「中文马克思主义文库」转录的"
              "人民出版社 1973 年版《列宁是怎样写作学习的》文本：整本节选 7 篇之一，篇内全文照录、"
              "一字未改；篇末「写于1932年」「载于娜·康·克鲁斯卡娅：《列宁关于图书事业写了和说了"
              "些什么？》」两行与 [NN] 编者注保留。"),
    dict(file="1-列宁怎样学习外国语.txt", work="列宁怎样学习外国语",
         author="娜·康·克鲁普斯卡娅", prefix="CH-KPWY-", slug="kpwy",
         html=["krupskaya/on-lenin-2/11.html"],
         note="娜·康·克鲁普斯卡娅《列宁怎样学习外国语》（1937 年），据「中文马克思主义文库」转录的"
              "人民出版社 1973 年版《列宁是怎样写作学习的》文本：整本节选 7 篇之一，篇内全文照录、"
              "一字未改；篇末「写于1937年」「载于1937年9月5日《真理报》第245号」两行保留。"),
    dict(file="1-研究马克思主义.txt", work="研究马克思主义",
         author="娜·康·克鲁普斯卡娅", prefix="CH-YJMY-", slug="yjmy",
         html=["krupskaya/on-lenin/321-329.html"],
         drop_leading=("研究马克思主义",),
         note="娜·康·克鲁普斯卡娅《研究马克思主义》（1924 年 9 月 20 日在俄罗斯列宁共产主义青年团"
              "中央委员会全体会议上的报告，刊载时作了删节），中译文见《马列著作编译资料》："
              "全文照录，未作裁剪，一字未改；篇首「孙凌齐 译 王澍 校」与版本说明行（含「刊载时"
              "作了删节」）保留——删节是原刊所为，不是本库所为。"),
    dict(file="1-列宁是科学工作者.txt", work="列宁是科学工作者",
         author="娜·康·克鲁普斯卡娅", prefix="CH-KPKX-", slug="kpkx",
         html=["krupskaya/on-lenin/352-353.html"],
         note="娜·康·克鲁普斯卡娅《列宁是科学工作者》，中译文见《马列著作编译资料》第 16 辑"
              "（原文原载于《论列宁》1979 年俄文第 4 版第 352—353 页）：全文照录，未作裁剪，"
              "一字未改；篇首译者行与版本说明行、篇末 [NN] 编者注保留。"),
    dict(file="1-列宁如何对待博物馆工作.txt", work="列宁如何对待博物馆工作",
         author="娜·康·克鲁普斯卡娅", prefix="CH-KPBW-", slug="kpbw",
         html=["krupskaya/on-lenin/103-104.html"],
         note="娜·康·克鲁普斯卡娅《列宁如何对待博物馆工作》，中译文见《马列著作编译资料》第 16 辑"
              "（原文原载于《论列宁》1979 年俄文第 4 版第 103—104 页）：全文照录，未作裁剪，"
              "一字未改；篇首译者行与版本说明行保留。"),

    # ===== D125 按章节缺口补 13 篇（列宁夺权三篇／马克思论犹太人问题／李大钊四篇／
    # 周恩来两篇／毛泽东宪法草案／邓中夏我们的力量）=====
    # 立项依据不是「作者全集补全」，而是九个章节的**内容缺口**：
    # · `sec_B_02`（国家与革命：夺权）只有 4 条、且没有一篇列宁 1917 年的夺权
    #   策略文本——十月革命前三个月列宁究竟怎么论证「现在就该起义」是空白的；
    # · `sec_A_12`（异化劳动与人的解放）只有 2 条，缺马克思本人论「政治解放 vs
    #   人类解放」的原典；
    # · `sec_A_09`（打碎旧国家机器：法兰西内战）缺中国早期对巴黎公社的系统介绍；
    # · `sec_A_13`（辩证唯物主义要义）只有 2 条，缺列宁对马克思主义世界观的整体概述；
    # · `sec_B_09`（调查研究与阶级分析的范本）缺党早期对农村与农民武装的直接调查；
    # · `sec_C_02`（新民主主义论）缺「马克思怎么看中国民族革命」这条中国化线索；
    # · `sec_C_03`（论人民民主专政）缺建国后国家结构（宪法、民族区域自治）文本；
    # · `sec_B_08`（战略与策略）缺统一战线经验的系统总结；
    # · `sec_B_03`（中国社会各阶级的分析）缺无产阶级自身力量的实证统计。
    # 红线核对：列宁（1917 年 4—10 月夺权文本）、马克思（1843 年）、毛泽东、周恩来、
    # 李大钊（1927 年遇难）、邓中夏（1933 年遇难）均为正面文献，不命中黑名单四条。
    # 口径：12 篇全文照录、一字未改；《卡尔·马克思》按小节标题裁为哲学部分（见 TRIM）。
    dict(file="1-论策略书.txt", work="论策略书", author="列宁", prefix="CH-CELS-", slug="cls",
         html=["lenin/mia-chinese-lenin-19170408-13.html"],
         note="列宁《论策略书》（1917 年 4 月 8 日和 13 日〔21 日和 26 日〕之间），据「中文马克思主义"
              "文库」转录的《列宁全集》中文版文本：全文照录、未作裁剪，一字未改；"
              "篇内两封信的分隔行、[NN] 脚注与篇末注释区保留。"),
    dict(file="1-马克思主义和起义.txt", work="马克思主义和起义", author="列宁", prefix="CH-MYSQ-", slug="mysq",
         html=["lenin-cworks/32/030.html"],
         note="列宁《马克思主义和起义——给俄国社会民主工党（布）中央委员会的信》"
              "（1917 年 9 月 13—14 日〔26—27 日〕），据「中文马克思主义文库」转录的"
              "《列宁全集》中文版文本：全文照录、未作裁剪，一字未改；"
              "篇首副题行、[NN] 脚注与篇末注释区保留。"),
    dict(file="1-布尔什维克能保持国家政权吗.txt", work="布尔什维克能保持国家政权吗？", author="列宁",
         prefix="CH-BESW-", slug="besw",
         html=["lenin/mia-chinese-lenin-19171001.html"],
         note="列宁《布尔什维克能保持国家政权吗？》（1917 年 9 月底—10 月 1 日〔14 日〕），据"
              "「中文马克思主义文库」转录的《列宁全集》中文版文本：全文照录、未作裁剪，"
              "一字未改；篇内「再版序言」「我们听到的赞许声」「后记」三个小标题、"
              "苏维埃代表名额对照表、[NN] 脚注与篇末注释区保留。"),
    dict(file="1-论犹太人问题.txt", work="论犹太人问题", author="马克思", prefix="CH-LYTR-", slug="lytr",
         html=["marx-engels2/01/02.html"],
         note="马克思《论犹太人问题》（1843 年秋），据「中文马克思主义文库」转录的"
              "《马克思恩格斯文集》第一卷文本：全文照录、未作裁剪，一字未改；"
              "篇首作者行、篇名后的编者注号、篇内「一 布鲁诺·鲍威尔：《犹太人问题》1843 年"
              "不伦瑞克版」「二 布鲁诺·鲍威尔：《现代犹太人和基督徒获得自由的能力》」"
              "两节标题与 [NN] 编者注保留。"),
    dict(file="1-一八七一年的巴黎康妙恩.txt", work="一八七一年的巴黎“康妙恩”", author="李大钊",
         prefix="CH-KMEN-", slug="kme",
         html=["lidazhao/marxist.org-chinese-lee-192302.html"],
         note="李大钊《一八七一年的巴黎“康妙恩”》（五十年的回顾 社会革命的先声，1923 年 2 月），"
              "据「中文马克思主义文库」转录的《申报之最近五十年》原文：全文照录、未作裁剪，"
              "一字未改；篇首副题行、篇末「1923年2月」「“申报之最近五十年”」「署名：李大钊」"
              "三行保留。"),
    dict(file="1-卡尔马克思传略和马克思主义概述节选.txt", work="卡尔·马克思（传略和马克思主义概述·节选）",
         author="列宁", prefix="CH-KEMK-", slug="kem",
         html=["lenin-cworks/26/009.html"],
         note="列宁《卡尔·马克思（传略和马克思主义概述）》（1914 年 11 月），据「中文马克思主义"
              "文库」转录的《列宁全集》中文版第 26 卷文本。**D125 裁为节选**：保留「序言」、"
              "马克思传略部分与「马克思的学说」下的「哲学唯物主义」「辩证法」「唯物主义历史观」"
              "「阶级斗争」四节；裁去「马克思的经济学说」「社会主义」「无产阶级阶级斗争的策略」"
              "「书目」四节（经济学说与策略另有专章，本处只取世界观概述）。"
              "原文一字未改，边界为小节标题行；[NN] 脚注保留。"),
    dict(file="1-土地与农民.txt", work="土地与农民", author="李大钊", prefix="CH-TDYM-", slug="tdym",
         html=["lidazhao/marxist.org-chinese-lee-19251230.html"],
         note="李大钊《土地与农民》（1925 年 12 月 30 日），据「中文马克思主义文库」转录的"
              "《政治生活》第 62—67 期原文：全文照录、未作裁剪，一字未改；"
              "篇内农业人口与土地分配的统计数字、篇末「1926年2月3日」「“政治生活”62—67期」"
              "「署名：守常」三行保留。"),
    dict(file="1-鲁豫陕等省的红枪会.txt", work="鲁豫陕等省的红枪会", author="李大钊", prefix="CH-HQHH-", slug="hqh",
         html=["lidazhao/marxist.org-chinese-lee-1926A.html"],
         note="李大钊《鲁豫陕等省的红枪会》（1926 年 8 月 8 日），据「中文马克思主义文库」转录的"
              "《政治生活》原文（按《守常文集》刊印）：全文照录、未作裁剪，一字未改；"
              "篇末「“政治生活”」「按“守常文集”刊印」两行保留。"),
    dict(file="1-马克思的中国民族革命观.txt", work="马克思的中国民族革命观", author="李大钊",
         prefix="CH-ZGMG-", slug="zgmg",
         html=["lidazhao/marxist.org-chinese-lee-192605.html"],
         note="李大钊《马克思的中国民族革命观》（1926 年 5 月），据「中文马克思主义文库」转录的"
              "《政治生活》第 76 期原文：全文照录、未作裁剪，一字未改；"
              "篇末「1926年5月」「“政治生活”第76期」「署名：猎夫」三行保留。"),
    dict(file="1-论统一战线.txt", work="论统一战线", author="周恩来", prefix="CH-LTYX-", slug="ltyx",
         html=["zhouenlai/028.html"],
         note="周恩来《论统一战线》（1945 年 4 月 30 日），据「中文马克思主义文库」转录的"
              "《周恩来选集》上卷文本：全文照录、未作裁剪，一字未改；"
              "篇首日期行、篇末「＊这是在中国共产党第七次全国代表大会上的发言。」题注保留。"),
    dict(file="1-关于中华人民共和国宪法草案.txt", work="关于中华人民共和国宪法草案", author="毛泽东",
         prefix="CH-XFCA-", slug="xfca",
         html=["maozedong/marxist.org-chinese-mao-19540614.html"],
         note="毛泽东《关于中华人民共和国宪法草案》（1954 年 6 月 14 日），据「中文马克思主义文库」"
              "转录的《毛泽东选集》第五卷文本：全文照录、未作裁剪，一字未改；"
              "篇首日期行、[NN] 脚注保留。"),
    dict(file="1-关于我国民族政策的几个问题.txt", work="关于我国民族政策的几个问题", author="周恩来",
         prefix="CH-MZZC-", slug="mzzc",
         html=["zhouenlai/260.html"],
         note="周恩来《关于我国民族政策的几个问题》（1957 年 8 月 4 日），据「中文马克思主义文库」"
              "转录的《周恩来选集》下卷文本：全文照录、未作裁剪，一字未改；"
              "篇首日期行、篇末「＊这是在全国人民代表大会民族委员会召开的民族工作座谈会上的讲话。」"
              "题注保留。"),
    dict(file="1-我们的力量.txt", work="我们的力量", author="邓中夏", prefix="CH-WMDL-", slug="wmdl",
         html=["dengzhongxia/marxist.org-chinese-gong-192411.html"],
         drop_leading=("我们的力量", "第一册（1921―1925）"),
         note="邓中夏《我们的力量》（1924 年 11 月），据「中文马克思主义文库」转录的《中国工人》"
              "第 2 期原文：全文照录、未作裁剪，一字未改；网页顶部重复输出的篇名行与"
              "《邓中夏文集》分册行「第一册（1921―1925）」属版面信息，已按行删除；"
              "篇首「（载于一九二四年十一月出版的《中国工人》第二期）」行、篇内工矿人数统计表、"
              "篇末「原载《中国工人》第2期」「署名：邓中夏」两行与 [NN] 脚注保留。"),

    # ===== D126 周恩来民主革命期补 12 篇（1926—1949），按章节缺口选，不按年份堆 =====
    # 立项依据是六章的**内容缺口**，尤其用户点名的两章：
    # · `sec_B_02`（国家与革命：夺权）7 条里 6 条是列宁俄国经验 + 恽代英 1928 年苏维埃，
    #   中国革命自己的夺权与政权更替路径（农村包围城市→夺取城市、打谈结合）没有原文；
    # · `sec_C_02`（新民主主义论）7 条都是「论新民主主义」的总纲，缺建国前后新民主主义纲领、
    #   经济构成与恢复生产的具体文本；
    # · `sec_B_01`（建党原则）缺红四军前委与中央关系（九月来信）与党内意识斗争的直接文献；
    # · `sec_B_03`（中国社会各阶级的分析）缺对蒋介石统治阶级性质的判定示范；
    # · `sec_B_08`（战略与策略）缺大革命时期无产阶级领导权主张与两次国共合作的教训总结；
    # · `sec_B_09`（调查研究与阶级分析的范本）缺「分类指导」式的土改与整党指示。
    # 红线核对：全部为《周恩来选集》上卷文本、正面谱系，不命中黑名单四条；
    # 与既有周恩来 15 篇、222 条延伸阅读条目零重复。
    # 口径：12 篇全文照录、一字未改、不设 TRIM、不留裁剪备份。
    # 其中 4 篇自带删节/摘要题注（九月来信「个别段落没有选入」、论中国的法西斯主义
    # 「第五部分有删节」、一年来的谈判及前途「第二部分是摘要」、恢复生产建设中国
    # 「讲话摘要」）——删节是原书/原刊所为，按纪律原样保留并在题注里注明。
    dict(file="1-中共中央给红军第四军前委的指示信.txt", work="中共中央给红军第四军前委的指示信",
         author="周恩来", prefix="CH-HJZS-", slug="hjzs",
         html=["zhouenlai/007.html"],
         drop_leading=("中共中央给红军第四军前委的指示信", "（一九二九年九月二十八日）"),
         note="周恩来《中共中央给红军第四军前委的指示信》（1929 年 9 月 28 日，即「九月来信」），"
              "据「中文马克思主义文库」转录的《周恩来选集》上卷文本：全文照录、未作裁剪，"
              "一字未改；篇内「目前军阀混战的形势」「红军的根本问题」「红军的组织与训练」"
              "等小标题、[NN] 编者注保留；篇末「＊这封信是陈毅同志按照周恩来同志多次谈话和"
              "中共中央会议的精神代中央起草并经周恩来同志审定的，收入本书时个别段落没有"
              "选入。」题注原样保留——删节是《周恩来选集》编辑所为，不是本库所为。"),
    dict(file="1-坚决肃清党内一切非无产阶级的意识.txt", work="坚决肃清党内一切非无产阶级的意识",
         author="周恩来", prefix="CH-SQYS-", slug="sqys",
         html=["zhouenlai/003.html"],
         drop_leading=("坚决肃清党内一切非无产阶级的意识", "（一九二八年十一月十一日）"),
         note="周恩来《坚决肃清党内一切非无产阶级的意识》（1928 年 11 月 11 日），据"
              "「中文马克思主义文库」转录的《周恩来选集》上卷文本：全文照录、未作裁剪，"
              "一字未改；篇内「第一，极端民主化的倾向」至「第四，支部生活的改进」四条"
              "分项行、[NN] 编者注保留；篇末「＊这是中共中央为贯彻执行中国共产党第六次"
              "全国代表大会决议而发布的《告全体同志书》的第四部分，这部分是周恩来同志"
              "起草的。」题注原样保留。"),
    dict(file="1-现时政治斗争中之我们.txt", work="现时政治斗争中之我们", author="周恩来",
         prefix="CH-XSZZ-", slug="xszz",
         html=["zhouenlai/001.html"],
         drop_leading=("现时政治斗争中之我们", "（一九二六年十二月十一日）"),
         note="周恩来《现时政治斗争中之我们》（1926 年 12 月 11 日），据「中文马克思主义文库」"
              "转录的《周恩来选集》上卷文本：全文照录、未作裁剪，一字未改；篇内分节序号行、"
              "[NN] 编者注保留；篇末「＊一九二六年冬，随着北伐战争的节节胜利……」题注"
              "（说明当时党内右倾机会主义者不敢坚持无产阶级领导权）原样保留。"),
    dict(file="1-关于一九二四至二六年党对国民党的关系.txt", work="关于一九二四至二六年党对国民党的关系",
         author="周恩来", prefix="CH-GMDX-", slug="gmdx",
         html=["zhouenlai/020.html"],
         drop_leading=("关于一九二四至二六年党对国民党的关系", "（一九四三年春）"),
         note="周恩来《关于一九二四至二六年党对国民党的关系》（1943 年春），据「中文马克思主义"
              "文库」转录的《周恩来选集》上卷文本：全文照录、未作裁剪，一字未改；"
              "篇内 [NN] 编者注保留；篇末「＊这是在重庆中共中央南方局干部学习会上所做的报告。」"
              "题注原样保留。"),
    dict(file="1-一年来的谈判及前途.txt", work="一年来的谈判及前途", author="周恩来",
         prefix="CH-YNTP-", slug="yntp",
         html=["zhouenlai/041.html"],
         drop_leading=("一年来的谈判及前途", "（一九四六年十二月十八日）"),
         note="周恩来《一年来的谈判及前途》（1946 年 12 月 18 日），据「中文马克思主义文库」"
              "转录的《周恩来选集》上卷文本：全文照录、未作裁剪，一字未改；"
              "篇内「一 一年来的谈判情况」「二 一年谈判的经验教训与将来的前途」两节标题、"
              "[NN] 编者注保留；篇末「＊这是在延安的一次干部会议上的报告，其中第二部分是"
              "摘要。」题注原样保留——摘要是《周恩来选集》编辑所为，不是本库所为。"),
    dict(file="1-论中国的法西斯主义新专制主义.txt", work="论中国的法西斯主义——新专制主义",
         author="周恩来", prefix="CH-FXSZ-", slug="fxsz",
         html=["zhouenlai/025.html"],
         drop_leading=("论中国的法西斯主义——新专制主义", "（一九四三年八月十六日）"),
         note="周恩来《论中国的法西斯主义——新专制主义》（1943 年 8 月 16 日），据"
              "「中文马克思主义文库」转录的《周恩来选集》上卷文本：全文照录、未作裁剪，"
              "一字未改；篇内「一 问题的提出和回答」等分节标题行、[NN] 编者注保留；"
              "篇末「＊这是一个报告提纲，收入本书时第五部分有删节。」题注原样保留——"
              "删节是《周恩来选集》编辑所为，不是本库所为。"),
    dict(file="1-全国大反攻打倒蒋介石.txt", work="全国大反攻，打倒蒋介石", author="周恩来",
         prefix="CH-QGFG-", slug="qgfg",
         html=["zhouenlai/044.html"],
         drop_leading=("全国大反攻，打倒蒋介石", "（一九四七年九月二十八日）"),
         note="周恩来《全国大反攻，打倒蒋介石》（1947 年 9 月 28 日），据「中文马克思主义文库」"
              "转录的《周恩来选集》上卷文本：全文照录、未作裁剪，一字未改；"
              "篇内 [NN] 编者注保留；篇末「＊一九四六年六月底，蒋介石发动大规模内战……」"
              "题注原样保留。"),
    dict(file="1-关于和平谈判问题的报告.txt", work="关于和平谈判问题的报告", author="周恩来",
         prefix="CH-HPTB-", slug="hptb",
         html=["zhouenlai/055.html"],
         drop_leading=("关于和平谈判问题的报告", "（一九四九年四月十七日）"),
         note="周恩来《关于和平谈判问题的报告》（1949 年 4 月 17 日），据「中文马克思主义文库」"
              "转录的《周恩来选集》上卷文本：全文照录、未作裁剪，一字未改；"
              "篇内「国内和平协定」八条二十四款的具体条目、[NN] 编者注保留；"
              "篇末「＊这是向来北平参加即将召开的新政治协商会议的部分爱国民主人士、"
              "北平一些大学教授做的报告。」题注原样保留。"),
    dict(file="1-老区半老区的土地改革与整党工作.txt", work="老区半老区的土地改革与整党工作",
         author="周恩来", prefix="CH-LQTG-", slug="lqtg",
         html=["zhouenlai/047.html"],
         drop_leading=("老区半老区的土地改革与整党工作", "（一九四八年二月二十二日）"),
         note="周恩来《老区半老区的土地改革与整党工作》（1948 年 2 月 22 日），据"
              "「中文马克思主义文库」转录的《周恩来选集》上卷文本：全文照录、未作裁剪，"
              "一字未改；篇内「第一类地区」「第二类地区」「第三类地区」的分类行与分节序号行、"
              "[NN] 编者注保留；篇末「＊这是为中共中央起草的指示，经毛泽东同志修改过。」"
              "题注原样保留。"),
    dict(file="1-人民政协共同纲领草案的特点.txt", work="人民政协共同纲领草案的特点", author="周恩来",
         prefix="CH-ZXGT-", slug="zxgt",
         html=["zhouenlai/060.html"],
         drop_leading=("人民政协共同纲领草案的特点", "（一九四九年九月二十二日）"),
         note="周恩来《人民政协共同纲领草案的特点》（1949 年 9 月 22 日），据「中文马克思主义"
              "文库」转录的《周恩来选集》上卷文本：全文照录、未作裁剪，一字未改；"
              "篇内「第一是中国人民民主统一战线的问题」至「第八是新民主主义的外交政策问题」"
              "八条分项行、[NN] 编者注保留；篇末「＊一九四九年九月二十一日至三十日，在北京"
              "召开了中国人民政治协商会议第一届全体会议……」题注原样保留。"),
    dict(file="1-恢复生产建设中国.txt", work="恢复生产，建设中国", author="周恩来",
         prefix="CH-HFSC-", slug="hfsc",
         html=["zhouenlai/059.html"],
         drop_leading=("恢复生产，建设中国", "（一九四九年七月二十三日）"),
         note="周恩来《恢复生产，建设中国》（1949 年 7 月 23 日），据「中文马克思主义文库」"
              "转录的《周恩来选集》上卷文本：全文照录、未作裁剪，一字未改；"
              "篇内「第一」「第二」「第三」「第四」四条分项行、[NN] 编者注保留；"
              "篇末「＊这是在全国工会工作会议上的讲话摘要。」题注原样保留——摘要是"
              "《周恩来选集》编辑所为，不是本库所为。"),
    dict(file="1-新民主主义的经济建设.txt", work="新民主主义的经济建设", author="周恩来",
         prefix="CH-XMJJ-", slug="xmjj",
         html=["zhouenlai/051.html"],
         drop_leading=("新民主主义的经济建设", "（一九四八年六月二十一日）"),
         note="周恩来《新民主主义的经济建设》（1948 年 6 月 21 日），据「中文马克思主义文库」"
              "转录的《周恩来选集》上卷文本：全文照录、未作裁剪，一字未改；"
              "本篇是提纲式笔记，原有编号条目与 [NN] 编者注保留。"),

    # ===== D127：考茨基 4 篇（1887 / 1892 / 1898 / 1908）=====
    # 分档说明：考茨基是第二国际理论家，不是马列毛经典作家——BOOKS 里一律记
    # 「正统/0.9」，不占「经典原著/1.0」。理由与库内既有分档一致：其国家与革命
    # 学说后来被列宁《国家与革命》《无产阶级革命和叛徒考茨基》正面批判，
    # 本批只作历史文献与思想史材料（此判断写在 reading_extensions_d127.py 的
    # caution 里，读者可见）。
    # 取文口径：四部均据「中文马克思主义文库」镜像的中译本，原文一字未改；
    # 1892 / 1898 / 1908 三部为长篇，按篇/章标题行裁为节选（进 TRIM 表），
    # 1887 一部篇幅较小（约 12 万汉字），全书照录、不裁。
    # ⚠️ 镜像目录坑：`kautsky/1887/` 是《莫尔及其乌托邦》，本书在 `kautsky/1887b/`。
    dict(file="1-马克思的经济学说.txt", work="马克思的经济学说", author="考茨基",
         prefix="CH-KCJX-", slug="kcjx",
         html=["kautsky/1887b/00.html"]
              + [f"kautsky/1887b/1-{i:02d}.html" for i in range(1, 4)]
              + [f"kautsky/1887b/2-{i:02d}.html" for i in range(1, 11)]
              + [f"kautsky/1887b/3-{i:02d}.html" for i in range(1, 8)]
              + ["kautsky/1887b/04.html"],
         keep_titles=True, keep_first_title=True,
         note="考茨基《马克思的经济学说》（1887），据「中文马克思主义文库」转录的"
              "生活·读书·新知三联书店 1958 年版（区维译，据俄译本转译）：**全书照录、未作裁剪**——"
              "俄译本出版说明、三篇（商品、货币和资本／剩余价值／工资和利润）共二十章、"
              "译后记与各章章末注释全部保留；原文一字未改，只删站点导航行。"
              "本页书在镜像里是 `kautsky/1887b/`（`kautsky/1887/` 是《莫尔及其乌托邦》）。"),
    dict(file="1-爱尔福特纲领解说节选.txt", work="爱尔福特纲领解说（节选）", author="考茨基",
         prefix="CH-AEFT-", slug="aeft",
         html=["kautsky/1892/00a.html", "kautsky/1892/00b.html",
               "kautsky/1892/01.html", "kautsky/1892/02.html",
               "kautsky/1892/03.html", "kautsky/1892/04.html",
               "kautsky/1892/05.html"],
         keep_titles=True, keep_first_title=True,
         note="考茨基《爱尔福特纲领解说》（1892），据「中文马克思主义文库」转录的"
              "生活·读书·新知三联书店 1963 年版（据英译本译出，又据苏联国家政治书籍出版社"
              "1959 年版俄译本并参照日译本校订）**节选**：保留出版者说明、著者第一版序与"
              "「历史部分」三章（第一章 小生产的灭亡／第二章 无产阶级／第三章 资本家阶级，"
              "共十八节）；裁去第四章「未来的国家」、第五章「阶级斗争」。原文一字未改，"
              "边界均为章标题行。"),
    dict(file="1-土地问题节选.txt", work="土地问题（节选）", author="考茨基",
         prefix="CH-TDWT-", slug="tdwt",
         html=["kautsky/1898/00.html"]
              + [f"kautsky/1898/1-{i:02d}.html" for i in range(1, 12)]
              + [f"kautsky/1898/2-{i:02d}.html" for i in range(1, 6)]
              + ["kautsky/1898/3.html"],
         keep_titles=True, keep_first_title=True,
         note="考茨基《土地问题》（1898），据「中文马克思主义文库」转录的生活·读书·新知"
              "三联书店 1955 年版（梁琳即赵济译，据苏联「无产者」出版社 1926 年俄文版转译，"
              "原著德文版 Die Agrarfrage）**节选**：保留著者序与上卷「资本主义社会中农村经济"
              "的发展」前四章（绪论／农民与工业／封建时代的农村经济／现代的农村经济）；"
              "裁去上卷第五章以下九章、下卷「社会民主主义的土地政策」五章与〔附录〕译者简介。"
              "原文一字未改，边界均为章标题行。"),
    dict(file="1-基督教之基础节选.txt", work="基督教之基础（节选）", author="考茨基",
         prefix="CH-JDJC-", slug="jdjc",
         html=[f"kautsky/kautsky-1908/Kautsky-1908book{i:02d}.html" for i in range(1, 22)],
         keep_titles=True, keep_first_title=True,
         note="考茨基《基督教之基础》（1908），据「中文马克思主义文库」转录的叶启芳等译本"
              "（1932 年神州国光社初版，1954 年译者校订重版；英文本据第十三次德文版移译）"
              "**节选**：保留「引论」与「第二篇 罗马帝国时代的社会」全篇（第一章 蓄奴制度／"
              "第二章 国家的生活／第三章 罗马帝国时代之思潮，共十七节）；裁去「第一篇 "
              "耶稣的人格」「第三篇 犹太民族」「第四篇 基督教之起源」，并按行删去各页沿页"
              "重复输出、只留每章首见的「篇 >> 章」标题行与「一 土地所有」等节标题行）。"
              "原文一字未改，"
              "边界均为篇／章标题行。"),
]

# 追加到既有正文（不是新著作）：《资本论》第一卷节选原缺「第二版跋」。
# 取 marx-engels/23/002.html（马恩全集中文第 1 版第 23 卷），与 0-资本论节选.txt 内
# 「《马恩全集》中文版第 13 卷/第 4 卷/第 1 卷」的引用卷次同版，避免同一节选混用两套译文。
APPEND_BA: dict = dict(
    file="0-资本论节选.txt",
    html="marx-engels/23/002.html",
    note="《马恩全集》中文第 1 版第 23 卷《资本论》第一卷『第二版跋』全文（含卷末注释）。"
         "《书籍.md》第 4 阶段明文要求重点章『1/4/5/24/二版跋』，原节选漏收此篇，"
         "本轮按同一版卷次补入，不改动既有正文一字。",
)

# 插入到既有正文（不是新著作）：《资本论》第一卷节选缺「相对剩余价值的生产」整篇。
# 按同一版卷次（马恩全集中文第 1 版第 23 卷）补入第十一／十二／十三章，
# 落点在第二十二章之前，保持全书章次顺序（既不改动任何原有行，也不调整原行位置）。
INSERT_SC: dict = dict(
    file="0-资本论节选.txt",
    anchor="第二十二章 剩余价值转化为资本",
    html=["marx-engels/23/021.html", "marx-engels/23/022.html",
          "marx-engels/23/023.html", "marx-engels/23/024.html"],
    markers=("第十一章。协 作", "第十二章 分工和工场手工业",
             "第十三章 机器和大工业。1—5"),
    note="《马恩全集》中文第 1 版第 23 卷《资本论》第一卷第十一章「协作」、"
         "第十二章「分工和工场手工业」、第十三章「机器和大工业」（1—10 节，含卷末注释）全文。"
         "镜像把第十三章拆为 1—5、6-10 两页，第二页页头的「。6-10」是站点页码区间（导航），"
         "已按行删除；其余一字未改。插入位置在第二十二章之前，不动任何原有行。",
)


# ============================================================================
# D101：按学习路线裁剪 9 部长篇（方案 1：只保留符合路线要求的章节）
# ----------------------------------------------------------------------------
# 每段 = (start_marker, start_nth, end_marker, end_nth)
#   * marker 为「strip 后完全相等」的独立标题行；nth 为第 n 次出现（1-based）
#   * start_marker=None → 从文件第 0 行开始；end_marker=None → 到文件末尾
#   * 保留 [start, end) 的整行，边界均落在章节标题行，绝不截断段落
#   * 原文一字不改，只做「删去未选章节」；每段 desc 供文档/测试核对
# ============================================================================
TRIM: dict[str, dict] = {
    # ===== D117：邓中夏工运史只取第五、七、九章（边界均落在章标题行）=====
    "1-中国职工运动简史节选.txt": dict(
        desc="保留著者申明、第五章（第一次全国劳动大会及劳动立法运动）、"
             "第七章（京汉路大罢工——“二七”惨杀）、第九章（职工运动复兴期）；"
             "裁去第一至四章、第六章、第八、十至十三章",
        segments=[
            (None, 1, "第一章 原始的职工运动", 1),
            ("第五章 第一次全国劳动大会及劳动立法运动", 1,
             "第六章 开滦五矿大罢工", 1),
            ("第七章 京汉路大罢工——“二七”惨杀", 1,
             "第八章 职工运动消沉期", 1),
            ("第九章 职工运动复兴期", 1,
             "第十章 上海日本纱厂大罢工", 1),
        ]),
    # ===== D103：毛泽东 8 篇 + 列宁/斯大林/马恩 8 部（按合适章节节选，不整篇照录）=====
    "5-中国革命战争的战略问题.txt": dict(
        desc="保留题解、第一章「如何研究战争」四节（战争规律是发展的／战争的目的在于消灭战争／"
             "战略问题是研究战争全局的规律的东西／重要的问题在善于学习）、第二章"
             "「中国共产党和中国革命战争」、第三章「中国革命战争的特点」三节、"
             "第四章「『围剿』和反『围剿』」；裁去第五章「战略防御」全部战术诸节与卷末注释",
        segments=[
            (None, 1, "第五章 战略防御", 1),
        ]),
    "5-抗日游击战争的战略问题.txt": dict(
        desc="保留第一至四章（为何提战略问题／战争的基本原则是保存自己消灭敌人／六个具体战略问题／"
             "主动性灵活性计划性）；裁去第五章配合方式、第六至九章根据地与战略防御进攻、指挥关系与注释",
        segments=[
            (None, 1, "第五章 和正规战争相配合", 1),
        ]),
    "5-战争和战略问题.txt": dict(
        desc="保留题解、「一 中国的特点和革命」、「三 中国共产党的战争史」至「五 抗日游击战争的战略地位」；"
             "裁去「二 中国国民党的战争史」、「六 注意研究军事问题」与卷末注释",
        segments=[
            (None, 1, "二 中国国民党的战争史", 1),
            ("三 中国共产党的战争史", 1, "六 注意研究军事问题", 1),
        ]),
    "5-井冈山的斗争.txt": dict(
        desc="保留题解、湘赣边界的割据和八月失败、割据地区的现势、土地问题、政权问题、党的组织问题、"
             "革命性质问题、割据地区问题；裁去「军事问题」细部与卷末注释",
        segments=[
            (None, 1, "军事问题", 1),
            ("土地问题", 1, "注释", 1),
        ]),
    "5-中国的红色政权为什么能够存在.txt": dict(
        desc="保留「一 国内的政治状况」、「二 中国红色政权发生和存在的原因」、"
             "「五 经济问题」；裁去三、四节具体割据形势、「六 军事根据地问题」与卷末注释",
        segments=[
            (None, 1, "三 湘赣边界的割据和八月的失败", 1),
            ("五 经济问题", 1, "六 军事根据地问题", 1),
        ]),
    "5-论反对日本帝国主义的策略.txt": dict(
        desc="保留目前政治形势的特点、民族统一战线、人民共和国、国际援助四节全文；裁去卷末注释",
        segments=[
            (None, 1, "注释", 1),
        ]),
    "5-学习和时局.txt": dict(
        desc="保留正文三节（一、二、三）；刻意不收网页所附《关于若干历史问题的决议》与卷末注释，"
             "并删掉网页插在日期后的「附录」指路行（该决议是党的文献、非毛泽东著作）",
        segments=[
            (None, 1, "注释", 1),
        ],
        drop=[("· 附录：关于若干历史问题的决议", 1)]),
    "5-在省市自治区党委书记会议上的讲话.txt": dict(
        desc="保留「一 一月十八日的讲话」全文与「二 一月二十七日的讲话」前五点"
             "（至「第五点，闹事问题」全节——两类矛盾学说落到具体事件上的操作示范）；"
             "裁去「第六点，法制问题」及其后的农业、出版信息与卷末注释",
        segments=[
            (None, 1, "第六点，法制问题。讲三条：一定要守法，一定要肃反，一定要肯定肃反的成绩。", 1),
        ]),
    "1-评经济浪漫主义.txt": dict(
        desc="保留题名/副题、「第二章 浪漫主义者对资本主义的批评的性质」全章"
             "（浪漫主义批评的性质、小资产阶级性、反动性——批判民粹派的方法论示范）；"
             "裁去第一章对西斯蒙第国民收入论、国内市场理论的经济学史长篇考据与卷末注释",
        segments=[
            (None, 1, "第一章", 1),
            ("第二章", 1, "注释：", 1),
        ]),
    "1-马克思主义和语言学问题.txt": dict(
        desc="保留「论语言学中的马克思主义」全文（基础与上层建筑、语言无阶级性）；"
             "裁去后四篇答复与卷末注",
        segments=[
            ("马克思主义和语言学问题", 2, "论语言学的几个问题", 1),
        ]),
    "1-马克思主义和民族问题.txt": dict(
        desc="保留「一 民族」（民族四特征的定义）、「二 民族运动」、「三 问题的提法」、"
             "「七 俄国的民族问题」；裁去四、五、六节民族文化自治论战细部与注释",
        segments=[
            (None, 1, "四 民族文化自治", 1),
            ("七 俄国的民族问题", 1, None, 1),
        ]),
    "2-无政府主义还是社会主义.txt": dict(
        desc="保留「一 辩证方法」全节（辩证唯物主义原理的通俗系统表述）；"
             "裁去「二 唯物主义」「三 无产阶级社会主义」下篇与卷末注",
        segments=[
            (None, 1, "二 唯物主义理论", 1),
        ]),
    "2-1848年至1850年的法兰西阶级斗争.txt": dict(
        desc="保留题解与「一 1848年的六月失败」、「四 1850年普选权的废除」；"
             "裁去第二、三节事件经过细部与卷末注释",
        segments=[
            (None, 1, "二 1849年6月13日", 1),
            ("四 1850年普选权的废除", 1, "卡·马克思写于1849年底1850年3月底和1850年10月—11月1日", 1),
        ]),
    "2-德国农民战争.txt": dict(
        desc="保留 1870 年第二版序言与「1870年第二版序言的补充」、第一章「一」"
             "（16 世纪初期德国状况的唯物史观分析）；裁去第二至七章战争史叙述与卷末注释",
        segments=[
            (None, 1, "二", 1),
        ]),
    "0-哲学的贫困.txt": dict(
        desc="保留题名/题解/序言、第一章第一节「使用价值和交换价值的对立」、"
             "第二章第一节「方法」；裁去蒲鲁东价值论细部与分工/机器、竞争、地租、罢工等专论",
        segments=[
            (None, 1, "第二节 构成价值或综合价值", 1),
            ("第二章 政治经济学的形而上学", 1, "第二节 分工和机器", 1),
        ]),
    "1-两种策略.txt": dict(
        desc="保留卷首题解/注释（说明写作背景）、第 10 节「革命公社」与工农革命民主专政、"
             "第 13 节结论「我们敢不敢胜利？」；裁去 1—9、11、12 节俄国内派别论战细节与补充说明",
        segments=[
            (None, 1, "1．一个迫切的政治问题", 1),
            ("10．“革命公社”与无产阶级和农民的革命民主专政", 1, "11．俄国社会民主工党第三次代表大会某些决议", 1),
            ("13．结论。我们敢不敢胜利？", 1, "补充说明再论解放派，再论新火星派", 1),
        ]),
    "5-中国革命和中国共产党.txt": dict(
        desc="保留题名/合著题解、第一章第三节「现代的殖民地、半殖民地和半封建社会」"
             "（国情判断）、第二章「中国革命」全章；裁去第一、二节古代社会史料细部与卷末注释",
        segments=[
            (None, 1, "第一章 中国社会", 1),
            ("第三节 现代的殖民地、半殖民地和半封建社会", 1, "第二章 中国革命", 1),
            ("第二章 中国革命", 1, "注释", 1),
        ]),
    "5-论联合政府.txt": dict(
        desc="保留「一 中国人民的基本要求」、第四章总论与「我们的一般纲领／具体纲领」"
             "（建国方略）、第五章全党团结；裁去国际国内形势、两条路线论战、逐条政策罗列与尾注",
        segments=[
            (None, 1, "二 国际形势和国内形势", 1),
            ("四 中国共产党的政策", 1, "第一 彻底消灭日本侵略者，不许中途妥协", 1),
            ("五 全党团结起来，为实现党的任务而斗争", 1, "注释", 1),
        ]),
    "5-论持久战.txt": dict(
        desc="保留「问题的提起」「问题的根据」、「亡国论是不对的，速胜论也是不对的」"
             "与「持久战的三个阶段」、「能动性在战争中」、「兵民是胜利之本」与结论；"
             "裁去驳亡国论细部、犬牙交错/具体战役部署、运动战等军事技术章与尾注",
        segments=[
            (None, 1, "驳亡国论", 1),
            ("亡国论是不对的，速胜论也是不对的", 1, "犬牙交错的战争", 1),
            ("能动性在战争中", 1, "战争和政治", 1),
            ("兵民是胜利之本", 1, "注释", 1),
        ]),
    "0-社会主义从空想到科学的发展.txt": dict(
        desc="保留题名页、马克思写的 1880 年法文版前言、正文「一／二／三」三章及文集注释；"
             "裁去 1882 德文版序言、1891 德文第四版序言、1892 英文版导言（与 A 路线唯物史观主线重复）",
        segments=[
            (None, 1, "1882年德文第一版序言 〔257〕", 1),
            ("社会主义从空想到科学的发展", 2, None, 1),
        ]),
    "1-进一步退两步.txt": dict(
        desc="保留卷首/序言、第（七）—（九）节党章第一条与组织原则（民主集中制原始论证）、"
             "第（十八）节「稍微谈谈辩证法。两个变革」；裁去代表大会逐日记录、选举细节、"
             "会后派别斗争与附录",
        segments=[
            (None, 1, "（一）代表大会的准备", 1),
            ("（七）党章。马尔托夫同志的草案", 1, "（十）无辜被加上莫须有的机会主义罪名的人", 1),
            ("（十八）稍微谈谈辩证法。两个变革", 1, "附录", 1),
        ]),
    "1-无产阶级革命和叛徒考茨基.txt": dict(
        desc="保留题名/目录、序言、「考茨基怎样把马克思变成了庸俗的自由主义者」、"
             "「资产阶级民主和无产阶级民主」、「苏维埃不得变成国家组织」"
             "（无产阶级专政与民主的主体论证）；裁去立宪会议以后各节、经济分析辩驳与两个附录",
        segments=[
            (None, 1, "立宪会议和苏维埃共和国", 1),
        ]),
    "5-论列宁主义的几个问题.txt": dict(
        desc="保留题名/刊印说明、第六节「关于社会主义在一个国家内胜利的问题」、"
             "第七节「为社会主义建设的胜利而奋斗」；裁去前五节列宁主义定义、党内反对派论战",
        segments=[
            (None, 1, "一 列宁主义的定义", 1),
            ("六 关于社会主义在一个国家内胜利的问题", 1, "七 为社会主义建设的胜利而奋斗", 1),
            ("七 为社会主义建设的胜利而奋斗", 1, None, 1),
        ]),

    # ===== D104：P0+P1 中确需节选的 4 部（其余 22 部为单篇全文／小节全文，不裁）=====
    "1-大难临头出路何在.txt": dict(
        desc="保留题名、原书目录与正文前五节（饥荒逼近／政府不起作用／"
             "监督办法是众所周知和轻而易举的／银行国有化／辛迪加国有化／取消商业秘密／"
             "强迫参加联合组织／调节消费，即「政府破坏民主组织的工作」之前六节）；"
             "裁去「政府破坏民主组织的工作」「财政破产和挽救的办法」「消除经济破坏」"
             "「革命民主派和革命无产阶级」等后六节与卷末注释",
        segments=[
            (None, 1, "政府破坏民主组织的工作", 1),
        ]),
    "3-反杜林论政治经济学篇.txt": dict(
        desc="保留第二编题名、「一 对象和方法」（政治经济学对象与广义／狭义定义）、"
             "「二 暴力论」「三 暴力论（续）」「四 暴力论（续完）」；"
             "裁去「五 价值论」及其后的简单劳动和复合劳动、资本和剩余价值、《批判史》论述与注释",
        segments=[
            (None, 1, "五 价值论", 1),
        ]),
    "3-自然辩证法辩证法作为科学.txt": dict(
        desc="保留［辩证法作为科学］篇名与「辩证法」一文（辩证法的一般性质与三大规律）、"
             "「偶然性和必然性」；裁去［札记和片断］其余条目、「认识」以下各篇与注释",
        segments=[
            (None, 1, "［札记和片断］", 1),
            ("偶然性和必然性", 1, "［认识］", 1),
        ]),

    # ===== D105：所选 11 个章节文件全文保留；只删网页每页重复的卷名页头 =====
    "4-剩余价值理论节选.txt": dict(
        desc="所选的 11 个章节文件全文保留；仅删去网页沿页重复输出的「第二十六卷（I）」页头行"
             "（版式噪声，不是原书文字）",
        segments=[
            (None, 1, None, 1),
        ],
        collapse_blank=True,
        drop=[("第二十六卷（I）", 1)]),

    # ===== D116：3 篇毛泽东短篇只裁卷末注释，2 篇刘少奇按节保留 =====
    "5-关心群众生活注意工作方法.txt": dict(
        desc="保留题注与两个问题的全部正文；裁去卷末 6 条注释（版式与注释性附录）",
        segments=[
            (None, 1, "注释", 1),
        ]),
    "5-农村调查的序言和跋.txt": dict(
        desc="保留题名行与序（1941.3.17）、跋（1941.4.19）全部正文；裁去卷末 6 条注释",
        segments=[
            (None, 1, "注释", 1),
        ]),
    "5-组织起来.txt": dict(
        desc="保留题注与大会讲话全部正文；裁去卷末 5 条注释",
        segments=[
            (None, 1, "注释", 1),
        ]),
    "1-关于白区的党和群众工作.txt": dict(
        desc="保留题名行、「党和群众的关系」「公开工作和秘密工作的联系」二节与「党的转变」"
             "前四节（至「（五）一切工作，一切转变，都依靠我们的干部……」之前）；"
             "裁去「彻底的转变」一节、「党的转变」后五节与卷末 4 条注释",
        segments=[
            (None, 1, "彻底的转变", 1),
            ("党和群众的关系", 1, "党的转变", 1),
            ("党的转变", 1,
             "（五）一切工作，一切转变，都依靠我们的干部，因此干部问题是党内的中心问题。"
             "训练出大批的干部分配到各条战线上去，是党的中心工作。各地方要特别注意"
             "选择干部来受训练。", 1),
        ]),
    "1-怎样进行群众工作.txt": dict(
        desc="保留开篇与（一）至（四）四节；裁去（五）群众团体的不同性质、"
             "（六）人民阵线与结尾口号，以及卷末注释",
        segments=[
            (None, 1, "（五）", 1),
        ]),
    # ===== D123：恽代英两篇按讲次／小节标题节选 =====
    "1-中国民族革命运动史节选.txt": dict(
        desc="保留题名、系年、原书说明行与讲次目录（第一至七讲），"
             "以及第五讲「辛亥革命运动」、第六讲「五四运动前后的国民党」、"
             "第七讲「五卅运动」三讲正文；裁去第一至四讲正文",
        segments=[
            (None, 1, "第一讲 由反清复明运动至鸦片战争", 2),
            ("第五讲 辛亥革命运动", 2, None, 0),
        ],
    ),
    "1-答醒狮周报三十二期的质难节选.txt": dict(
        desc="保留「一 民族解放运动决不是甚么『国家主义』」与"
             "「二 谁能担保革命者不『出卖』救国事业」两节，"
             "裁去「三 联俄便是倚赖外力么？」与「四 答余家菊君的五个问题」；"
             "篇末载行、署名与注① 保留",
        segments=[
            (None, 1, "三 联俄便是倚赖外力么？", 1),
            ("载《中国青年》第82期", 1, None, 0),
        ],
    ),
    # ===== D125：列宁《卡尔·马克思》只取世界观概述（哲学部分）=====
    "1-卡尔马克思传略和马克思主义概述节选.txt": dict(
        desc="保留「序言」、马克思传略、「马克思的学说」下的「哲学唯物主义」「辩证法」"
             "「唯物主义历史观」「阶级斗争」四节；裁去「马克思的经济学说」「社会主义」"
             "「无产阶级阶级斗争的策略」「书目」四节",
        segments=[
            (None, 1, "马克思的经济学说", 1),
        ],
    ),

    # ===== D127：考茨基 3 部长篇按篇／章标题行裁为节选 =====
    # 《爱尔福特纲领解说》：原书分「历史部分」（第一至三章）与「理论部分」
    # （第四章 未来的国家、第五章 阶级斗争）。本库取历史部分：它按生产过程
    # 推小生产灭亡、无产阶级与资本家阶级的形成，是历史唯物主义落到经济史
    # 上的完整叙述；理论部分（未来国家构想）是后来被列宁批判的那一段，
    # 且与 sec_C_02 的社会主义构想章重复，故不取。
    "1-爱尔福特纲领解说节选.txt": dict(
        desc="保留出版者说明、著者第一版序与第一至三章（小生产的灭亡／无产阶级／"
             "资本家阶级，共十八节）；裁去第四章「未来的国家」与第五章「阶级斗争」",
        segments=[
            (None, 1, "第四章 未来的国家", 1),
        ],
    ),

    # 《土地问题》：原书分上下卷。上卷讲资本主义农业的发展（第一至五章）与
    # 大生产小生产之争（第六至十一章），下卷讲社会民主党的土地政纲（第一章
    # 至第五章）。本库取著者序与上卷前四章（绪论／农民与工业／封建时代的
    # 农村经济／现代的农村经济）：这是「资本主义农业怎样从封建农村里长出来」
    # 的完整链条，止于第五章「现代农村经济的资本主义性质」之前。
    "1-土地问题节选.txt": dict(
        desc="保留著者序与上卷第一至四章（绪论／农民与工业／封建时代的农村经济／"
             "现代的农村经济）；裁去上卷第五至十一章、下卷五章与〔附录〕译者简介",
        segments=[
            (None, 1, "第五章 现代农村经济的资本主义性质", 1),
        ],
    ),

    # 《基督教之基础》：全书四篇。本库只取「引论」与第二篇「罗马帝国时代的社会」
    # （第一章 蓄奴制度、第二章 国家的生活、第三章 罗马帝国时代之思潮，共十七节）：
    # 这一篇是唯物史观分析古代社会结构（奴隶制经济→国家→思想）的完整样本；
    # 第一篇（耶稣的人格）与第三、四篇（犹太民族、基督教之起源）属神学考据，不取。
    # drop 里列的是镜像每页沿页重复输出的站点头部行（书名行 + 「篇 >> 章」指示行），
    # 逐页各出现一次；按「第 1 次出现」逐条列，删完为止，不是原书文字。
    "1-基督教之基础节选.txt": dict(
        desc="保留「引论」与第二篇「罗马帝国时代的社会」全篇（第一章 蓄奴制度、"
             "第二章 国家的生活、第三章 罗马帝国时代之思潮，共十七节）；"
             "裁去第一篇「耶稣的人格」、第三篇「犹太民族」、第四篇「基督教之起源」，"
             "并按行删去每页重复的站点头部行",
        segments=[
            (None, 1, "第一篇 耶稣的人格", 1),
            ("第二篇 罗马帝国时代的社会 >> 第一章 蓄奴制度", 1, None, 1),
        ],
        collapse_blank=True,
        # 镜像把篇名与章名写在同一行（「篇 >> 章」），所以每章第一页的这一行
        # 就是该章标题行，保留；后面各页重复输出的同名行删去。
        # 删「第 2 次出现」而不是第 1 次：每删一次，第 2 次就往后挪一位，
        # 循环删到底就只剩每章首见的那一行（章标题留在章首）。
        drop=([("考茨基：基督教之基础", 1)] * 18
              + [("第二篇 罗马帝国时代的社会 >> 第一章 蓄奴制度", 2)] * 4
              + [("第二篇 罗马帝国时代的社会 >> 第二章 国家的生活", 2)] * 4
              + [("第二篇 罗马帝国时代的社会 >> 第三章 罗马帝国时代之思潮", 2)] * 6)),
}


def _nth_line(stripped: list[str], marker: str | None, nth: int, file: str) -> int:
    """定位第 nth 次出现的章节标题行；marker=None 表示文件首行。"""
    if marker is None:
        return 0
    seen = 0
    for i, line in enumerate(stripped):
        if line == marker:
            seen += 1
            if seen == nth:
                return i
    raise RuntimeError(f"裁剪 marker 未命中: {file} → {marker!r}（第 {nth} 次）")


def apply_trim(file: str, text: str) -> str:
    """按 TRIM 保留指定章节区间；原文一字不改，只删未选章节的整行。

    幂等性由「从镜像重新 build 出全文后再裁」保证：不对已裁文件二次裁剪。
    """
    cfg = TRIM.get(file)
    if not cfg:
        return text
    lines = text.splitlines()
    stripped = [ln.strip() for ln in lines]
    kept: list[str] = []
    prev_end = 0
    for start, start_nth, end, end_nth in cfg["segments"]:
        i = _nth_line(stripped, start, start_nth, file)
        j = len(lines) if end is None else _nth_line(stripped, end, end_nth, file)
        if i < prev_end or j <= i:
            raise RuntimeError(f"裁剪区间重叠/倒序: {file} L{i}..L{j}")
        if not lines[i].strip() or (j < len(lines) and not lines[j].strip()):
            raise RuntimeError(f"裁剪边界不在章节标题行: {file} L{i}..L{j}")
        kept.extend(lines[i:j])
        if kept and kept[-1].strip():
            kept.append("")
        prev_end = j
    # 可选 drop：(marker, nth) 逐个删掉「夹在保留区间内、但属网页噪声或附录指路」的单行。
    # 原文其余一字不改；marker 未命中会直接报错，不会静默放过。
    for _marker, _nth in cfg.get("drop", []):
        _k = _nth_line([ln.strip() for ln in kept], _marker, _nth, file)
        del kept[_k]
        # 删掉的行若是沿页重复的页头，其前后往往各有一个空行；
        # cfg["collapse_blank"]（D105 起）要求再删一个空行，使段落间距恒定。
        # 默认不开启：D103/D104 的现库产物按旧行为存盘，改动会使复现比对失真。
        if cfg.get("collapse_blank") and _k < len(kept) and not kept[_k].strip() \
                and _k > 0 and not kept[_k - 1].strip():
            del kept[_k]
    out = "\n".join(kept).rstrip() + "\n"
    if len(out) >= len(text):
        raise RuntimeError(f"裁剪未生效（疑似 marker 失效）: {file}")
    return out


# D102 标题修复涉及的 5 部早期著作。`--no-keep-titles` 只还原这 5 部：
# D100 那 3 部（哲学的贫困 / 两种策略 / 宁肯少些但要好些）自建库起就带
# keep_titles=True，且 TRIM 边界依赖其标题行，绝不能被这个开关剥掉。
D102_TITLE_FILES = frozenset({
    "3-唯物主义和经验批判主义.txt",
    "4-资本论第二卷.txt",
    "4-资本论第三卷.txt",
    "3-论一元论历史观的发展.txt",
    "3-思想起源论.txt",
})


def build(spec: dict, *, trim: bool = True, keep_titles: bool = True) -> tuple[str, int]:
    """keep_titles=False 只把 D102_TITLE_FILES 这 5 部还原为修复前拼接产物。

    D100 自建库起就带 keep_titles=True 的 3 部不受影响（TRIM 边界依赖其标题行）。
    """
    parts: list[str] = [spec["work"], ""]
    n_files = 0
    for idx, rel in enumerate(spec.get("html", [])):
        p = MIRROR / Path(*rel.split("/"))
        if not p.exists():
            raise FileNotFoundError(f"镜像缺文件: {rel}")
        # keep_titles：后续分文件首行是章节标题，必须保留。
        # · D100 用于新补录的 3 部多文件著作；
        # · D102 用于早期 5 部（唯批 / 资本论二、三卷 / 一元论历史观 / 思想起源论）：
        #   实测这 5 部共 36 个章节标题行被 strip_title_repeat 误删，逐行复核均为
        #   合法独立标题（非导航、非重复输出），故按 keep_titles=True 脚本化补回。
        #   备份在 sources/_backup_d102_pretitle/；其余 SPECS 行为完全不变。
        # keep_titles=False 只作用于 D102 这 5 部；D100 3 部必须保留标题行，
        # 否则 apply_trim() 的章节 marker 会未命中，整库 dry-run 直接失败。
        d102 = spec["file"] in D102_TITLE_FILES
        # keep_first_title：D105 起用于「首文件首行本身就是『序言／前言／第一章』标题」的著作；
        # 默认 False（首文件按 <title> 重复行剔除），不影响 D100/D101/D102/D103/D104。
        strip_repeat = ((idx == 0 and not spec.get("keep_first_title"))
                        or (d102 and not keep_titles)
                        or (not spec.get("keep_titles")))
        lines = html_to_lines(p, strip_title_repeat=strip_repeat)
        # drop_leading：D121 起用于「网页顶部把篇名/作者名再输出一遍、且 <title>
        # 形如『作者：篇名（年份）』导致 strip_title_repeat 无法匹配」的页面。
        # 只从首文件头部连续删除、且只删精确等于这些串的行；遇到第一个不在集合内的行即停，
        # 不会误删正文。未声明该键的既有权重零影响。
        _drop = set(spec.get("drop_leading", ()))
        if _drop:
            while lines and lines[0].strip() in _drop:
                lines.pop(0)
        if not lines:
            raise RuntimeError(f"抽取为空: {rel}")
        n_files += 1  # 已核验文件存在
        # 【关键】text_loader.read_paragraphs() 按 \n\s*\n 切段，
        # 因此每行之后补一空行，让每个自然行成为独立段落（不塌成一大段）。
        parts.extend(x + "\n" for x in lines)
        parts.append("")
    for pdf_rel, p_start, p_end in spec.get("pdf", []):
        if not (MIRROR / Path(*pdf_rel.split("/"))).exists():
            raise FileNotFoundError(f"镜像缺 PDF: {pdf_rel}")
        plines = pdf_lines((p_start, p_end), pdf_rel)
        paras = merge_pdf_lines(plines)
        if not paras:
            raise RuntimeError(f"PDF 抽取为空: {pdf_rel} {p_start}-{p_end}")
        n_files += 1
        parts.extend(x + "\n" for x in paras)
        parts.append("")
    if n_files == 0:
        raise RuntimeError(f"无来源: {spec['file']}")
    text = "\n".join(parts).rstrip() + "\n"
    if trim:
        text = apply_trim(spec["file"], text)
    cn = len(re.findall(r"[\u4e00-\u9fff]", text))
    return text, cn


def append_ba(out_dir: Path) -> tuple[str, int]:
    """把《资本论》第一卷「第二版跋」追加到既有节选正文。

    幂等：以「独立成段的『第二版跋』标题」为标记，重复运行不会重复追加；
    dry-run 时先把 TEXTS 里的原文件复制到 .local/mirror_extract/ 再追加，
    保证正式入库与 dry-run 的产物完全一致。不改动既有正文一字。
    """
    target = out_dir / APPEND_BA["file"]
    src = TEXTS / APPEND_BA["file"]
    if not target.exists():
        if not src.exists():
            raise FileNotFoundError(f"追加目标不存在: {src}")
        target.write_bytes(src.read_bytes())
    old = target.read_text(encoding="utf-8")
    paras = html_to_lines(MIRROR / Path(*APPEND_BA["html"].split("/")))
    if not paras:
        raise RuntimeError(f"抽取为空: {APPEND_BA['html']}")
    if "\n第二版跋\n" in old:
        return "已存在，跳过", 0
    block = "\n\n".join(paras) + "\n"
    new = old.rstrip("\n") + "\n\n" + block
    target.write_text(new, encoding="utf-8", newline="\n")
    cn = len(re.findall(r"[\u4e00-\u9fff]", block))
    return f"追加 {len(paras)} 段", cn


def insert_sc(out_dir: Path) -> tuple[str, int]:
    """把《资本论》第一卷第十一／十二／十三章插入既有节选正文（幂等）。

    只插入、不重写：锚点行「第二十二章」及其前后原有行一个字节不改；
    dry-run 时同样先把 TEXTS 的原文件复制到 .local/mirror_extract/ 再插入，
    保证试跑与正式入库的产物完全一致。
    """
    target = out_dir / INSERT_SC["file"]
    src = TEXTS / INSERT_SC["file"]
    if not target.exists():
        if not src.exists():
            raise FileNotFoundError(f"插入目标不存在: {src}")
        target.write_bytes(src.read_bytes())
    old = target.read_text(encoding="utf-8")
    if all(f"\n{m}\n" in old for m in INSERT_SC["markers"]):
        return "已存在，跳过", 0
    block: list[str] = []
    seen_ch13 = False
    for rel in INSERT_SC["html"]:
        lines = html_to_lines(MIRROR / Path(*rel.split("/")), strip_title_repeat=False)
        if not lines:
            raise RuntimeError(f"抽取为空: {rel}")
        if lines[0].startswith("第十三章 机器和大工业"):
            if seen_ch13:
                # 镜像把第 13 章分两页；第二页页头「。6-10」是页码区间（导航），按行删除
                lines = lines[1:]
            else:
                seen_ch13 = True
        block.extend(lines)
    body = "\n\n".join(block)
    anchor = INSERT_SC["anchor"]
    old_lines = old.splitlines()
    idx = [i for i, ln in enumerate(old_lines) if ln.strip() == anchor]
    if len(idx) != 1:
        raise RuntimeError(
            f"插入锚点不唯一: {INSERT_SC['file']} → {anchor!r} 命中 {len(idx)} 次")
    i = idx[0]
    new_lines = old_lines[:i] + body.splitlines() + [""] + old_lines[i:]
    target.write_text("\n".join(new_lines).rstrip("\n") + "\n",
                      encoding="utf-8", newline="\n")
    cn = len(re.findall(r"[\u4e00-\u9fff]", body))
    return f"插入 {len(block)} 段", cn


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--pdf-probe", action="store_true")
    ap.add_argument("--no-trim", action="store_true",
                    help="生成 D101 裁剪前的全文（复核/回退用）")
    ap.add_argument("--no-keep-titles", action="store_true",
                    help="只把 D102 修复的 5 部还原为修复前拼接产物（D100 3 部不受影响，复核/回退用）")
    args = ap.parse_args()
    if not (args.dry_run or args.write or args.pdf_probe):
        ap.print_help()
        return 1

    if args.pdf_probe:
        for spec in SPECS:
            if not spec.get("pdf"):
                continue
            for pdf_rel, a, b in spec["pdf"]:
                ls = pdf_lines((a, b), pdf_rel)
                ps = merge_pdf_lines(ls)
                cn = sum(len(re.findall(r"[\u4e00-\u9fff]", x)) for x in ps)
                print(f"  {spec['file']}: {pdf_rel} p{a}-{b} -> {len(ls)} 行 / {len(ps)} 段 / {cn} 汉字")
                print("    HEAD:", " | ".join(x[:70] for x in ps[:3]))
                print("    TAIL:", " | ".join(x[:70] for x in ps[-3:]))
        return 0

    out_dir = TEXTS if args.write else DRY
    out_dir.mkdir(parents=True, exist_ok=True)
    total = 0
    print(f"镜像: {MIRROR}")
    print(f"输出: {out_dir}  ({'正式入库' if args.write else 'dry-run'})")
    print("-" * 100)
    for spec in SPECS:
        try:
            text, cn = build(spec, trim=not args.no_trim,
                             keep_titles=not args.no_keep_titles)
        except Exception as exc:
            print(f"!! {spec['file']}: {exc}")
            return 2
        (out_dir / spec["file"]).write_text(text, encoding="utf-8", newline="\n")
        total += cn
        print(f"  {cn:>8} 汉字  {len(text):>8} 字符  {spec['file']}")
    if not args.pdf_probe:
        try:
            status, ba_cn = append_ba(out_dir)
        except Exception as exc:
            print(f"!! 追加《第二版跋》失败: {exc}")
            return 2
        total += ba_cn
        print(f"  {ba_cn:>8} 汉字  {'':>8}        {APPEND_BA['file']}（第二版跋 {status}）")
        try:
            sc_status, sc_cn = insert_sc(out_dir)
        except Exception as exc:
            print(f"!! 插入第十一／十二／十三章失败: {exc}")
            return 2
        total += sc_cn
        print(f"  {sc_cn:>8} 汉字  {'':>8}        {INSERT_SC['file']}（第十一至十三章 {sc_status}）")
    print("-" * 100)
    print(f"共 {len(SPECS)} 部 + 1 篇追加 + 3 章插入，{total} 汉字")
    return 0


if __name__ == "__main__":
    sys.exit(main())
