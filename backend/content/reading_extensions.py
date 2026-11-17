"""扩展读物 — 路线 C“建设社会主义国家”的延伸阅读（P0 内容补齐）

来源与定位说明（务必遵守的分档红���）：
  《扩展读物.md》混装了四段来源：前三段是「原教旨马列毛（MLM）」书单，
  第四段是合规化改写。经甄别，按其与马克思列宁主义、毛泽东思想的符合程度，
  分为四档，并在 UI 上用不同颜色徽章标注：

    classic    经典原文/权威文献 —— 符合马列毛，可正面学习。
    historical 历史文献/实践经验 —— 只作背景与史料参考，不作当代正面教材。
    private    「私人版本」/民间理论 —— 民间左翼学者或非官方出版物中，立场基本
               符合马列毛、属于建设性反思或学理探讨者（本文档默认只收这一小类，
               且明示「个人观点·非官方版本·须对照经典与《历史决议》阅读」）。
    contested  争议版本（原教旨/宗派化 MLM）—— 只能作为「批判对象·非借鉴」呈现，
               不得作正面教材、不得生成鼓励性题目。

  另有 BLACKLIST（禁止入库）：凡鼓吹推翻社会主义制度、否定党的领导、把改革
  开放定性为「全面复辟」、或境外反华「原教旨」出版物，一律不得接入本系统。

红线复述（不可违反）：
  1) 不伪造原著正文：未入真实 TextChunk 前标「导读/延伸」，source_note 声明；
  2) 延伸阅读不参与主线门控、不计正式掌握度；
  3) contested 条目仅作靶子，包裹在【批判对象·非借鉴】语义中呈现。
"""
from __future__ import annotations

from content.reading_extensions_d98 import D98_EXTENSIONS

# 分档常量
KIND_CLASSIC = "classic"
KIND_HISTORICAL = "historical"
KIND_PRIVATE = "private"
KIND_CONTESTED = "contested"

KIND_LABEL: dict[str, str] = {
    KIND_CLASSIC: "经典原文 / 权威文献",
    KIND_HISTORICAL: "历史文献 / 实践经验",
    KIND_PRIVATE: "私人版本 · 民间理论（非官方）",
    KIND_CONTESTED: "争议版本 · 仅供批判",
}


# ---------------------------------------------------------------------------
# 一、路线 C 各章「延伸阅读」
#    section_id -> [条目]
# 条目字段：
#   title       书名/篇名
#   author      作者/出处
#   kind        分档（见上）
#   intro       一句话定位（正面条目为学习要点；contested 为「要批判什么」）
#   points      要点（列表，UI 用列表渲染）
#   how_to_use  怎么用（学习建议）
#   caution     注意（可选，尤其 private/contested 必填）
#   link        可选外部链接（仅限可公开访问的权威/合规站点）
# ---------------------------------------------------------------------------

READING_EXTENSIONS: dict[str, list[dict]] = {
    "sec_C_00": [
        {
            "title": "《反对本本主义》",
            "author": "毛泽东（1930）",
            "kind": "classic",
            "intro": "『没有调查，没有发言权』——把实践标准落到调查研究的作风上。",
            "points": [
                "中国革命斗争的胜利要靠中国同志了解中国情况。",
                "反对脱离实际的『本本主义』，强调调查研究是一切工作的第一步。"
            ],
            "how_to_use": "配合‘从现实社会关系出发’一节，体会实事求是的思想路线。",
            "link": "https://www.marxists.org/chinese/maozedong/marxist.org-chinese-mao-193005.htm",
            "local_work": "反对本本主义"
        }
    ],
    "sec_C_01": [
        {
            "title": "《国家与革命》第五章（国家消亡的经济基础）",
            "author": "列宁（1917）",
            "kind": "classic",
            "intro": "列宁对《哥达纲领批判》的展开：社会主义阶段国家与法权的存废问题。",
            "points": [
                "在共产主义第一阶段，国家正在消亡但还不能完全消亡，因为还需要保卫按劳分配的‘资产阶级法权’。",
                "只有到共产主义高级阶段，国家才完全消亡。"
            ],
            "how_to_use": "与本章‘共产主义社会的两个阶段’对照，理解国家消亡的条件。",
            "link": "https://www.marxists.org/chinese/lenin/191708-09/05.htm",
            "local_work": "国家与革命"
        },
        {
            "title": "《读苏联〈政治经济学教科书〉的谈话》（节选·关于社会主义商品生产与价值规律部分）",
            "author": "毛泽东（1959—1960）",
            # D100 版本治理：此处入库的是 1968 年《毛泽东思想万岁》所收「阅读笔记（社会主义部分、
            # 第三版）」，不是官方《毛泽东文集》第八卷「谈话」整理稿 → 降为“历史文本·须对照批判”，
            # 避免把非官方版本当作可正面引用的经典原文。见 .local/route_books_audit.md §3.4。
            "kind": "historical",
            "intro": "毛泽东对社会主义政治经济学的独立思考；只取其中关于商品生产、价值规律、按劳分配的论述。",
            "points": [
                "社会主义社会商品生产还要发展，价值规律‘是一个伟大的学校’，但必须在计划指导下发挥作用。",
                "‘政治工作是一切经济工作的生命线’——经济建设不能‘见物不见人’。"
            ],
            "how_to_use": "只读『商品生产』『价值规律』相关部分；官方《毛泽东文集》第八卷有收录。"
                           "本篇为 1968 年汉版《毛泽东思想万岁》所收阅读笔记（篇名/版本与通行整理稿不同），"
                           "可点“阅读原文”核对；不建议采用网络上拼接的‘完整版’，以免混入非原文内容。",
            "caution": "该谈话流传版本繁杂，务必以权威出版版本核对；本篇所收版本见‘阅读原文’，引用须注明版本。"
        }
    ],
    "sec_C_02": [
        {
            "title": "《论人民民主专政》",
            "author": "毛泽东（1949）",
            "kind": "classic",
            "intro": "新民主主义革命胜利后建设什么国家：人民民主专政，为向社会主义过渡准备政治前提。",
            "points": [
                "工人阶级（经过共产党）领导、以工农联盟为基础的人民民主专政。",
                "对人民实行民主，对反动派实行专政，二者结合。"
            ],
            "how_to_use": "与《新民主主义论》衔接读，理解从新民主主义到社会主义的过渡逻辑。",
            "link": "https://www.marxists.org/chinese/maozedong/marxist.org-chinese-mao-19490630.htm",
            "local_work": "论人民民主专政"
        }
    ],
    "sec_C_03": [
        {
            "title": "《新民主主义论》",
            "author": "毛泽东（1940）",
            "kind": "classic",
            "intro": "人民民主专政的前史：新民主主义共和国的国体与政体构想。",
            "points": [
                "新民主主义革命的性质、对象、动力与前途。",
                "国体——各革命阶级联合专政；政体——民主集中制。"
            ],
            "how_to_use": "与《论人民民主专政》衔接读，理解从新民主主义到社会主义的过渡逻辑。",
            "link": "https://www.marxists.org/chinese/maozedong/marxist.org-chinese-mao-194001.htm",
            "local_work": "新民主主义论"
        }
    ],
    "sec_C_04": [
        {
            "title": "『鞍钢宪法』（两参一改三结合）作为历史经验",
            "author": "1960年鞍山钢铁公司经验总结",
            "kind": "historical",
            "intro": "‘干部参加劳动、工人参加管理，改革不合理规章制度，工人、干部、技术人员三结合’的工业管理经验。",
            "points": [
                "强调劳动者参与管理，是对苏联‘一长制’的反思与调整。",
                "作为社会主义企业民主管理的历史探索，有借鉴意义，也需结合当代企业治理辩证看待。"
            ],
            "how_to_use": "作为‘实践经验’阅读，与本章‘统筹兼顾’‘调动积极因素’相互印证，**不神化、不照搬**。",
            "caution": "属特定历史条件下的经验总结；当代国企治理须结合现代企业制度与法治，不能简单套用。"
        },
        {
            "title": "《论十大关系》相关的建设性研究（民间 · 非官方）",
            "author": "民间左翼学者 / 老干部回忆（示例：南街村、华西村集体经济的公开调研报告）",
            "kind": "private",
            "intro": "民间对集体经济与群众路线的田野调查与反思，属‘建设性反思’一类的私人版本读物。",
            "points": [
                "记录公有制集体经济在基层的真实做法、成效与困境（如管理僵化、代际传承等）。",
                "强调‘没有调查就没有发言权’，主张立足实践、不回避矛盾。"
            ],
            "how_to_use": "作为‘不同视角的参考’阅读，须与官方乡村振兴战略、宪法关于公有制主体地位的规定对照。",
            "caution": "个人观点·非官方版本，未经权威审定；只可作争鸣参考，不得替代经典与党的理论，若出现‘全面否定现行制度’的表述即属越界，不得采信。"
        }
    ],
    "sec_C_05": [
        {
            "title": "《矛盾论》",
            "author": "毛泽东（1937）",
            "kind": "classic",
            "intro": "两类矛盾学说的哲学基础：矛盾的普遍性与特殊性、主要矛盾与矛盾的主要方面。",
            "points": [
                "矛盾的普遍性与特殊性、共性与个性的关系。",
                "主要矛盾和矛盾的主要方面决定事物性质，要学会抓主要矛盾。",
                "对抗性矛盾与非对抗性矛盾的区分与转化。"
            ],
            "how_to_use": "与本章对照读，理解‘不同性质矛盾用不同方法解决’的哲学根据。",
            "link": "https://www.marxists.org/chinese/maozedong/marxist.org-chinese-mao-193708.htm",
            "local_work": "矛盾论"
        },
    ],
    "sec_A_06": [
        {
            "title": "《德意志意识形态》（节选·费尔巴哈章）",
            "author": "马克思恩格斯（1845—1846）",
            "kind": "classic",
            "intro": "《宣言》所依据的历史唯物主义原理的系统阐述。",
            "points": [
                "社会存在决定社会意识。",
                "物质生产是历史的第一个前提。",
                "生产力与交往形式的矛盾推动社会更替。"
            ],
            "how_to_use": "配合下一章精读，先建立『生活决定意识』的唯物史观框架。",
            "local_work": "德意志意识形态"
        }
    ],
    "sec_A_07": [
        {
            "title": "《〈政治经济学批判〉序言》",
            "author": "马克思（1859）",
            "kind": "classic",
            "intro": "唯物史观最凝练的经典表述：生产力—生产关系—上层建筑。",
            "points": [
                "『不是人们的意识决定人们的存在，相反，是人们的社会存在决定人们的意识。』",
                "生产力与生产关系的矛盾是社会革命的根本原因。",
                "‘两个决不会’：旧社会形态在生产力充分发挥前不会灭亡。"
            ],
            "how_to_use": "作为本章的理论提炼来读，背熟‘社会存在决定社会意识’的完整表述。",
            "local_work": "《政治经济学批判》序言"
        }
    ],
    "sec_A_08": [
        {
            "title": "《雇佣劳动与资本》",
            "author": "马克思（1847）",
            "kind": "classic",
            "intro": "《资本论》的通俗前身，便于入门的政治经济学读本。",
            "points": [
                "工资是劳动力价值（价格）的转化形式。",
                "资本是一种社会生产关系。",
                "资本与雇佣劳动的对立统一。"
            ],
            "how_to_use": "作为《资本论》的入门预热，先建立‘资本是生产关系’的直观。",
            "local_work": "雇佣劳动与资本"
        }
    ],
    "sec_A_09": [
        {
            "title": "《国家与革命》第三章（国家与革命·巴黎公社的经验）",
            "author": "列宁（1917）",
            "kind": "classic",
            "intro": "列宁对《法兰西内战》国家学说的继承与发展。",
            "points": [
                "打碎旧国家机器是无产阶级革命的必经环节。",
                "以无产阶级专政代替资产阶级专政。"
            ],
            "how_to_use": "与本章‘打碎旧国家机器’直接对读。",
            "local_work": "国家与革命"
        }
    ],
    "sec_B_06": [
        {
            "title": "《国家与革命》序言及第一章（阶级社会与国家）",
            "author": "列宁（1917）",
            "kind": "classic",
            "intro": "从帝国主义论出发，理解国家与革命的内在联系。",
            "points": [
                "国家是阶级矛盾不可调和的产物。",
                "帝国主义把矛盾推向革命前夜。"
            ],
            "how_to_use": "承接本章，理解‘帝国主义是无产阶级革命前夜’的判断。",
            "local_work": "国家与革命"
        }
    ],
    "sec_B_08": [
        {
            "title": "《怎么办？》第一章、第二章（批评自由与自觉性）",
            "author": "列宁（1902）",
            "kind": "classic",
            "intro": "回到建党原则，理解组织与策略的连贯逻辑。",
            "points": [
                "没有革命的理论，就不会有革命的运动。",
                "自觉性高于自发性。"
            ],
            "how_to_use": "与本章‘策略灵活性’对照，理解原则坚定性是灵活性的前提。",
            "local_work": "怎么办？"
        }
    ],
    "sec_B_09": [
        {
            "title": "《中国社会各阶级的分析》",
            "author": "毛泽东（1925）",
            "kind": "classic",
            "intro": "与本章一脉相承的阶级分析方法，可对照阅读。",
            "points": [
                "分清敌友是革命的首要问题。",
                "以经济地位与革命态度划分阶级。"
            ],
            "how_to_use": "与《湖南农民运动考察报告》对照，理解阶级分析方法的连续运用。",
            "local_work": "中国社会各阶级的分析"
        }
    ],
    "sec_B_10": [
        {
            "title": "《整顿党的作风》",
            "author": "毛泽东（1942）",
            "kind": "classic",
            "intro": "延安整风姊妹篇，进一步展开反对主观主义、宗派主义与党八股。",
            "points": [
                "反对主观主义以整顿学风、反对宗派主义以整顿党风、反对党八股以整顿文风。",
                "理论和实践相结合是党的优良作风。"
            ],
            "how_to_use": "与《改造我们的学习》连读，理解整风运动的完整逻辑。",
            "local_work": "整顿党的作风"
        },
        {
            "title": "《反对党八股》",
            "author": "毛泽东（1942）",
            "kind": "classic",
            "intro": "从文风入手反对主观主义，是实事求是思想路线在文风上的延伸。",
            "points": [
                "党八股是主观主义和宗派主义的宣传工具。",
                "提倡生动活泼、新鲜有力的马克思列宁主义文风。"
            ],
            "how_to_use": "从『文风』角度看思想路线改造，与本章呼应。",
            "local_work": "反对党八股"
        }
    ],
    "sec_C_06": [
        {
            "title": "《国家与革命》第一章（阶级社会和国家）",
            "author": "列宁（1917）",
            "kind": "classic",
            "intro": "列宁对恩格斯国家学说的直接继承与发展。",
            "points": [
                "国家是阶级矛盾不可调和的产物和表现。",
                "国家是阶级压迫的暴力机关。"
            ],
            "how_to_use": "与本书第九章对读，理解国家学说的连续性。",
            "local_work": "国家与革命"
        }
    ],
    "sec_C_07": [
        {
            "title": "《新民主主义论》",
            "author": "毛泽东（1940）",
            "kind": "classic",
            "intro": "其中『新民主主义的文化』一节是本章上层建筑理论的前奏。",
            "points": [
                "新民主主义文化是民族的、科学的、大众的文化。",
                "文化是政治经济的反映，又反作用于政治经济。"
            ],
            "how_to_use": "阅读『新民主主义的文化』一节，理解文化与政治经济的关系。",
            "local_work": "新民主主义论"
        }
    ],
    "sec_A_04": [
        {
            "title": "《马克思主义的三个来源和三个组成部分》",
            "author": "列宁（1913）",
            "kind": "classic",
            "intro": "从整体上把握马克思主义的三大来源（德国古典哲学、英国古典政治经济学、法国空想社会主义）与三个组成部分。",
            "points": [
                "马克思主义哲学、政治经济学、科学社会主义是严整的统一整体。",
                "它是人类先进思想的结晶与批判继承。"
            ],
            "how_to_use": "作为“纯理论研究”主线的理论地图通读，把握马克思主义的整体结构。",
            "local_work": "马克思主义的三个来源和三个组成部分"
        }
    ],
    # ---------------- 路线 A：体系收拢（D97）----------------
    "sec_A_13": [
        {
            "title": "《辩证唯物主义 历史唯物主义》",
            "author": "艾思奇 主编（1961/1978 人民出版社）",
            "kind": "classic",
            "intro": "同一体系的中国化教科书版：上篇辩证唯物主义、下篇历史唯物主义，第十六章讲人民群众与个人在历史上的作用。",
            "points": [
                "上篇：物质与意识、对立统一规律、质量互变、否定之否定、唯物辩证法的基本范畴、认识和实践、真理。",
                "下篇：历史唯物主义与历史唯心主义的根本对立、生产力和生产关系、经济基础和上层建筑、阶级和国家、社会革命、社会意识、人民群众和个人在历史上的作用。",
                "与斯大林的短篇相比，它把每个原理展开了论证和历史材料，适合作为‘把体系读厚’的课本。"
            ],
            "how_to_use": "先读本章导读里的“辩证法四特征 / 哲学唯物主义三特征”抡要，再到这里逐章求证与展开；重点对照上篇第四章（对立统一）与下篇第十一、十二章。",
            "local_work": "辩证唯物主义历史唯物主义（艾思奇）",
        },
        {
            "title": "《实践论》",
            "author": "毛泽东（1937）",
            "kind": "classic",
            "intro": "与‘世界可知性’对照读：实践是检验认识真理性的唯一标准，也是驳斥不可知论的现实依据。",
            "points": [
                "实践、认识、再实践、再认识，循环往复以至无穷。",
                "真理的标准只能是社会的实践。"
            ],
            "how_to_use": "在学完‘哲学唯物主义三项特征’的可知性一条后回顾本章，把‘可知’从命题变成方法。",
            "local_work": "实践论",
        }
    ],
    "sec_A_14": [
        {
            "title": "《辩证唯物主义和历史唯物主义》",
            "author": "斯大林（1938）",
            "kind": "classic",
            "intro": "与本章互相参读：斯大林给骨架（生产力是最活动最革命的要素、社会存在决定社会意识），教科书给血肉。",
            "points": [
                "社会底生产方式怎样，社会本身在基本上也就会怎样。",
                "生产力是生产中最活动最革命的要素，生产关系又会反过来影响生产力。",
                "社会发展史首先是生产发展史，也就是物质资料生产者本身的历史。"
            ],
            "how_to_use": "把斯大林文本中关于生产方式的几段与教科书第十一章对读，比较‘推广说’与‘结构论’的侧重。",
            "local_work": "辩证唯物主义和历史唯物主义",
            "caution": "全文照录《辩证唯物主义和历史唯物主义》1938 年单行本正文，一字未改。"
                       "立场提示：这是 1938 年为《联共（布）党史简明教程》写的章节，"
                       "体系化程度高但对某些范畴的处理偏窄，宜与恩格斯、列宁的原著对读，"
                       "不作为唯一依据。",
        },
        {
            "title": "《家庭、私有制和国家的起源》",
            "author": "恩格斯（1884）",
            "kind": "classic",
            "intro": "把教科书中‘阶级、国家是生产发展到一定历史阶段的产物’这一命题追溯到经典论证。",
            "points": [
                "两种生产：生活资料的生产与人自身的生产。",
                "国家是阶级矛盾不可调和的产物，随阶级的消失而消亡。"
            ],
            "how_to_use": "读完本章第十三章‘阶级和国家’后接着读它，把结论还原为历史考证。",
            "local_work": "家庭、私有制和国家的起源",
        }
    ]
}

# ---------------------------------------------------------------------------
# 二、黑名单（禁止入库）
#   不是「书单」本身，而是明确列出「哪些类型/来源不得接入」，供合规审计。
# ---------------------------------------------------------------------------
READING_BLACKLIST: list[str] = [
    "鼓吹推翻社会主义制度、否定中国共产党领导的任何文本",
    "把改革开放、中国特色社会主义道路定性为『全面复辟』『社会帝国主义』的文本",
    "境外反华势力以『原教旨马列毛』为包装的出版物与网站内容",
    "秘鲁共产党（光辉道路）、菲律宾共产党、印度共产党（毛主义）等被依法定性为反政府武装/恐怖组织的文献",
    "任何未标注真实出处、无法溯源到权威版本、或鼓吹暴力颠覆的『油印本/地下出版物』",
]


# D98：必读书单补位（导读型延伸阅读，表在 reading_extensions_d98.py）
# 只 append 不 reorder：既有章节的条目顺序与前端展示保持原样。
for _sid, _items in D98_EXTENSIONS.items():
    READING_EXTENSIONS.setdefault(_sid, []).extend(_items)
del _sid, _items

# D99：源表实际 11 条（sec_B_04 四篇 + 其余七条），一律导读型（写作时无正文、不摘原文）。
# 注意：D99 头注释与早期设计文档曾声称还包含「周恩来六篇 + 《论联合政府》《唯物主义史论丛》」
# 等条目，但**源表并未落地**；这些欠账已由 D100 补齐，详见 .local/route_books_audit.md。
# 刻意不收（红线）：托洛茨基系列、第 6 阶段批判对象、西方马克思主义/资产阶级社会学。
from content.reading_extensions_d99 import D99_EXTENSIONS as _D99

for _sid, _items in _D99.items():
    READING_EXTENSIONS.setdefault(_sid, []).extend(_items)
del _sid, _items, _D99

# D100：设计文档点名欠账（P0）+ 三路线谱系补环（P1）+ 镜像无可靠全文的导读（P2）。
# 与 D98/D99 不同，本表条目大多已由 scripts/import_mirror.py 照录入库并自带 local_work。
from content.reading_extensions_d100 import D100_EXTENSIONS as _D100

for _sid, _items in _D100.items():
    READING_EXTENSIONS.setdefault(_sid, []).extend(_items)
del _sid, _items, _D100

# D103：按「合适章节」节选的 15 部原著（毛 8 / 列 2 / 斯 3 / 马 1 / 恩 1），全部自带 local_work。
# 裁剪范围见 scripts/import_mirror.py 的 TRIM；不新开章节。
from content.reading_extensions_d103 import D103_EXTENSIONS as _D103

for _sid, _items in _D103.items():
    READING_EXTENSIONS.setdefault(_sid, []).extend(_items)
del _sid, _items, _D103

# D104：军事、过渡时期政治、经济政策、文化四块的 26 部原著（节选口径同 D103），
# 全部自带 local_work。裁剪范围见 scripts/import_mirror.py 的 TRIM。
from content.reading_extensions_d104 import D104_EXTENSIONS as _D104

for _sid, _items in _D104.items():
    READING_EXTENSIONS.setdefault(_sid, []).extend(_items)
del _sid, _items, _D104

# D105：帝国主义论三源头（希法亭／卢森堡／布哈林）+ 《剩余价值理论》+ 《神圣家族》，
# 以及并入《资本论（第一卷节选）》的第十一至十三章（相对剩余价值的生产）。
from content.reading_extensions_d105 import D105_EXTENSIONS as _D105

for _sid, _items in _D105.items():
    READING_EXTENSIONS.setdefault(_sid, []).extend(_items)
del _sid, _items, _D105

# D114：给「延伸阅读为空」的三章（sec_A_03 / sec_A_05 / sec_B_00）补可选读物。
# 只从已入库正文的著作里选，全部 classic 档；不新增章节。
from content.reading_extensions_d114 import D114_EXTENSIONS as _D114

for _sid, _items in _D114.items():
    READING_EXTENSIONS.setdefault(_sid, []).extend(_items)
del _sid, _items, _D114

# D116：组织领导／群众路线谱系补环（3 篇毛泽东短篇 + 2 篇刘少奇节选），
# 全部自带 local_work；裁剪范围见 scripts/import_mirror.py 的 TRIM；不新开章节。
from content.reading_extensions_d116 import D116_EXTENSIONS as _D116

for _sid, _items in _D116.items():
    READING_EXTENSIONS.setdefault(_sid, []).extend(_items)
del _sid, _items, _D116

# D117：① 工人运动谱系补环（邓中夏《中国职工运动简史》节选 → sec_B_01/sec_B_08、
# 刘少奇 1926 职工运动方针 → sec_B_04）② 六个薄章节补白（sec_A_00/A_01/A_12、
# sec_B_02、sec_C_03/C_06，均指向库内已有正文，不新增文本）。
# 新入库 2 部的裁剪范围见 scripts/import_mirror.py 的 TRIM；章节数仍为 32。
from content.reading_extensions_d117 import D117_EXTENSIONS as _D117

for _sid, _items in _D117.items():
    READING_EXTENSIONS.setdefault(_sid, []).extend(_items)
del _sid, _items, _D117

# D118：建党前史（1918—1926）—— 李大钊 6 篇 + 蔡和森 2 篇，全文照录、不设 TRIM。
# 挂接：sec_A_06（宣言入门）3 条、sec_A_07（唯物史观创立）2 条、
# sec_B_01（建党原则）2 条、sec_B_04（组织领导）1 条；章节数仍为 32。
from content.reading_extensions_d118 import D118_EXTENSIONS as _D118

for _sid, _items in _D118.items():
    READING_EXTENSIONS.setdefault(_sid, []).extend(_items)
del _sid, _items, _D118

# D119：建党文献原文（1920—1925）——《中共中央文件选集》第一册 10 篇，全文照录、不设 TRIM。
# 挂接：sec_B_01（建党原则）4 条、sec_B_04（组织领导）3 条、sec_B_08（战略策略）1 条、
# sec_C_02（新民主主义论）1 条、sec_C_06（国家的起源）1 条；章节数仍为 32。
from content.reading_extensions_d119 import D119_EXTENSIONS as _D119

for _sid, _items in _D119.items():
    READING_EXTENSIONS.setdefault(_sid, []).extend(_items)
del _sid, _items, _D119

# D120：周恩来建国后文献 6 篇（1951—1963），全文照录、不设 TRIM。
# 挂接：sec_B_10（实事求是）1 条、sec_C_03（论人民民主专政）1 条、
# sec_C_04（论十大关系）1 条、sec_C_06（国家的起源）1 条、
# sec_C_07（上层建筑与文艺）2 条；章节数仍为 32。
from content.reading_extensions_d120 import D120_EXTENSIONS as _D120

for _sid, _items in _D120.items():
    READING_EXTENSIONS.setdefault(_sid, []).extend(_items)
del _sid, _items, _D120

# D121：普列汉诺夫前期哲学著作 2 篇（1898《个人在历史上的作用问题》／1895《奥古斯丹·
# 梯叶里和唯物史观》），全文照录、不设 TRIM。只取马克思主义时期（1883—1903）的著作，
# 1903 年后转孟什维克、护国主义与反对十月革命的那批文字一律不入。
from content.reading_extensions_d121 import D121_EXTENSIONS as _D121

for _sid, _items in _D121.items():
    READING_EXTENSIONS.setdefault(_sid, []).extend(_items)
del _sid, _items, _D121

# D122：妇女运动文献 13 篇（1920—1933）——向警予 8 篇 + 党的三大/四大妇女决议 2 篇
# + 蔡特金 3 篇。只收妇女解放与劳动解放这条主线上的文献；柯伦泰整批不收（无一份
# 可溯源到正式中文出版物，且《工人反对派》等属被列宁批判的路线），蔡特金《罗莎·卢森堡
# 对俄国革命的态度》亦不收。全文照录、不设 TRIM。
from content.reading_extensions_d122 import D122_EXTENSIONS as _D122

for _sid, _items in _D122.items():
    READING_EXTENSIONS.setdefault(_sid, []).extend(_items)
del _sid, _items, _D122

# D123：恽代英文献 22 篇（1925—1930）——理论著作与讲演 12 篇 + 工运与苏维埃史料 10 篇。
# 只收可溯源到原刊或权威单行本的篇目；《红旗》署「稚宜」的新闻体短评 6 篇、
# 私人文字与散文 7 篇不收。两篇长篇按讲次/小节标题行裁为节选，其余全文照录、一字未改。
from content.reading_extensions_d123 import D123_EXTENSIONS as _D123

for _sid, _items in _D123.items():
    READING_EXTENSIONS.setdefault(_sid, []).extend(_items)
del _sid, _items, _D123

# D124：克鲁普斯卡娅「列宁怎样读书、研究、宣传」10 篇——整本《列宁是怎样写作
# 学习的》按篇节选 7 篇 + 《论列宁》单篇 3 篇。篇内全文照录、一字未改。
from content.reading_extensions_d124 import D124_EXTENSIONS as _D124

for _sid, _items in _D124.items():
    READING_EXTENSIONS.setdefault(_sid, []).extend(_items)
del _sid, _items, _D124

# D125：按九个章节的内容缺口补 13 篇——列宁 1917 年夺权三篇、马克思《论犹太人
# 问题》、李大钊四篇（巴黎公社／土地与农民／红枪会／中国民族革命观）、周恩来
# 两篇（统一战线／民族政策）、毛泽东宪法草案讲话、邓中夏《我们的力量》。
# 篇内全文照录、一字未改；《卡尔·马克思》按小节标题裁为哲学部分。
from content.reading_extensions_d125 import D125_EXTENSIONS as _D125

for _sid, _items in _D125.items():
    READING_EXTENSIONS.setdefault(_sid, []).extend(_items)
del _sid, _items, _D125

# D126：按六章的内容缺口补周恩来民主革命期 12 篇——建军组织两篇（九月来信／肃清
# 非无产阶级意识）、夺权与政权更替两篇（全国大反攻／和平谈判）、阶级性质判定一篇、
# 统战与策略三篇（现时政治斗争中之我们／党对国民党的关系／一年来的谈判及前途）、
# 分类指导一篇（老区半老区土改与整党）、建国与经济建设三篇（共同纲领特点／恢复
# 生产／新民主主义的经济建设）。篇内全文照录、一字未改，不设裁剪。
from content.reading_extensions_d126 import D126_EXTENSIONS as _D126

for _sid, _items in _D126.items():
    READING_EXTENSIONS.setdefault(_sid, []).extend(_items)
del _sid, _items, _D126

# D127：按四章的内容缺口补考茨基 4 篇——资本论一章补「同时代人怎么把《资本论》
# 第一卷讲给工人听」（马克思的经济学说）、建党原则一章补「纲领逐条解说」的范本
# （爱尔福特纲领解说）、农村调查一章补农村阶级经济地位的长篇拆解（土地问题）、
# 历史唯物主义要义一章补「用唯物史观处理一个具体对象」的实例（基督教之基础）。
# 四部一律记「正统/0.9」，不记经典原著：考茨基是第二国际理论家，
# 其国家与革命学说后来被列宁正面批判，条目内已写明这一立场。
from content.reading_extensions_d127 import D127_EXTENSIONS as _D127

for _sid, _items in _D127.items():
    READING_EXTENSIONS.setdefault(_sid, []).extend(_items)
del _sid, _items, _D127

# 镜像补录：D98/D99 写作时此处无正文，故一律导读；现已从 D 盘镜像照录 22 部入库，
# 对其中确有原文的条目挂 local_work 并更新 caution（其余仍保持导读）。
# D100 的条目自带 local_work，apply_upgrades 只处理匹配到且尚无 local_work 的条目。
from content.mirror_upgrades import apply_upgrades as _apply_upgrades

_apply_upgrades(READING_EXTENSIONS)
del _apply_upgrades


# 读者可见的照录说明：凡已挂正文的条目，caution 里一律注明「一字未改」，
# 让读者知道本页文字是照录原文、未经改写。只补缺失的那几句，不改原有文案。
def _ensure_verbatim_note() -> None:
    from content.book_chunks import available_works

    works = set(available_works())
    note = "本篇正文照录原文，一字未改。"
    for items in READING_EXTENSIONS.values():
        for it in items:
            if it.get("local_work") not in works:
                continue
            caution = it.get("caution") or ""
            if "一字未改" in caution:
                continue
            it["caution"] = f"{caution}{note}" if caution else note


_ensure_verbatim_note()
del _ensure_verbatim_note


def extensions_for(section_id: str) -> list[dict]:
    """返回某章的延伸阅读条目（含分档）；无则空列表。"""
    return READING_EXTENSIONS.get(section_id, [])


def blacklist() -> list[str]:
    return list(READING_BLACKLIST)
