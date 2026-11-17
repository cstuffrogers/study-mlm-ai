"""原生原著分片 — 从 sources/texts/*.txt 抽取真实原著正文分片

与 theses_annotations.build_chunks()（《提纲》人工四层分片）互补：
  - 《关于费尔巴哈的提纲》走人工逐条四层分片（layer 1-4，权威注解）
  - 其余已入正文的原著走本模块「自动分段 + 依据表意抽概念 mention」

正统性红线：
  - 本模块只处理「已入正文」的原著（sources/texts/*.txt），分片 text 均为原文照录，
    不做任何改写或润色；
  - 未入库的原著一律不在此伪造，章节导读仍沿用 chapter_content 的「导读」声明。

数据来源：www.marxists.org 中文马克思主义文库镜像（已由项目方提供原件/文字版）。
"""
from __future__ import annotations

import logging
import re
from functools import lru_cache

logger = logging.getLogger(__name__)


# 已登记的原著（file 对应 sources/texts/ 下的文件名；缺失则跳过）
# 说明：全部来自本地镜像（中文马克思主义文库）HTML 去标签、UTF-8 纯文本，
# 正文照录不改写；id_prefix 保证分片 id 全局唯一。
BOOKS: list[dict] = [
    dict(
        file="0-大众哲学.txt",
        work="大众哲学",
        author="艾思奇",
        id_prefix="CH-DZ-",
        slug="dz",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        # 阶段0 必读：斯大林《辩证唯物主义和历史唯物主义》(1938)。
        # 正文由 1949/1956 人民出版社繁体扫描版 OCR（无文字层）逐页识别，
        # 已做繁→简与少量确定性错字校正，个别处或有个别识别误差。
        file="1-辩证唯物主义与历史唯物主义.txt",
        work="辩证唯物主义和历史唯物主义",
        author="斯大林",
        id_prefix="CH-SDL-",
        slug="sdl",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        # 教科书：艾思奇主编《辩证唯物主义 历史唯物主义》(人民出版社 1961/1978)。
        # 363 页扫描件（无文字层）逐页 OCR，已在行内/页脚做清洗与繁→简，
        # 篇章结构完整（绪论 + 上篇辩证唯物主义 8 章 + 下篇历史唯物主义 8 章）。
        file="0-辩证唯物主义历史唯物主义（艾思奇）.txt",
        work="辩证唯物主义历史唯物主义（艾思奇）",
        author="艾思奇",
        id_prefix="CH-DZJX-",
        slug="dzjx",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-哲学笔记.txt",
        work="哲学笔记",
        author="列宁",
        id_prefix="CH-ZXBJ-",
        slug="zxbj",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    # —— 路线 A/B/C 经典原著（本轮从本地镜像补齐）——
    dict(
        file="2-实践论.txt",
        work="实践论",
        author="毛泽东",
        id_prefix="CH-SJL-",
        slug="sjl",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-矛盾论.txt",
        work="矛盾论",
        author="毛泽东",
        id_prefix="CH-MDL-",
        slug="mdl",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="5-中国社会各阶级的分析.txt",
        work="中国社会各阶级的分析",
        author="毛泽东",
        id_prefix="CH-JJFX-",
        slug="jjfx",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="5-反对本本主义.txt",
        work="反对本本主义",
        author="毛泽东",
        id_prefix="CH-FDBB-",
        slug="fdbb",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="5-新民主主义论.txt",
        work="新民主主义论",
        author="毛泽东",
        id_prefix="CH-XMZ-",
        slug="xmz",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="5-论人民民主专政.txt",
        work="论人民民主专政",
        author="毛泽东",
        id_prefix="CH-RMZ-",
        slug="rmz",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="5-论十大关系.txt",
        work="论十大关系",
        author="毛泽东",
        id_prefix="CH-SDGX-",
        slug="sdgx",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-关于正确处理人民内部矛盾的问题.txt",
        work="关于正确处理人民内部矛盾的问题",
        author="毛泽东",
        id_prefix="CH-LM-",
        slug="lm",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="4-哥达纲领批判.txt",
        work="哥达纲领批判",
        author="马克思",
        id_prefix="CH-GDGB-",
        slug="gdgb",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="3-国家与革命.txt",
        work="国家与革命",
        author="列宁",
        id_prefix="CH-GJGM-",
        slug="gjgm",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    # —— 依《路径.txt》补齐的「马恩奠基 / 列宁破局」核心原著（D87，从本地镜像抽取）——
    dict(
        file="0-关于费尔巴哈的提纲.txt",
        work="关于费尔巴哈的提纲",
        author="马克思",
        id_prefix="CH-MLTH-",
        slug="mlth",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="0-共产党宣言.txt",
        work="共产党宣言",
        author="马克思恩格斯",
        id_prefix="CH-XY-",
        slug="xy",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="0-德意志意识形态.txt",
        work="德意志意识形态",
        author="马克思恩格斯",
        id_prefix="CH-DYZT-",
        slug="dyzt",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="0-法兰西内战.txt",
        work="法兰西内战",
        author="马克思",
        id_prefix="CH-FLNZ-",
        slug="flnz",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="0-资本论节选.txt",
        work="资本论（第一卷节选）",
        author="马克思",
        id_prefix="CH-ZBL-",
        slug="zbl",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-怎么办.txt",
        work="怎么办？",
        author="列宁",
        id_prefix="CH-ZMB-",
        slug="zmb",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-帝国主义是资本主义的最高阶段.txt",
        work="帝国主义是资本主义的最高阶段",
        author="列宁",
        id_prefix="CH-DGZY-",
        slug="dgzy",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-共产主义运动中的左派幼稚病.txt",
        work="共产主义运动中的“左派”幼稚病",
        author="列宁",
        id_prefix="CH-YZB-",
        slug="yzb",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    # ---- D88 第二批次：学习顺序/方案/书籍 点名、镜像有可靠全文的原著 ----
    dict(
        file="0-1844年经济学哲学手稿.txt",
        work="1844年经济学哲学手稿",
        author="马克思",
        id_prefix="CH-SG-",
        slug="sg",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="0-雇佣劳动与资本.txt",
        work="雇佣劳动与资本",
        author="马克思",
        id_prefix="CH-GYLD-",
        slug="gyld",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="0-政治经济学批判序言.txt",
        work="《政治经济学批判》序言",
        author="马克思",
        id_prefix="CH-ZZJJX-",
        slug="zzjjx",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-费尔巴哈和德国古典哲学的终结.txt",
        work="路德维希·费尔巴哈和德国古典哲学的终结",
        author="恩格斯",
        id_prefix="CH-FEBH-",
        slug="febh",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-家庭私有制和国家的起源.txt",
        work="家庭、私有制和国家的起源",
        author="恩格斯",
        id_prefix="CH-JT-",
        slug="jt",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-马克思主义的三个来源和三个组成部分.txt",
        work="马克思主义的三个来源和三个组成部分",
        author="列宁",
        id_prefix="CH-SGZ-",
        slug="sgz",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="5-湖南农民运动考察报告.txt",
        work="湖南农民运动考察报告",
        author="毛泽东",
        id_prefix="CH-HN-",
        slug="hn",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="5-改造我们的学习.txt",
        work="改造我们的学习",
        author="毛泽东",
        id_prefix="CH-GZ-",
        slug="gz",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="5-整顿党的作风.txt",
        work="整顿党的作风",
        author="毛泽东",
        id_prefix="CH-ZD-",
        slug="zd",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="5-反对党八股.txt",
        work="反对党八股",
        author="毛泽东",
        id_prefix="CH-DBG-",
        slug="dbg",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="5-在延安文艺座谈会上的讲话.txt",
        work="在延安文艺座谈会上的讲话",
        author="毛泽东",
        id_prefix="CH-YA-",
        slug="ya",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    # —— D 盘中文马克思主义文库镜像补录（scripts/import_mirror.py --write，22 部）
    # 全部为镜像 HTML/PDF 文字层原文照录；抽取只做技术清洗（解码 / 去标签 / 去页眉页码
    # / 空白归一 / 全角 ASCII 归一），不改写、不补写。版本与篇目范围见 SOURCE_MANIFEST.md。
    dict(
        file="0-马克思恩格斯选集目录.txt",
        work="马克思恩格斯选集（四卷本·目录序言）", author="马克思恩格斯",
        id_prefix="CH-MES-", slug="mes",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="3-唯物主义和经验批判主义.txt",
        work="唯物主义和经验批判主义", author="列宁",
        id_prefix="CH-WP-", slug="wp",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="3-反杜林论哲学篇.txt",
        work="反杜林论（哲学篇）", author="恩格斯",
        id_prefix="CH-FDL-", slug="fdl",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="4-资本论第二卷.txt",
        work="资本论（第二卷）", author="马克思",
        id_prefix="CH-ZBL2-", slug="zbl2",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="4-资本论第三卷.txt",
        work="资本论（第三卷）", author="马克思",
        id_prefix="CH-ZBL3-", slug="zbl3",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="0-在马克思墓前的讲话.txt",
        work="在马克思墓前的讲话", author="恩格斯",
        id_prefix="CH-MQJ-", slug="mqj",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="0-工资价格和利润.txt",
        work="工资、价格和利润", author="马克思",
        id_prefix="CH-GZJG-", slug="gzjg",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="0-论权威.txt",
        work="论权威", author="恩格斯",
        id_prefix="CH-LQW-", slug="lqw",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="2-路易波拿巴的雾月十八日.txt",
        work="路易·波拿巴的雾月十八日", author="马克思",
        id_prefix="CH-WY-", slug="wy",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="2-给维伊查苏利奇的复信草稿.txt",
        work="给维·伊·查苏利奇的复信草稿", author="马克思",
        id_prefix="CH-ZSLQ-", slug="zslq",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="3-自然辩证法导言.txt",
        work="自然辩证法（导言）", author="恩格斯",
        id_prefix="CH-ZR-", slug="zr",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="2-1857-1858年经济学手稿.txt",
        work="1857-1858年经济学手稿（大纲）", author="马克思",
        id_prefix="CH-DG-", slug="dg",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="3-论一元论历史观的发展.txt",
        work="论一元论历史观的发展", author="普列汉诺夫",
        id_prefix="CH-YYL-", slug="yyl",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="3-思想起源论.txt",
        work="思想起源论", author="拉法格",
        id_prefix="CH-SXQY-", slug="sxqy",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-论列宁主义基础.txt",
        work="论列宁主义基础", author="斯大林",
        id_prefix="CH-LLN-", slug="lln",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="5-星星之火可以燎原.txt",
        work="星星之火，可以燎原", author="毛泽东",
        id_prefix="CH-XXZH-", slug="xxzh",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="5-关于领导方法的若干问题.txt",
        work="关于领导方法的若干问题", author="毛泽东",
        id_prefix="CH-LDFF-", slug="ldff",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-在白色恐怖下如何健全党的组织工作.txt",
        work="在白色恐怖下如何健全党的组织工作", author="周恩来",
        id_prefix="CH-BSKB-", slug="bskb",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-怎样做一个好的领导者.txt",
        work="怎样做一个好的领导者", author="周恩来",
        id_prefix="CH-HLDZ-", slug="hldz",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-反对官僚主义.txt",
        work="反对官僚主义", author="周恩来",
        id_prefix="CH-FGL-", slug="fgl",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="5-苏联社会主义经济问题.txt",
        work="苏联社会主义经济问题", author="斯大林",
        id_prefix="CH-SHJ-", slug="shj",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="5-读苏联政治经济学教科书的谈话.txt",
        work="读苏联《政治经济学教科书》的谈话", author="毛泽东",
        id_prefix="CH-DJKS-", slug="djks",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    # —— D100 补录（P0 设计文档点名 5 部 + P1 谱系补环 16 部）——
    # 全部由 scripts/import_mirror.py --write 从 D 盘中文马克思主义文库镜像照录，
    # 逐部来源/版本/篇目范围见 sources/texts/SOURCE_MANIFEST.md 的 D100 附录。
    dict(file="1-我的修养要则.txt", work="我的修养要则", author="周恩来",
         id_prefix="CH-XYYZ-", slug="xyyz", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-加强调查研究.txt", work="加强调查研究", author="周恩来",
         id_prefix="CH-JQDC-", slug="jqdc", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-关于党的六大的研究.txt", work="关于党的“六大”的研究", author="周恩来",
         id_prefix="CH-LD-", slug="ldyj", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-说真话鼓真劲做实事收实效.txt", work="说真话，鼓真劲，做实事，收实效", author="周恩来",
         id_prefix="CH-SZH-", slug="szh", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="5-论联合政府.txt", work="论联合政府", author="毛泽东",
         id_prefix="CH-LHZF-", slug="lhzf", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="0-黑格尔法哲学批判导言.txt", work="《黑格尔法哲学批判》导言", author="马克思",
         id_prefix="CH-HGDF-", slug="hgdf", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="0-哲学的贫困.txt", work="哲学的贫困", author="马克思",
         id_prefix="CH-ZXPK-", slug="zxpk", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="0-社会主义从空想到科学的发展.txt", work="社会主义从空想到科学的发展", author="恩格斯",
         id_prefix="CH-KXDX-", slug="kxdx", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-进一步退两步.txt", work="进一步，退两步", author="列宁",
         id_prefix="CH-JYTB-", slug="jytb", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-两种策略.txt", work="社会民主党在民主革命中的两种策略", author="列宁",
         id_prefix="CH-LZCL-", slug="lzcl", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-无产阶级革命和叛徒考茨基.txt", work="无产阶级革命和叛徒考茨基", author="列宁",
         id_prefix="CH-KCJJ-", slug="kcjj", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="5-共产党人发刊词.txt", work="《共产党人》发刊词", author="毛泽东",
         id_prefix="CH-FKC-", slug="fkc", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="5-中国革命和中国共产党.txt", work="中国革命和中国共产党", author="毛泽东",
         id_prefix="CH-ZGGM-", slug="zggm", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="5-论持久战.txt", work="论持久战", author="毛泽东",
         id_prefix="CH-LJCZ-", slug="ljcz", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="5-关于纠正党内的错误思想.txt", work="关于纠正党内的错误思想", author="毛泽东",
         id_prefix="CH-JZDN-", slug="jzdn", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="5-党委会的工作方法.txt", work="党委会的工作方法", author="毛泽东",
         id_prefix="CH-DWH-", slug="dwh", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="5-七届二中全会报告.txt",
         work="在中国共产党第七届中央委员会第二次全体会议上的报告", author="毛泽东",
         id_prefix="CH-QJEZ-", slug="qjez", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="5-论粮食税.txt", work="论粮食税", author="列宁",
         id_prefix="CH-LSS-", slug="lss", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="5-论合作社.txt", work="论合作社", author="列宁",
         id_prefix="CH-HZS-", slug="hzs", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="5-宁肯少些但要好些.txt", work="宁肯少些，但要好些", author="列宁",
         id_prefix="CH-NKSX-", slug="nksx", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="5-论列宁主义的几个问题.txt", work="论列宁主义的几个问题", author="斯大林",
         id_prefix="CH-LLNWT-", slug="llnwt", orthodoxy_tag="经典原著", authority_score=1.0),

    # ===== D103（2026-11）：按「合适章节」节选入库的 15 部 =====
    # 毛泽东 8 篇（全部《毛泽东选集》官方版，节选范围见 scripts/import_mirror.py 的 TRIM）
    dict(file="5-中国革命战争的战略问题.txt", work="中国革命战争的战略问题", author="毛泽东",
         id_prefix="CH-ZGZM-", slug="zgzm", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="5-抗日游击战争的战略问题.txt", work="抗日游击战争的战略问题", author="毛泽东",
         id_prefix="CH-KRYJ-", slug="kryj", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="5-战争和战略问题.txt", work="战争和战略问题", author="毛泽东",
         id_prefix="CH-ZZZL-", slug="zzzl", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="5-井冈山的斗争.txt", work="井冈山的斗争", author="毛泽东",
         id_prefix="CH-JGSD-", slug="jgsd", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="5-中国的红色政权为什么能够存在.txt", work="中国的红色政权为什么能够存在？",
         author="毛泽东", id_prefix="CH-HSZQ-", slug="hszq",
         orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="5-论反对日本帝国主义的策略.txt", work="论反对日本帝国主义的策略", author="毛泽东",
         id_prefix="CH-FDRB-", slug="fdrb", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="5-学习和时局.txt", work="学习和时局", author="毛泽东",
         id_prefix="CH-XXSJ-", slug="xxsj", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="5-在省市自治区党委书记会议上的讲话.txt",
         work="在省市自治区党委书记会议上的讲话", author="毛泽东",
         id_prefix="CH-SSWJ-", slug="sswj", orthodoxy_tag="经典原著", authority_score=1.0),
    # 列宁 2 篇
    dict(file="1-论国家.txt", work="论国家", author="列宁",
         id_prefix="CH-LGJ-", slug="lgj", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-评经济浪漫主义.txt", work="评经济浪漫主义", author="列宁",
         id_prefix="CH-PJJL-", slug="pjjl", orthodoxy_tag="经典原著", authority_score=1.0),
    # 斯大林 3 篇
    dict(file="1-马克思主义和语言学问题.txt", work="马克思主义和语言学问题", author="斯大林",
         id_prefix="CH-YYX-", slug="yyx", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-马克思主义和民族问题.txt", work="马克思主义和民族问题", author="斯大林",
         id_prefix="CH-MZWT-", slug="mzwt", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="2-无政府主义还是社会主义.txt", work="无政府主义还是社会主义？", author="斯大林",
         id_prefix="CH-WZF-", slug="wzf", orthodoxy_tag="经典原著", authority_score=1.0),
    # 马克思 / 恩格斯各 1 篇
    dict(file="2-1848年至1850年的法兰西阶级斗争.txt",
         work="1848年至1850年的法兰西阶级斗争", author="马克思",
         id_prefix="CH-FLGJ-", slug="flgj", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="2-德国农民战争.txt", work="德国农民战争", author="恩格斯",
         id_prefix="CH-DGNS-", slug="dgns", orthodoxy_tag="经典原著", authority_score=1.0),

    # ===== D104：P0 + P1 批次（26 部，按合适章节节选；裁剪见 scripts/import_mirror.py 的 TRIM）=====
    dict(file="5-目前形势和我们的任务.txt", work="目前形势和我们的任务", author="毛泽东",
         id_prefix="CH-MQXS-", slug="mqxs", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="3-劳动在从猿到人的转变中的作用.txt", work="劳动在从猿到人的转变中的作用",
         author="恩格斯", id_prefix="CH-LL-", slug="ll",
         orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-无产阶级专政时代的经济和政治.txt", work="无产阶级专政时代的经济和政治",
         author="列宁", id_prefix="CH-ZZJJ-", slug="zzjj",
         orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-民族和殖民地问题提纲初稿.txt", work="民族和殖民地问题提纲初稿", author="列宁",
         id_prefix="CH-MZTG-", slug="mztg", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-民族和殖民地问题委员会的报告.txt", work="民族和殖民地问题委员会的报告",
         author="列宁", id_prefix="CH-MZBG-", slug="mzbg",
         orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-论战斗唯物主义的意义.txt", work="论战斗唯物主义的意义", author="列宁",
         id_prefix="CH-ZDWM-", slug="zdwm", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="3-法德农民问题.txt", work="法德农民问题", author="恩格斯",
         id_prefix="CH-FDNM-", slug="fdnm", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="5-为人民服务.txt", work="为人民服务", author="毛泽东",
         id_prefix="CH-WRM-", slug="wrm", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="5-纪念白求恩.txt", work="纪念白求恩", author="毛泽东",
         id_prefix="CH-BQE-", slug="bqe", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="5-愚公移山.txt", work="愚公移山", author="毛泽东",
         id_prefix="CH-YGYS-", slug="ygys", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-马克思主义和修正主义.txt", work="马克思主义和修正主义", author="列宁",
         id_prefix="CH-MZXS-", slug="mzxs", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-帝国主义和社会主义运动中的分裂.txt", work="帝国主义和社会主义运动中的分裂",
         author="列宁", id_prefix="CH-DGFL-", slug="dgfl",
         orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-十月革命四周年.txt", work="十月革命四周年", author="列宁",
         id_prefix="CH-SYSN-", slug="sysn", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-论黄金在目前和社会主义完全胜利后的作用.txt",
         work="论黄金在目前和在社会主义完全胜利后的作用", author="列宁",
         id_prefix="CH-LHJ-", slug="lhj", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-大难临头出路何在.txt", work="大难临头，出路何在？", author="列宁",
         id_prefix="CH-DNLT-", slug="dnlt", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="5-关于农业合作化问题.txt", work="关于农业合作化问题", author="毛泽东",
         id_prefix="CH-NYHZ-", slug="nyhz", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="5-怎样分析农村阶级.txt", work="怎样分析农村阶级", author="毛泽东",
         id_prefix="CH-ZYFX-", slug="zyfx", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="5-集中优势兵力各个歼灭敌人.txt", work="集中优势兵力，各个歼灭敌人",
         author="毛泽东", id_prefix="CH-JZYS-", slug="jzys",
         orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="5-论政策.txt", work="论政策", author="毛泽东",
         id_prefix="CH-LZC-", slug="lzc", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="5-目前抗日统一战线中的策略问题.txt", work="目前抗日统一战线中的策略问题",
         author="毛泽东", id_prefix="CH-KRTJ-", slug="krtj",
         orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="5-将革命进行到底.txt", work="将革命进行到底", author="毛泽东",
         id_prefix="CH-JGM-", slug="jgm", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="5-在中国共产党全国宣传工作会议上的讲话.txt",
         work="在中国共产党全国宣传工作会议上的讲话", author="毛泽东",
         id_prefix="CH-XCGZ-", slug="xcgz", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="5-应当重视电影武训传的讨论.txt", work="应当重视电影《武训传》的讨论",
         author="毛泽东", id_prefix="CH-WXC-", slug="wxc",
         orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="5-大量吸收知识分子.txt", work="大量吸收知识分子", author="毛泽东",
         id_prefix="CH-ZSFZ-", slug="zsfz", orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="3-反杜林论政治经济学篇.txt", work="反杜林论（政治经济学篇·节选）",
         author="恩格斯", id_prefix="CH-FDL2-", slug="fdl2",
         orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="3-自然辩证法辩证法作为科学.txt", work="自然辩证法（辩证法作为科学·节选）",
         author="恩格斯", id_prefix="CH-ZRB2-", slug="zrb2",
         orthodoxy_tag="经典原著", authority_score=1.0),

    # ===== D105：帝国主义论三源头 + 《资本论》第四卷 + 唯物史观前史 =====
    # 马克思、恩格斯两本为经典原著；卢森堡／布哈林／希法亭三本是马列运动内部的历史文献，
    # 列宁在《帝国主义论》中对它们既有吸收也有直接批评（详见章节扩展读物 caution）。
    dict(file="4-剩余价值理论节选.txt", work="剩余价值理论（节选）", author="马克思",
         id_prefix="CH-SYZ-", slug="syz",
         orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-神圣家族节选.txt", work="神圣家族（节选）", author="马克思、恩格斯",
         id_prefix="CH-SDJZ-", slug="sdjz",
         orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-资本积累论节选.txt", work="资本积累论（节选）", author="罗莎·卢森堡",
         id_prefix="CH-ZBJL-", slug="zbjl",
         orthodoxy_tag="正统", authority_score=0.9),
    dict(file="1-世界经济与帝国主义.txt", work="世界经济与帝国主义", author="布哈林",
         id_prefix="CH-SJJJ-", slug="sjjj",
         orthodoxy_tag="正统", authority_score=0.9),
    dict(file="1-金融资本节选.txt", work="金融资本（节选）", author="鲁道夫·希法亭",
         id_prefix="CH-JRZB-", slug="jrzb",
         orthodoxy_tag="正统", authority_score=0.85),

    # ===== D116：组织领导 / 群众路线谱系补环（5 部） =====
    # 立项依据：sec_B_04（怎样做一个好的领导者）与 sec_B_05（反对本本主义）缺三块原文：
    #   群众路线奠基篇（1934）、调查研究自述篇（1941）、以及库内零本刘少奇（白区党群线）。
    # 红线核对：全部为《毛泽东选集》《刘少奇选集》官版收录篇目（可溯源、非批判对象、
    # 非黑名单组织来源）；3 篇毛文未节选（短篇，仅裁卷末注释），2 篇刘文按节保留，
    # 节选范围写在 reading_extensions_d116 的 caution 与 import_mirror 的 TRIM 里。
    dict(file="5-关心群众生活注意工作方法.txt", work="关心群众生活，注意工作方法",
         author="毛泽东", id_prefix="CH-GXXZ-", slug="gxxz",
         orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="5-农村调查的序言和跋.txt", work="《农村调查》的序言和跋",
         author="毛泽东", id_prefix="CH-NCDC-", slug="ncdc",
         orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="5-组织起来.txt", work="组织起来", author="毛泽东",
         id_prefix="CH-ZZQL-", slug="zzql",
         orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-关于白区的党和群众工作.txt", work="关于白区的党和群众工作",
         author="刘少奇", id_prefix="CH-BQDH-", slug="bqdh",
         orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-怎样进行群众工作.txt", work="怎样进行群众工作",
         author="刘少奇", id_prefix="CH-ZYQZ-", slug="zyqz",
         orthodoxy_tag="经典原著", authority_score=1.0),

    # ===== D117：工人运动谱系补环（2 部） =====
    # 立项依据：库内「工会／职工运动／罢工」一条线为 0 部（原只能靠教科书叙述和
    # 《矛盾论》注释顺带提及），sec_B_01（建党原则）只讲欧洲建党、sec_B_04（组织领导）
    # 只讲党对群众的领导，没有「党在工人中怎么建组织」的原文。
    # 红线核对：邓中夏为中共早期领导人、烈士（1933 年牺牲），该书 1930 年著于莫斯科，
    # 1949 年后人民出版社／工人出版社多次重印，属党内自述史学著作；刘少奇 1926 年报告
    # 收《刘少奇选集》上卷。均不命中 reading_extensions 的 READING_BLACKLIST。
    # 收录口径：邓中夏书只收第五、七、九章（见 import_mirror.TRIM），刘少奇文全文照录。
    dict(file="1-中国职工运动简史节选.txt", work="中国职工运动简史（1919—1926）节选",
         author="邓中夏", id_prefix="CH-ZGYD-", slug="zgyd",
         orthodoxy_tag="正统", authority_score=0.9),
    dict(file="1-工人阶级在革命中的地位与职工运动方针.txt",
         work="工人阶级在革命中的地位与职工运动方针",
         author="刘少奇", id_prefix="CH-GRJD-", slug="grjd",
         orthodoxy_tag="经典原著", authority_score=1.0),

    # ===== D118：建党前史（1918—1926）——李大钊 6 篇 + 蔡和森 2 篇 =====
    # 立项依据：D117 之后库内最早的中文文献仍是 1925 年《中国社会各阶级的分析》，
    # 1918—1924 这段「马克思主义怎样进入中国、党怎样从讨论组变成组织」完全空白，
    # 三章只能讲欧洲源头、讲不到中国这一环。
    # 红线核对：李大钊（1927 年遇难）、蔡和森（1931 年遇难）均为党史正面人物，
    # 所选篇目为马克思主义在中国传播与建党的正面文献，不命中黑名单四条。
    # 收录口径：8 篇全部全文照录（篇末原刊出处、署名、译注均保留），不设 TRIM。
    dict(file="1-法俄革命之比较观.txt", work="法俄革命之比较观", author="李大钊",
         id_prefix="CH-FLG-", slug="flg",
         orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-庶民的胜利.txt", work="庶民的胜利", author="李大钊",
         id_prefix="CH-SMD-", slug="smd",
         orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-Bolshevism的胜利.txt", work="Bolshevism的胜利", author="李大钊",
         id_prefix="CH-BLS-", slug="bls",
         orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-再论问题与主义.txt", work="再论问题与主义", author="李大钊",
         id_prefix="CH-ZLWT-", slug="zlwt",
         orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-由经济上解释中国近代思想变动的原因.txt",
         work="由经济上解释中国近代思想变动的原因", author="李大钊",
         id_prefix="CH-JJBD-", slug="jjbd",
         orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-唯物史观在现代史学上的价值.txt",
         work="唯物史观在现代史学上的价值", author="李大钊",
         id_prefix="CH-WWSG-", slug="wwsg",
         orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-马克思学说与中国无产阶级.txt", work="马克思学说与中国无产阶级",
         author="蔡和森", id_prefix="CH-CMZS-", slug="cmzs",
         orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-关于中国共产党的组织和党内生活向共产国际的报告.txt",
         work="关于中国共产党的组织和党内生活向共产国际的报告（部分）",
         author="蔡和森", id_prefix="CH-CDBG-", slug="cdbg",
         orthodoxy_tag="正统", authority_score=0.9),

    # ===== D119：建党文献原文（1920—1925）——《中共中央文件选集》第一册 10 篇 =====
    # 立项依据：D118 补的是「建党前史」的个人著述（李大钊、蔡和森），库里仍没有一份
    # 党的本体文件（纲领、决议、章程、组织问题议决案），sec_B_01（建党原则）与
    # sec_B_04（组织领导）只能讲列宁的党，讲不到中国党自己的组织构造。
    # 书源：central 档案馆编《中共中央文件选集》第一册录入文本，每篇篇末带刊印依据。
    # 红线核对：1920—1925 年党的公开文件与代表大会决议，党史正面文献，
    # 不命中 READING_BLACKLIST 四条，不作路线斗争叙事。
    # 收录口径：10 篇全部全文照录（含篇内说明、注释与卷末注文），不设 TRIM。
    dict(file="1-中国共产党第一个纲领.txt", work="中国共产党第一个纲领",
         author="中国共产党第一次全国代表大会", id_prefix="CH-DYGL-", slug="dygl",
         orthodoxy_tag="正统", authority_score=0.9),
    dict(file="1-中国共产党第一个决议.txt", work="中国共产党第一个决议",
         author="中国共产党第一次全国代表大会", id_prefix="CH-DYJY-", slug="dyjy",
         orthodoxy_tag="正统", authority_score=0.9),
    dict(file="1-中国共产党宣言.txt", work="中国共产党宣言",
         author="中国共产党上海发起组", id_prefix="CH-ZGCD-", slug="zgcd",
         orthodoxy_tag="正统", authority_score=0.9),
    dict(file="1-中国共产党章程.txt", work="中国共产党章程",
         author="中国共产党第二次全国代表大会", id_prefix="CH-DZZC-", slug="dzzc",
         orthodoxy_tag="正统", authority_score=0.9),
    dict(file="1-关于共产党的组织章程决议案.txt",
         work="关于共产党的组织章程决议案",
         author="中国共产党第二次全国代表大会", id_prefix="CH-ZZZC-", slug="zzzc",
         orthodoxy_tag="正统", authority_score=0.9),
    dict(file="1-关于民主的联合战线的议决案.txt",
         work="关于“民主的联合战线”的议决案",
         author="中国共产党第二次全国代表大会", id_prefix="CH-LHZX-", slug="lhzx",
         orthodoxy_tag="正统", authority_score=0.9),
    dict(file="1-关于妇女运动的决议.txt", work="关于妇女运动的决议",
         author="中国共产党第二次全国代表大会", id_prefix="CH-FNYD-", slug="fnyd",
         orthodoxy_tag="正统", authority_score=0.9),
    dict(file="1-中国共产党第二次全国大会宣言.txt",
         work="中国共产党第二次全国大会宣言",
         author="中国共产党第二次全国代表大会", id_prefix="CH-EDXY-", slug="edxy",
         orthodoxy_tag="正统", authority_score=0.9),
    dict(file="1-党内组织及宣传教育问题议决案.txt",
         work="党内组织及宣传教育问题议决案",
         author="中共中央执行委员会扩大会议", id_prefix="CH-DNZJ-", slug="dnzj",
         orthodoxy_tag="正统", authority_score=0.9),
    dict(file="1-对于组织问题之议决案.txt", work="对于组织问题之议决案",
         author="中国共产党第四次全国代表大会", id_prefix="CH-ZZWT-", slug="zzwt",
         orthodoxy_tag="正统", authority_score=0.9),

    # ===== D120：周恩来建国后文献（1951—1963）6 篇 =====
    # 立项依据：库里原有周恩来 7 篇（`CH-HLDZ-`/`CH-FGL-`/`CH-BSKB-`/`CH-XYYZ-`/
    # `CH-JQDC-`/`CH-LD-`/`CH-SZH-`），全部挂 sec_B_04，以 1920—40 年代组织/作风
    # 文献为主。建国后政权形态、知识分子、文艺三块的一手文献仍是空的：
    # sec_C_03（论人民民主专政）仅 2 条延伸阅读，sec_C_06（国家的起源）3 条，
    # sec_C_07（上层建筑与文艺）缺 1960 年代文艺政策讲话。
    # 书源：镜像 `zhouenlai/`（《周恩来选集》上/下卷录入文本），每篇篇末带选集
    # 编者说明（会议、日期、节录情况），可逐篇溯源；6 篇全文照录、不设 TRIM。
    dict(file="1-专政要继续民主要扩大.txt", work="专政要继续，民主要扩大",
         author="周恩来", id_prefix="CH-ZYMS-", slug="zyms",
         orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-关于知识分子问题的报告.txt", work="关于知识分子问题的报告",
         author="周恩来", id_prefix="CH-ZSFT-", slug="zsft",
         orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-论知识分子问题.txt", work="论知识分子问题",
         author="周恩来", id_prefix="CH-LZSF-", slug="lzsf",
         orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-在文艺工作座谈会和故事片创作会议上的讲话.txt",
         work="在文艺工作座谈会和故事片创作会议上的讲话",
         author="周恩来", id_prefix="CH-WYZT-", slug="wyzt",
         orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-学习毛泽东.txt", work="学习毛泽东",
         author="周恩来", id_prefix="CH-XXMZ-", slug="xxmzd",
         orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-切实执行婚姻法保护妇女合法权益.txt",
         work="切实执行婚姻法，保护妇女合法权益",
         author="周恩来", id_prefix="CH-HYF-", slug="hyf",
         orthodoxy_tag="经典原著", authority_score=1.0),

    # ===== D121：普列汉诺夫前期哲学著作 2 篇（1898 / 1895）=====
    # 收录边界（项目内固定口径）：只收 1883—1903 年马克思主义时期的理论著作。
    # 1903 年二大后转孟什维克、一战期间护国主义、1917 年反对十月革命这条线上的
    # 文字一律不入库，《在祖国的一年》永作争议版本。作者是理论来源、不是路线标杆，
    # 故写「正统／0.9」而不是「经典原著／1.0」——与列宁、毛泽东原文区分开，
    # 避免图召回把普列汉诺夫的判断排在党的经典作家之前。
    dict(file="1-个人在历史上的作用问题.txt", work="个人在历史上的作用问题",
         author="普列汉诺夫", id_prefix="CH-GRZY-", slug="grzy",
         orthodoxy_tag="正统", authority_score=0.9),
    dict(file="1-奥古斯丹·梯叶里和唯物史观.txt", work="奥古斯丹·梯叶里和唯物史观",
         author="普列汉诺夫", id_prefix="CH-TYL-", slug="tyl",
         orthodoxy_tag="正统", authority_score=0.9),

    # ===== D122：妇女运动文献 13 篇——向警予 8 篇 + 三大/四大妇女决议 2 篇
    # + 蔡特金 3 篇 =====
    # 立项依据：`sec_C_06`（《家庭、私有制和国家的起源》）此前只有 1922 年二大
    # 《关于妇女运动的决议》与 1951 年《切实执行婚姻法》两条延伸阅读，中间
    # 1923—1925 年中国党怎样把「妇女解放伴随劳动解放」落到女工罢工、女子教育、
    # 国民会议运动上，库内一个字也没有。
    # 红线核对：向警予（1928 年遇害）、蔡特金（共产国际妇女运动领导人）均为
    # 正面人物；所选篇目均为妇女解放与劳动解放主线上的文献，不命中黑名单四条。
    # 不收：柯伦泰整批（中译全为当代志愿者从俄文/英文新译，无一份可溯源到正式
    # 中文出版物；《工人反对派》《给有翼的爱若斯让路吧》属被列宁批判的路线与思潮）；
    # 蔡特金《罗莎·卢森堡对俄国革命的态度》（为卢森堡对俄国革命的批评辩护）。
    # 分档：向警予 8 篇同李大钊例，`经典原著 1.0`；三大/四大决议同 D119 例
    # `正统 0.9`；蔡特金 3 篇为外国理论来源（同 D121 普列汉诺夫例），`正统 0.9`。
    # 口径：13 篇全文照录（原刊出处行、译注、俄文版说明均保留），不设 TRIM。
    dict(file="1-女子解放与改造的商榷.txt", work="女子解放与改造的商榷", author="向警予",
         id_prefix="CH-NJSF-", slug="njsf",
         orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-留法女生对海外大学之要求.txt", work="留法女生对海外大学之要求", author="向警予",
         id_prefix="CH-LFNS-", slug="lfns",
         orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-中国知识妇女的三派.txt", work="中国知识妇女的三派", author="向警予",
         id_prefix="CH-ZSSP-", slug="zssp",
         orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-对于万国女权同盟大会的感想.txt", work="对于万国女权同盟大会的感想", author="向警予",
         id_prefix="CH-WGNQ-", slug="wgnq",
         orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-中国妇女运动杂评.txt", work="中国妇女运动杂评（从六月到八月）", author="向警予",
         id_prefix="CH-FNYP-", slug="fnyp",
         orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-今后中国妇女的国民革命运动.txt", work="今后中国妇女的国民革命运动",
         author="向警予", id_prefix="CH-FNGM-", slug="fngm",
         orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-丝厂女工团结起来.txt", work="丝厂女工团结起来", author="向警予",
         id_prefix="CH-SCTJ-", slug="sctj",
         orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-妇女运动的基础.txt", work="妇女运动的基础", author="向警予",
         id_prefix="CH-FNJC-", slug="fnjc",
         orthodoxy_tag="经典原著", authority_score=1.0),
    dict(file="1-中共三大关于妇女运动的决议案.txt",
         work="中国共产党第三次全国代表大会关于妇女运动的决议案",
         author="中国共产党第三次全国代表大会", id_prefix="CH-SDFN-", slug="sdfn",
         orthodoxy_tag="正统", authority_score=0.9),
    dict(file="1-中共四大对于妇女运动之议决案.txt",
         work="中国共产党第四次全国代表大会对于妇女运动之议决案",
         author="中国共产党第四次全国代表大会", id_prefix="CH-SIFN-", slug="sifn",
         orthodoxy_tag="正统", authority_score=0.9),
    dict(file="1-关于妇女劳动问题.txt", work="关于妇女劳动问题", author="克拉拉·蔡特金",
         id_prefix="CH-FNLD-", slug="fnld",
         orthodoxy_tag="正统", authority_score=0.9),
    dict(file="1-无产阶级妇女们准备起来.txt", work="无产阶级妇女们，准备起来！",
         author="克拉拉·蔡特金", id_prefix="CH-ZBQL-", slug="zbql",
         orthodoxy_tag="正统", authority_score=0.9),
    dict(file="1-列宁给全世界妇女的遗教.txt", work="列宁给全世界妇女的遗教",
         author="克拉拉·蔡特金", id_prefix="CH-LNYJ-", slug="lnyj",
         orthodoxy_tag="正统", authority_score=0.9),
    # ===== D123 恽代英文献 22 部（1925—1930）=====
    # 分档依据：理论著作与讲演 12 部按「党的早期经典作家原文」记 1.0（同 D118 李大钊 6 篇、
    # D122 向警予 8 篇例）；工人运动与苏维埃史料 10 部记 0.9（含政策主张与地方政权经验，
    # 同 D117 邓中夏《中国职工运动简史》、D119 建党文献例）。
    dict(
        file="1-中国民族革命运动史节选.txt",
        work="中国民族革命运动史（节选）",
        author="恽代英",
        id_prefix="CH-MZGM-",
        slug="mzgm",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-世界革命与中国革命.txt",
        work="世界革命与中国革命（讲演大纲）",
        author="恽代英",
        id_prefix="CH-SJGM-",
        slug="sjgm",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-革命之障碍.txt",
        work="革命之障碍",
        author="恽代英",
        id_prefix="CH-GMZA-",
        slug="gmza",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-国民革命与阶级斗争.txt",
        work="国民革命与阶级斗争",
        author="恽代英",
        id_prefix="CH-GMJJ-",
        slug="gmjj",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-与李琯卿君论新国家主义.txt",
        work="与李琯卿君论新国家主义",
        author="恽代英",
        id_prefix="CH-LGQJ-",
        slug="lgqj",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-答醒狮周报三十二期的质难节选.txt",
        work="答《醒狮周报》三十二期的质难（节选）",
        author="恽代英",
        id_prefix="CH-XSZB-",
        slug="xszb",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-读孙文主义之哲学的基础.txt",
        work="读《孙文主义之哲学的基础》",
        author="恽代英",
        id_prefix="CH-SWZY-",
        slug="swzy",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-民族革命中的共产党.txt",
        work="民族革命中的共产党",
        author="恽代英",
        id_prefix="CH-MZGC-",
        slug="mzgc",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-为什么产业无产阶级最富于革命性.txt",
        work="为什么产业无产阶级最富于革命性？",
        author="恽代英",
        id_prefix="CH-CYGM-",
        slug="cygm",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-怎样做一个共产党员.txt",
        work="怎样做一个共产党员？",
        author="恽代英",
        id_prefix="CH-ZYCD-",
        slug="zycd",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-什么是机会主义.txt",
        work="什么是机会主义？",
        author="恽代英",
        id_prefix="CH-JHZY-",
        slug="jhzy",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-我们的战略.txt",
        work="我们的战略",
        author="恽代英",
        id_prefix="CH-WMDZ-",
        slug="wmdz",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    # 以下 10 部记 0.9：史料与经验总结性质，写法上直陈政策主张（如《中东路问题与一般流行的错误意见》记当时党中央对中东路事件的口径），引用时须结合成文年代。
    dict(
        file="1-中国劳动阶级斗争第一幕.txt",
        work="中国劳动阶级斗争第一幕",
        author="恽代英",
        id_prefix="CH-LDJJ-",
        slug="ldjj",
        orthodoxy_tag="正统",
        authority_score=0.9,
    ),
    dict(
        file="1-上海日纱厂罢工中所得的教训.txt",
        work="上海日纱厂罢工中所得的教训",
        author="恽代英",
        id_prefix="CH-RSCB-",
        slug="rscb",
        orthodoxy_tag="正统",
        authority_score=0.9,
    ),
    dict(
        file="1-五卅运动与阶级争斗.txt",
        work="五卅运动与阶级争斗",
        author="恽代英",
        id_prefix="CH-WSJJ-",
        slug="wsjj",
        orthodoxy_tag="正统",
        authority_score=0.9,
    ),
    dict(
        file="1-农民中的宣传组织工作.txt",
        work="农民中的宣传组织工作",
        author="恽代英",
        id_prefix="CH-NMXC-",
        slug="nmxc",
        orthodoxy_tag="正统",
        authority_score=0.9,
    ),
    dict(
        file="1-苏维埃的建立.txt",
        work="苏维埃的建立",
        author="恽代英、李立三",
        id_prefix="CH-SWEA-",
        slug="swea",
        orthodoxy_tag="正统",
        authority_score=0.9,
    ),
    dict(
        file="1-广州暴动与工会.txt",
        work="广州暴动与工会",
        author="恽代英",
        id_prefix="CH-GZBQ-",
        slug="gzbq",
        orthodoxy_tag="正统",
        authority_score=0.9,
    ),
    dict(
        file="1-闽西苏维埃的过去与将来.txt",
        work="闽西苏维埃的过去与将来",
        author="恽代英",
        id_prefix="CH-MXSW-",
        slug="mxsw",
        orthodoxy_tag="正统",
        authority_score=0.9,
    ),
    dict(
        file="1-请看闽西农民造反的成绩.txt",
        work="请看闽西农民造反的成绩——福建通信",
        author="恽代英",
        id_prefix="CH-KMXN-",
        slug="kmxn",
        orthodoxy_tag="正统",
        authority_score=0.9,
    ),
    dict(
        file="1-中东路问题与一般流行的错误意见.txt",
        work="中东路问题与一般流行的错误意见",
        author="恽代英",
        id_prefix="CH-ZDLW-",
        slug="zdlw",
        orthodoxy_tag="正统",
        authority_score=0.9,
    ),
    dict(
        file="1-在狱中给党组织的信.txt",
        work="在狱中给党组织的信（附《狱中诗》）",
        author="恽代英",
        id_prefix="CH-YZDX-",
        slug="yzdx",
        orthodoxy_tag="正统",
        authority_score=0.9,
    ),
    # ===== D124 克鲁普斯卡娅「列宁怎样读书、研究、宣传」10 篇 =====
    # 书源：人民出版社 1973 年版《列宁是怎样写作学习的》（`on-lenin-2/`，整本
    # 11 篇按篇节选 7 篇）＋《论列宁》1979 年俄文第 4 版单篇（`on-lenin/`，
    # 中译见《马列著作编译资料》第 15／16 辑，收 3 篇）。
    # 分档：「正统 0.9」—— 回忆性文献而非列宁本人著作，与 D122 蔡特金／D123
    # 工运史料同例；不占经典原著档。
    dict(
        file="1-列宁是宣传家和鼓动家.txt",
        work="列宁是宣传家和鼓动家",
        author="娜·康·克鲁普斯卡娅",
        id_prefix="CH-KPLJ-",
        slug="kplj",
        orthodoxy_tag="正统",
        authority_score=0.9,
    ),
    dict(
        file="1-列宁论善于为工农群众写作.txt",
        work="列宁论善于为工农群众写作",
        author="娜·康·克鲁普斯卡娅",
        id_prefix="CH-KPGZ-",
        slug="kpgz",
        orthodoxy_tag="正统",
        authority_score=0.9,
    ),
    dict(
        file="1-列宁怎样研究马克思的著作.txt",
        work="列宁怎样研究马克思的著作",
        author="娜·康·克鲁普斯卡娅",
        id_prefix="CH-KPYJ-",
        slug="kpyj",
        orthodoxy_tag="正统",
        authority_score=0.9,
    ),
    dict(
        file="1-创造性的研究过程.txt",
        work="创造性的研究过程",
        author="娜·康·克鲁普斯卡娅",
        id_prefix="CH-CZXJ-",
        slug="czxj",
        orthodoxy_tag="正统",
        authority_score=0.9,
    ),
    dict(
        file="1-理论联系实际的学风.txt",
        work="理论联系实际的学风",
        author="娜·康·克鲁普斯卡娅",
        id_prefix="CH-LLLX-",
        slug="lllx",
        orthodoxy_tag="正统",
        authority_score=0.9,
    ),
    dict(
        file="1-列宁怎样利用图书馆.txt",
        work="列宁怎样利用图书馆",
        author="娜·康·克鲁普斯卡娅",
        id_prefix="CH-KPTU-",
        slug="kptu",
        orthodoxy_tag="正统",
        authority_score=0.9,
    ),
    dict(
        file="1-列宁怎样学习外国语.txt",
        work="列宁怎样学习外国语",
        author="娜·康·克鲁普斯卡娅",
        id_prefix="CH-KPWY-",
        slug="kpwy",
        orthodoxy_tag="正统",
        authority_score=0.9,
    ),
    dict(
        file="1-研究马克思主义.txt",
        work="研究马克思主义",
        author="娜·康·克鲁普斯卡娅",
        id_prefix="CH-YJMY-",
        slug="yjmy",
        orthodoxy_tag="正统",
        authority_score=0.9,
    ),
    dict(
        file="1-列宁是科学工作者.txt",
        work="列宁是科学工作者",
        author="娜·康·克鲁普斯卡娅",
        id_prefix="CH-KPKX-",
        slug="kpkx",
        orthodoxy_tag="正统",
        authority_score=0.9,
    ),
    dict(
        file="1-列宁如何对待博物馆工作.txt",
        work="列宁如何对待博物馆工作",
        author="娜·康·克鲁普斯卡娅",
        id_prefix="CH-KPBW-",
        slug="kpbw",
        orthodoxy_tag="正统",
        authority_score=0.9,
    ),
    # ===== D125 按章节缺口补 13 篇 =====
    # 9 个章节补内容缺口（夺权策略／人的解放／巴黎公社／世界观概述／农村调查／
    # 民族革命观／国家结构／统一战线／无产阶级力量），不是按作者全集补全。
    # 分档：列宁／马克思／毛泽东／周恩来／李大钊为「经典原著 1.0」（与本人既有
    # 条目同档）；邓中夏与既有的《中国职工运动简史（节选）》同档「正统 0.9」。
    dict(
        file="1-论策略书.txt",
        work="论策略书",
        author="列宁",
        id_prefix="CH-CELS-",
        slug="cls",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-马克思主义和起义.txt",
        work="马克思主义和起义",
        author="列宁",
        id_prefix="CH-MYSQ-",
        slug="mysq",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-布尔什维克能保持国家政权吗.txt",
        work="布尔什维克能保持国家政权吗？",
        author="列宁",
        id_prefix="CH-BESW-",
        slug="besw",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-论犹太人问题.txt",
        work="论犹太人问题",
        author="马克思",
        id_prefix="CH-LYTR-",
        slug="lytr",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-一八七一年的巴黎康妙恩.txt",
        work="一八七一年的巴黎“康妙恩”",
        author="李大钊",
        id_prefix="CH-KMEN-",
        slug="kme",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-卡尔马克思传略和马克思主义概述节选.txt",
        work="卡尔·马克思（传略和马克思主义概述·节选）",
        author="列宁",
        id_prefix="CH-KEMK-",
        slug="kem",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-土地与农民.txt",
        work="土地与农民",
        author="李大钊",
        id_prefix="CH-TDYM-",
        slug="tdym",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-鲁豫陕等省的红枪会.txt",
        work="鲁豫陕等省的红枪会",
        author="李大钊",
        id_prefix="CH-HQHH-",
        slug="hqh",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-马克思的中国民族革命观.txt",
        work="马克思的中国民族革命观",
        author="李大钊",
        id_prefix="CH-ZGMG-",
        slug="zgmg",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-论统一战线.txt",
        work="论统一战线",
        author="周恩来",
        id_prefix="CH-LTYX-",
        slug="ltyx",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-关于中华人民共和国宪法草案.txt",
        work="关于中华人民共和国宪法草案",
        author="毛泽东",
        id_prefix="CH-XFCA-",
        slug="xfca",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-关于我国民族政策的几个问题.txt",
        work="关于我国民族政策的几个问题",
        author="周恩来",
        id_prefix="CH-MZZC-",
        slug="mzzc",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-我们的力量.txt",
        work="我们的力量",
        author="邓中夏",
        id_prefix="CH-WMDL-",
        slug="wmdl",
        orthodoxy_tag="正统",
        authority_score=0.9,
    ),
    # ===== D126 周恩来民主革命期 12 篇（1926—1949）=====
    # 选篇依依据：六章的**内容缺口**，不是年份铺开。全部为《周恩来选集》上卷
    # 文本、正面谱系；分档与库内既有周恩来 15 篇同档（经典原著 1.0）。
    dict(
        file="1-中共中央给红军第四军前委的指示信.txt",
        work="中共中央给红军第四军前委的指示信",
        author="周恩来",
        id_prefix="CH-HJZS-",
        slug="hjzs",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-坚决肃清党内一切非无产阶级的意识.txt",
        work="坚决肃清党内一切非无产阶级的意识",
        author="周恩来",
        id_prefix="CH-SQYS-",
        slug="sqys",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-现时政治斗争中之我们.txt",
        work="现时政治斗争中之我们",
        author="周恩来",
        id_prefix="CH-XSZZ-",
        slug="xszz",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-关于一九二四至二六年党对国民党的关系.txt",
        work="关于一九二四至二六年党对国民党的关系",
        author="周恩来",
        id_prefix="CH-GMDX-",
        slug="gmdx",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-一年来的谈判及前途.txt",
        work="一年来的谈判及前途",
        author="周恩来",
        id_prefix="CH-YNTP-",
        slug="yntp",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-论中国的法西斯主义新专制主义.txt",
        work="论中国的法西斯主义——新专制主义",
        author="周恩来",
        id_prefix="CH-FXSZ-",
        slug="fxsz",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-全国大反攻打倒蒋介石.txt",
        work="全国大反攻，打倒蒋介石",
        author="周恩来",
        id_prefix="CH-QGFG-",
        slug="qgfg",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-关于和平谈判问题的报告.txt",
        work="关于和平谈判问题的报告",
        author="周恩来",
        id_prefix="CH-HPTB-",
        slug="hptb",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-老区半老区的土地改革与整党工作.txt",
        work="老区半老区的土地改革与整党工作",
        author="周恩来",
        id_prefix="CH-LQTG-",
        slug="lqtg",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-人民政协共同纲领草案的特点.txt",
        work="人民政协共同纲领草案的特点",
        author="周恩来",
        id_prefix="CH-ZXGT-",
        slug="zxgt",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-恢复生产建设中国.txt",
        work="恢复生产，建设中国",
        author="周恩来",
        id_prefix="CH-HFSC-",
        slug="hfsc",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    dict(
        file="1-新民主主义的经济建设.txt",
        work="新民主主义的经济建设",
        author="周恩来",
        id_prefix="CH-XMJJ-",
        slug="xmjj",
        orthodoxy_tag="经典原著",
        authority_score=1.0,
    ),
    # ===== D127 考茨基 4 篇（1887 / 1892 / 1898 / 1908）=====
    # 分档：全部「正统 / 0.9」，**不给 1.0**。考茨基是第二国际的理论家，
    # 不是马列毛经典作家：他的国家与革命学说后来被列宁《国家与革命》
    # 《无产阶级革命和叛徒考茨基》正面批判，库内只作历史文献与思想史材料。
    # 对照：同一作者谱系里，普列汉诺夫前期哲学著作（D121）同样记「正统 / 0.9」。
    dict(
        file="1-马克思的经济学说.txt",
        work="马克思的经济学说",
        author="考茨基",
        id_prefix="CH-KCJX-",
        slug="kcjx",
        orthodoxy_tag="正统",
        authority_score=0.9,
    ),
    dict(
        # 长篇节选：出版者说明＋著者第一版序＋「历史部分」三章。
        file="1-爱尔福特纲领解说节选.txt",
        work="爱尔福特纲领解说（节选）",
        author="考茨基",
        id_prefix="CH-AEFT-",
        slug="aeft",
        orthodoxy_tag="正统",
        authority_score=0.9,
    ),
    dict(
        # 长篇节选：著者序＋上卷前四章（资本主义农业的发展）。
        file="1-土地问题节选.txt",
        work="土地问题（节选）",
        author="考茨基",
        id_prefix="CH-TDWT-",
        slug="tdwt",
        orthodoxy_tag="正统",
        authority_score=0.9,
    ),
    dict(
        # 长篇节选：引论＋第二篇「罗马帝国时代的社会」。
        file="1-基督教之基础节选.txt",
        work="基督教之基础（节选）",
        author="考茨基",
        id_prefix="CH-JDJC-",
        slug="jdjc",
        orthodoxy_tag="正统",
        authority_score=0.9,
    ),
]

# 通用哲学概念词（用于图召回 mention；与 CONCEPT_KEYWORDS 合并）
_GENERIC_TERMS = [
    "哲学", "唯物论", "唯心论", "二元论", "辩证法", "唯物辩证法", "认识论", "实践",
    "矛盾", "对立统一", "否定之否定", "质量互变", "量变质变", "规律", "范畴",
    "物质", "意识", "感性认识", "理性认识", "真理", "绝对真理", "相对真理",
    "现象", "本质", "形式", "内容", "原因", "结果", "必然", "偶然", "自由", "必然性",
    "历史唯物主义", "唯物史观", "社会存在", "社会意识", "生产力", "生产关系", "阶级", "国家",
    "革命", "专政", "无产阶级", "资产阶级", "群众", "人民群众", "意识形态",
    # D117：群众路线／组织领导／工人运动词族。标准名与 core/rag/concept_dict.py
    # 新增条目完全一致，图召回才能从「提问概念」连到「分片 mention」。
    "工会", "职工运动", "罢工", "工人俱乐部", "群众路线", "群众组织",
    "工农联盟", "民主集中制", "党内斗争", "先锋队", "统一战线", "整风",
    "批评与自我批评", "调查研究", "妇女解放", "合作社", "白区工作",
    "领导方法", "阶级分析", "组织起来",
    # D119：建党文献（纲领／章程／组织决议）词族。同样要求标准名 = 分片 mention
    # 原文用词；「妇女运动」是 CONCEPT_MAP 里「妇女解放」的既有变体，1922 年
    # 《关于妇女运动的决议》全篇用的是这个词。
    "党纲", "章程", "党的组织", "妇女运动",
    # D120：周恩来建国后文献词族（知识分子／政权形态／文艺／思想改造）。同样要求
    # 标准名 = 分片 mention 的原文用词：「知识分子」294 次、「人民民主专政」11 次、
    # 「文艺」50 次、「自我改造」13 次，均为正文原词而非改写。
    "知识分子", "人民民主专政", "文艺", "自我改造",
    # D121：普列汉诺夫前期两篇的唯物史观术语。「个人在历史上的作用」正文出现 8 次，
    # 「杰出人物」3 次，都是原词；「必然」「偶然」「自由」「必然性」已在上方哲学词族里。
    "个人在历史上的作用", "杰出人物",
    # D122：妇女运动文献词族。标准名 = 分片 mention 原文用词：「劳动妇女」在
    # 向警予、蔡特金两批正文里共 42 次，「女工」65 次、「女权运动」11 次；
    # 「妇女解放」「妇女运动」已有。「劳动妇女」同时在 core/rag/concept_dict.py
    # 登记为标准概念，两端用词一致。
    "劳动妇女", "女工", "女权运动",

    # D123：恽代英文献词族（图召回 mention 用）。
    # 均为本批正文原文用词：帝国主义 188 次、苏维埃 112 次、军阀 64 次、工农 48 次、
    # 反革命 37 次、国家主义 35 次、革命势力 29 次、买办阶级 20 次、土豪劣绅 11 次、
    # 革命党 65 次、国民革命 68 次、五卅 55 次。
    # 前四个同时在 core/rag/concept_dict.py 登记为标准概念（两端用词一致，同 D122「劳动妇女」例），
    # 仍需在此列出，否则 mention 不会生成。
    "帝国主义", "苏维埃", "国民革命", "五卅运动",
    "军阀", "工农", "革命党", "国家主义", "反革命", "革命势力",
    "买办阶级", "土豪劣绅",
    # ===== D124：克鲁普斯卡娅「读书／研究／宣传」窄口 =====
    # 原文用词：宣传（10 篇共 60 余次）、鼓动（40 余次）、学风、图书馆。
    # 「宣传」「鼓动」是本批主题词，在此之前 _GENERIC_TERMS 里没有，
    # 不加则图召回对这些提问零命中。
    "宣传", "鼓动", "学风", "图书馆",
    # ===== D125：夺权／国家结构／人的解放／农民调查词族 =====
    # 原文用词与出现分片数：起义 213、宪法 152、异化 126、巴黎公社 76、
    # 土地革命 60、领导权 56、农民运动 39。前六个是列宁夺权三篇、毛泽东宪法
    # 草案讲话、《论犹太人问题》、李大钊巴黎公社一文带来的新词族，不加则
    # 检索「起义」「宪法」「异化」零命中。
    "起义", "宪法", "异化", "巴黎公社", "土地革命", "领导权", "农民运动",
    # ===== D126：新民主主义纲领／土地改革／统治性质词族 =====
    # 原文用词与全库出现次数：新民主主义 244、土地改革 76、法西斯主义 67、
    # 共同纲领 23、整党 15、民族资本家 8。前两个是「新民主主义论」与「调查研究」
    # 两章的主题词，此前不在词表里，不加则检索「新民主主义」「土地改革」零命中；
    # 「法西斯主义」是 D126 阶级性质判定那一篇的核心术语；「整党」「共同纲领」
    # 「民族资本家」均出现在所补正文原句里，不是改写。
    "新民主主义", "共同纲领", "土地改革", "整党", "法西斯主义", "民族资本家",
]


@lru_cache(maxsize=1)
def _terms() -> tuple[str, ...]:
    terms = set(_GENERIC_TERMS)
    try:
        from content.concept_keywords import CONCEPT_KEYWORDS

        for v in CONCEPT_KEYWORDS.values():
            for t in v.get("terms", []):
                if t and len(t) >= 2:
                    terms.add(t)
    except Exception:  # pragma: no cover - 词表缺失时退化为通用词
        pass
    # 概念词典的标准术语必须进这张词表：既有约定是「词典里的标准词就是分片里的
    # 原文用词」，但两套词表此前各写各的——「经济基础／上层建筑／认识／阶级斗争／
    # 商品／自然辩证法／反映论／商品拜物教／无产阶级专政／辩证唯物主义」这 10 个
    # 核心术语在 2 万多片里一次都没被标出过，概念召回对它们等于不存在。
    try:
        from core.rag.concept_dict import CONCEPT_MAP

        for k in CONCEPT_MAP:
            if k and len(k) >= 2:
                terms.add(k)
    except Exception:  # pragma: no cover - 词典缺失时退化
        pass
    # 长词优先匹配
    return tuple(sorted(terms, key=len, reverse=True))


def _concept_mentions(text: str, cap: int = 6) -> list[str]:
    hits: list[str] = []
    for term in _terms():
        if term in text and term not in hits:
            hits.append(term)
        if len(hits) >= cap:
            break
    return hits


def _clean_para(text: str) -> str:
    text = text.replace("\xa0", " ")
    text = re.sub(r"[ \t]+", " ", text)
    return text.strip()


def _looks_like_prose(text: str) -> bool:
    """粗筛：剔除 OCR 噪声（拉丁乱码行、页码索引碎片等）。

    要求足够多的 CJK 字符且中文占比不低，避免把出版社名/西文乱码
    当成原著正文入库（正统性：宁可漏，不可错）。
    """
    if len(text) < 12:
        return False
    cjk = sum(1 for ch in text if "\u4e00" <= ch <= "\u9fff")
    if cjk < 10:
        return False
    return cjk / len(text) >= 0.45


# 分片最短长度：不足这个数就把下一段并进来。
# 为什么要有下限——问答体、目录体、一行一段的书会被切成「平均 28 字」的碎片
# （实测「苏联社会主义经济问题」1520 片、「选集目录序言」1029 片，全库 <40 字
# 的分片占 20%）。这种分片既无法单独阅读，也无法作为检索单位：它没有任何
# 自足语义，只会靠「短 + 词频」刷分。合并到 60 字后全库 <40 字分片降到 0.3%，
# 分片总数减少约两成，检索指标不降（同一套 30 条基准 top1/top3 不变）。
MIN_CHUNK_CHARS = 60


def _build_book_chunks(meta: dict, paragraphs: list[dict]) -> list[dict]:
    chunks: list[dict] = []
    seq = 0
    buf: list[str] = []
    buf_chapter = ""

    def flush() -> None:
        nonlocal buf, seq
        if not buf:
            return
        text = "\n".join(buf)
        buf = []
        seq += 1
        loc = (buf_chapter + " " if buf_chapter else "") + f"第{seq}段"
        chunks.append(
            dict(
                id=f"{meta['id_prefix']}{seq:03d}",
                layer=1,
                source=meta["work"],
                source_location=loc,
                paragraph_id=f"{meta['slug']}-p{seq}",
                text=text,
                orthodoxy_tag=meta["orthodoxy_tag"],
                authority_score=meta["authority_score"],
                logical_type="primary_text",
                concept_mentions=_concept_mentions(text),
                book_author=meta["author"],
                is_primary_text=True,
            )
        )

    for p in paragraphs:
        text = _clean_para(p.get("text", ""))
        if len(text) < 15 or not _looks_like_prose(text):
            continue
        chapter = (p.get("chapter_hint") or "").strip()
        if buf and chapter != buf_chapter:  # 不跨章合并，否则出处定位会串
            flush()
        buf_chapter = chapter
        buf.append(text)
        if sum(len(t) for t in buf) >= MIN_CHUNK_CHARS:
            flush()
    flush()
    return chunks


# 只作导览、不进检索索引的条目（出版社编的选集目录/出版说明，非原著正文）。
GUIDE_ONLY_WORKS: frozenset[str] = frozenset({"马克思恩格斯选集（四卷本·目录序言）"})


@lru_cache(maxsize=1)
def all_book_chunks() -> tuple[dict, ...]:
    """扫描 sources/texts/ 下已登记的原文文件，生成真实正文分片。"""
    from content.text_loader import TextLoader

    loader = TextLoader()
    available = set(loader.list_files())
    out: list[dict] = []
    for meta in BOOKS:
        if meta["file"] not in available:
            continue
        try:
            paras = loader.read_paragraphs(meta["file"])
            book = _build_book_chunks(meta, paras)
            out.extend(book)
            logger.info("原著分片：%s -> %d 段", meta["work"], len(book))
        except Exception as exc:  # pragma: no cover
            logger.warning("原著分片失败 %s: %s", meta["file"], exc)
    return tuple(out)


def retrievable_chunks() -> tuple[dict, ...]:
    """喂给检索索引的分片（= 全部原著分片减去「只作导览」的条目）。

    为什么单列一个入口：`all_book_chunks()` 同时服务「书目 / 分片浏览」与「检索索引」，
    两者要的集合不一样。《马克思恩格斯选集（四卷本·目录序言）》是出版社编的选集
    目录与出版说明，不是原著正文，却被切成 1029 个平均 28 字的分片——这些碎片
    在自然语言提问里反复抢占前排（实测「中国有多少产业工人」「什么是剩余价值」
    等提问的前五条里都有它），而读者在书目录里仍应看得见它。所以只在检索入口
    剔除，不动 `BOOKS` 与分片总量。
    """
    return tuple(c for c in all_book_chunks() if c["source"] not in GUIDE_ONLY_WORKS)


def available_works() -> list[str]:
    """已成功生成分片的原著著作名。"""
    seen: list[str] = []
    for c in all_book_chunks():
        if c["source"] not in seen:
            seen.append(c["source"])
    return seen


def stats() -> dict:
    bt = all_book_chunks()
    return {
        "books": available_works(),
        "chunk_count": len(bt),
        "by_book": {w: sum(1 for c in bt if c["source"] == w) for w in available_works()},
    }
