"""三学习路线与章节定义（内容层）

路线骨架严格按 `路径.txt` 的**历史三阶段**组织（这是用户指定的最高依据）：

  阶段 0「革命前 · 理论奠基」（19世纪40年代—19世纪末）
    吃透辩证法、唯物史观、政治经济学批判，读懂马恩经典原著。
    → 路线 A：纯理论研究

  阶段 1「革命中 · 组织革命」（20世纪初—1949）
    列宁帝国主义论/国家与革命 + 建党/夺权/组织建设/领导方法（毛泽东）。
    → 路线 B：组织革命

  阶段 2「建国 · 建设社会主义」（1949 至今）
    过渡时期理论、社会主义建设规律、两类矛盾（从马克思到毛泽东）。
    → 路线 C：建设社会主义国家

「1+3」公共地基：三条路线共用同一套地基章（`is_foundation=True`，见
`FOUNDATION_SECTION_IDS`）——

  1. 艾思奇《大众哲学》·建坐标系：什么是哲学（sec_A_00）
  2. 艾思奇《大众哲学》·体系化：唯物论·辩证法·认识论（sec_A_01）
  3. 马克思《关于费尔巴哈的提纲》（sec_A_02，实践观·新唯物主义）

顺序不能倒：《大众哲学》先用白话把物质/意识、矛盾、量变质变、实践这些坐标立起来，
再去读《提纲》才看得懂「实践的、新唯物主义」在反驳什么。这三章**只在路线 A 的章节
列表里出现**（不重复排进 B/C，免得同一个人学两遍），但三条路线共用它们的学情：
B/C 路线页顶部会以「公共地基」卡片把它们列出来（`/api/routes/{id}/sections` 的
`foundation` 字段），读完的打勾、没读的提示去补。

注意：掌握度按「用户 × 路线」存（`MasteryRecord.route_id`），地基章的记录挂在
`FOUNDATION_ROUTE_ID`（route_A）名下，所以地基卡片的进度一律读 route_A 的掌握度，
不读当前路线的——否则从 A 切到 B 会看到「刚学完的地基又归零」。

章内顺序参照 `学习顺序.md` / `学习顺序2.md` 的书单先后（破冰→方法论→体系化→国际视野、
破冰→辩证法预备→马克思本人登场→体系化）。凡本机知识库已入原著正文的著作，章节都挂
`local_work`，可「查看原文」直读分页全文；未入正文的著作只做导读（不伪造原文）。

参数可被 config 覆盖；章节级 unlock_threshold 缺省取 config.UNLOCK_THRESHOLD。
"""
from __future__ import annotations

from core.config import UNLOCK_THRESHOLD

# 三阶段标签（与 路径.txt 对应的历史分期）
STAGE_LABELS: dict[int, str] = {
    0: "革命前 · 理论奠基",
    1: "革命中 · 组织革命",
    2: "建国 · 建设社会主义",
}

# 公共地基「1+3」：三条路线共用这三章，按学习顺序排列（先大众哲学，后提纲）
FOUNDATION_SECTION_IDS: tuple[str, ...] = ("sec_A_00", "sec_A_01", "sec_A_02")
# 地基章的掌握度挂在哪条路线名下（掌握度按「用户 × 路线」存，地基只存一份）
FOUNDATION_ROUTE_ID = "route_A"


ROUTES: list[dict] = [
    {
        "id": "route_A",
        "name": "纯理论研究",
        "goal": "吃透马哲原理本体（唯物史观 / 辩证法 / 政治经济学批判 / 国家学说），"
                "打牢理论地基、读懂经典原著 —— 对应「革命前 · 理论奠基」阶段。",
        "est_duration": "约 5-7 个月",
        "shares_foundation": True,
        "foundation_ref": "sec_A_00,sec_A_01,sec_A_02",
    },
    {
        "id": "route_B",
        "name": "组织革命",
        "goal": "掌握怎么建党、怎么夺权、怎么把组织运转起来（列宁—毛泽东组织工作），"
                "对应「革命中 · 组织革命」阶段。",
        "est_duration": "约 2-3 个月",
        "shares_foundation": True,
        "foundation_ref": "sec_A_00,sec_A_01,sec_A_02",
    },
    {
        "id": "route_C",
        "name": "建设社会主义国家",
        "goal": "掌握过渡时期理论、社会主义建设规律、两类矛盾处理（从马克思到毛泽东），"
                "对应「建国 · 建设社会主义」阶段。",
        "est_duration": "约 2-3 个月",
        "shares_foundation": True,
        "foundation_ref": "sec_A_00,sec_A_01,sec_A_02",
    },
]


# 章节：id / route / order / stage / work / title / is_foundation / local_work / work_short
# work_short 为《查看原文》指向的原著名（book_chunks 的 work），供前端展示。
SECTIONS: list[dict] = [
    # ================= 路线 A　阶段0「革命前 · 理论奠基」 =================
    {
        "id": "sec_A_00", "route_id": "route_A", "order_index": 0, "stage_no": 0,
        "work": "艾思奇《大众哲学》", "title": "建坐标系：什么是哲学", "is_foundation": True,
        "local_work": "大众哲学", "work_short": "大众哲学",
    },
    {
        "id": "sec_A_01", "route_id": "route_A", "order_index": 1, "stage_no": 0,
        "work": "艾思奇《大众哲学》", "title": "体系化：唯物论·辩证法·认识论", "is_foundation": True,
        "local_work": "大众哲学", "work_short": "大众哲学",
    },
    {
        "id": "sec_A_02", "route_id": "route_A", "order_index": 2, "stage_no": 0,
        "work": "马克思《关于费尔巴哈的提纲》", "title": "马克思本人登场：实践与新唯物主义", "is_foundation": True,
        "local_work": "关于费尔巴哈的提纲", "work_short": "关于费尔巴哈的提纲",
    },
    {
        "id": "sec_A_06", "route_id": "route_A", "order_index": 3, "stage_no": 0,
        "work": "马克思、恩格斯《共产党宣言》", "title": "入门必读：共产党宣言", "is_foundation": False,
        "local_work": "共产党宣言", "work_short": "共产党宣言",
    },
    {
        "id": "sec_A_07", "route_id": "route_A", "order_index": 4, "stage_no": 0,
        "work": "马克思、恩格斯《德意志意识形态》", "title": "唯物史观的创立：德意志意识形态", "is_foundation": False,
        "local_work": "德意志意识形态", "work_short": "德意志意识形态",
    },
    {
        "id": "sec_A_11", "route_id": "route_A", "order_index": 5, "stage_no": 0,
        "work": "恩格斯《路德维希·费尔巴哈和德国古典哲学的终结》", "title": "哲学基本问题与德国古典哲学的终结", "is_foundation": False,
        "local_work": "路德维希·费尔巴哈和德国古典哲学的终结", "work_short": "路德维希·费尔巴哈和德国古典哲学的终结",
    },
    {
        "id": "sec_A_03", "route_id": "route_A", "order_index": 6, "stage_no": 0,
        "work": "毛泽东《实践论》《矛盾论》", "title": "实践的辩证法：从《实践论》到《矛盾论》", "is_foundation": False,
        "local_work": "实践论", "work_short": "实践论",
    },
    {
        "id": "sec_A_04", "route_id": "route_A", "order_index": 7, "stage_no": 0,
        "work": "列宁《哲学笔记》", "title": "辩证法的体系化：哲学笔记", "is_foundation": False,
        "local_work": "哲学笔记", "work_short": "哲学笔记",
    },
    {
        "id": "sec_A_12", "route_id": "route_A", "order_index": 8, "stage_no": 0,
        "work": "马克思《1844年经济学哲学手稿》", "title": "异化劳动与人的解放：1844年经济学哲学手稿", "is_foundation": False,
        "local_work": "1844年经济学哲学手稿", "work_short": "1844年经济学哲学手稿",
    },
    {
        "id": "sec_A_08", "route_id": "route_A", "order_index": 9, "stage_no": 0,
        "work": "马克思《资本论（第一卷节选）》", "title": "剩余价值与资本主义积累：资本论", "is_foundation": False,
        "local_work": "资本论（第一卷节选）", "work_short": "资本论（第一卷节选）",
    },
    {
        "id": "sec_A_05", "route_id": "route_A", "order_index": 10, "stage_no": 0,
        "work": "马克思《哥达纲领批判》", "title": "政治经济学批判：哥达纲领批判", "is_foundation": False,
        "local_work": "哥达纲领批判", "work_short": "哥达纲领批判",
    },
    {
        "id": "sec_A_09", "route_id": "route_A", "order_index": 11, "stage_no": 0,
        "work": "马克思《法兰西内战》", "title": "打碎旧国家机器：法兰西内战", "is_foundation": False,
        "local_work": "法兰西内战", "work_short": "法兰西内战",
    },

    # ================= 路线 B　阶段1「革命中 · 组织革命」 =================
    {
        "id": "sec_B_00", "route_id": "route_B", "order_index": 0, "stage_no": 0,
        "work": "马克思《关于费尔巴哈的提纲》", "title": "公共地基：实践观（共享）", "is_foundation": True,
        "local_work": "关于费尔巴哈的提纲", "work_short": "关于费尔巴哈的提纲",
    },
    {
        "id": "sec_B_06", "route_id": "route_B", "order_index": 1, "stage_no": 1,
        "work": "列宁《帝国主义是资本主义的最高阶段》", "title": "时代背景：帝国主义论", "is_foundation": False,
        "local_work": "帝国主义是资本主义的最高阶段", "work_short": "帝国主义是资本主义的最高阶段",
    },
    {
        "id": "sec_B_01", "route_id": "route_B", "order_index": 2, "stage_no": 1,
        "work": "列宁《怎么办？》", "title": "怎么办？：建党原则", "is_foundation": False,
        "local_work": "怎么办？", "work_short": "怎么办？",
    },
    {
        "id": "sec_B_02", "route_id": "route_B", "order_index": 3, "stage_no": 1,
        "work": "列宁《国家与革命》", "title": "国家与革命：夺权", "is_foundation": False,
        "local_work": "国家与革命", "work_short": "国家与革命",
    },
    {
        "id": "sec_B_08", "route_id": "route_B", "order_index": 4, "stage_no": 1,
        "work": "列宁《共产主义运动中的“左派”幼稚病》", "title": "革命政党的战略与策略：左派幼稚病", "is_foundation": False,
        "local_work": "共产主义运动中的“左派”幼稚病", "work_short": "共产主义运动中的“左派”幼稚病",
    },
    {
        "id": "sec_B_09", "route_id": "route_B", "order_index": 5, "stage_no": 1,
        "work": "毛泽东《湖南农民运动考察报告》", "title": "调查研究与阶级分析的范本：湖南农民运动考察报告", "is_foundation": False,
        "local_work": "湖南农民运动考察报告", "work_short": "湖南农民运动考察报告",
    },
    {
        "id": "sec_B_03", "route_id": "route_B", "order_index": 6, "stage_no": 1,
        "work": "毛泽东《中国社会各阶级的分析》", "title": "中国社会各阶级的分析", "is_foundation": False,
        "local_work": "中国社会各阶级的分析", "work_short": "中国社会各阶级的分析",
    },
    {
        "id": "sec_B_10", "route_id": "route_B", "order_index": 7, "stage_no": 1,
        "work": "毛泽东《改造我们的学习》", "title": "实事求是：改造我们的学习", "is_foundation": False,
        "local_work": "改造我们的学习", "work_short": "改造我们的学习",
    },
    {
        "id": "sec_B_04", "route_id": "route_B", "order_index": 8, "stage_no": 1,
        "work": "周恩来《怎样做一个好的领导者》", "title": "怎样做一个好的领导者", "is_foundation": False,
        "local_work": "怎样做一个好的领导者", "work_short": "怎样做一个好的领导者",
    },
    {
        "id": "sec_B_05", "route_id": "route_B", "order_index": 9, "stage_no": 1,
        "work": "毛泽东《反对本本主义》", "title": "反对本本主义：调查研究与独立自主", "is_foundation": False,
        "local_work": "反对本本主义", "work_short": "反对本本主义",
    },

    # ================= 路线 C　阶段2「建国 · 建设社会主义」 =================
    {
        "id": "sec_C_00", "route_id": "route_C", "order_index": 0, "stage_no": 0,
        "work": "马克思《关于费尔巴哈的提纲》", "title": "公共地基：实践观（共享）", "is_foundation": True,
        "local_work": "关于费尔巴哈的提纲", "work_short": "关于费尔巴哈的提纲",
    },
    {
        "id": "sec_C_06", "route_id": "route_C", "order_index": 1, "stage_no": 2,
        "work": "恩格斯《家庭、私有制和国家的起源》", "title": "国家的起源：家庭、私有制和国家的起源", "is_foundation": False,
        "local_work": "家庭、私有制和国家的起源", "work_short": "家庭、私有制和国家的起源",
    },
    {
        "id": "sec_C_01", "route_id": "route_C", "order_index": 2, "stage_no": 2,
        "work": "马克思《哥达纲领批判》", "title": "哥达纲领批判：过渡时期", "is_foundation": False,
        "local_work": "哥达纲领批判", "work_short": "哥达纲领批判",
    },
    {
        "id": "sec_C_02", "route_id": "route_C", "order_index": 3, "stage_no": 2,
        "work": "毛泽东《新民主主义论》", "title": "新民主主义论：革命向建设的过渡", "is_foundation": False,
        "local_work": "新民主主义论", "work_short": "新民主主义论",
    },
    {
        "id": "sec_C_03", "route_id": "route_C", "order_index": 4, "stage_no": 2,
        "work": "毛泽东《论人民民主专政》", "title": "论人民民主专政", "is_foundation": False,
        "local_work": "论人民民主专政", "work_short": "论人民民主专政",
    },
    {
        "id": "sec_C_04", "route_id": "route_C", "order_index": 5, "stage_no": 2,
        "work": "毛泽东《论十大关系》", "title": "论十大关系", "is_foundation": False,
        "local_work": "论十大关系", "work_short": "论十大关系",
    },
    {
        "id": "sec_C_07", "route_id": "route_C", "order_index": 6, "stage_no": 2,
        "work": "毛泽东《在延安文艺座谈会上的讲话》", "title": "上层建筑与文艺：在延安文艺座谈会上的讲话", "is_foundation": False,
        "local_work": "在延安文艺座谈会上的讲话", "work_short": "在延安文艺座谈会上的讲话",
    },
    {
        "id": "sec_C_05", "route_id": "route_C", "order_index": 7, "stage_no": 2,
        "work": "毛泽东《关于正确处理人民内部矛盾的问题》", "title": "两类矛盾学说", "is_foundation": False,
        "local_work": "关于正确处理人民内部矛盾的问题", "work_short": "关于正确处理人民内部矛盾的问题",
    },
    # ===== 路线 A　阶段0「革命前 · 理论奠基」· 体系收拢（D97 新增，不前插）=====
    # 刻意放在路线 A 末尾：先用短篇原典建立问题意识，再用体系教科书收口，避免教条化。
    # order_index 取 12/13（段内续序），不改动既有 id 与 order_index，确保推荐链不变。
    {
        "id": "sec_A_13", "route_id": "route_A", "order_index": 12, "stage_no": 0,
        "work": "斯大林《辩证唯物主义和历史唯物主义》", "title": "体系收拢（一）：辩证唯物主义要义",
        "is_foundation": False,
        "local_work": "辩证唯物主义和历史唯物主义", "work_short": "辩证唯物主义和历史唯物主义",
    },
    {
        "id": "sec_A_14", "route_id": "route_A", "order_index": 13, "stage_no": 0,
        "work": "艾思奇《辩证唯物主义历史唯物主义（艾思奇）》", "title": "体系收拢（二）：历史唯物主义要义",
        "is_foundation": False,
        "local_work": "辩证唯物主义历史唯物主义（艾思奇）", "work_short": "辩证唯物主义历史唯物主义（艾思奇）",
    },
]


def sections_for_route(route_id: str) -> list[dict]:
    rows = [s for s in SECTIONS if s["route_id"] == route_id]
    rows.sort(key=lambda s: s["order_index"])
    for s in rows:
        s.setdefault("unlock_threshold", UNLOCK_THRESHOLD)
    return rows


def get_section(section_id: str) -> dict | None:
    for s in SECTIONS:
        if s["id"] == section_id:
            return s
    return None


def stage_label(stage_no: int) -> str:
    return STAGE_LABELS.get(stage_no, "")


def foundation_sections() -> list[dict]:
    """公共地基章（「1+3」），按学习顺序返回。

    三条路线共用这三章，但它们只排在路线 A 的章节列表里（不重复进 B/C）。
    路线页要展示「地基学着没」就靠这个列表 + `is_foundation` 标记。
    字体不重要，顺序重要：《大众哲学》两章在前，《提纲》在后。
    """
    out: list[dict] = []
    for sid in FOUNDATION_SECTION_IDS:
        sec = get_section(sid)
        if sec is not None:
            sec.setdefault("unlock_threshold", UNLOCK_THRESHOLD)
            out.append(sec)
    return out


def foundation_ids_of_route(route_id: str) -> list[str]:
    """该路线声明共享的地基章 id（含自身已列出的那些）。"""
    route = next((r for r in ROUTES if r["id"] == route_id), None)
    if not route or not route.get("shares_foundation"):
        return []
    ref = (route.get("foundation_ref") or "").strip()
    if ref in ("", "shared"):
        return list(FOUNDATION_SECTION_IDS)
    return [x.strip() for x in ref.split(",") if x.strip()]
