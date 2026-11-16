# -*- coding: utf-8 -*-
"""D97：为 sec_A_13 / sec_A_14（体系收拢章）追加题库条目。

红线：
  - 每题必须带真实 source_chunk_id（本次全部指向真实入库分片 CH-SDL-* / CH-DZJX-*）；
  - authority_status=reviewed、trial_only=False 才计入正式掌握度；
  - 错误诊断题的「故意错误项」须 exempt_marked=True，避免防偏离机制误杀。
"""
import io
import json
import os
import sys

BANK = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                    "backend", "content", "quiz_bank", "route_A.json")

NEW_ITEMS = [
    # ------------------------------ sec_A_13 辩证唯物主义 ------------------------------
    {
        "id": "q_a13_1", "section_id": "sec_A_13", "node_id": "kn_a13_worldview",
        "type": "concept_discrimination",
        "stem": "斯大林在《辩证唯物主义和历史唯物主义》开头如何界定「辩证唯物主义」？",
        "options": [
            "它之所以叫辩证唯物主义，是因为对自然界现象的看法、研究方法和认识方法是辩证的，"
            "而对自然界现象的解释和理论是唯物主义的",
            "它之所以叫辩证唯物主义，是因为它只研究自然界而不研究社会历史",
            "它之所以叫辩证唯物主义，是因为它把辩证法与唯物主义看作两个互不相干的体系",
            "它之所以叫辩证唯物主义，是因为它承认思维第一性、存在第二性",
        ],
        "answer": "A",
        "explanation": "该文开篇即给出定义：辩证唯物主义是马克思列宁主义党的世界观，「其所以叫作辩证唯物主义，"
                       "是因为它对自然界现象的看法、它研究自然界现象的方法、它认识这些现象的方法，是辩证的，"
                       "而它对自然界现象的解释、它的理论，是唯物主义」。D 项把第一性搞反，C 项把二者割裂，"
                       "B 项否认它对社会的推广。",
        "difficulty": 0.4, "source_chunk_id": "CH-SDL-001",
        "authority_status": "reviewed", "exempt_marked": False, "trial_only": False, "subjective": False,
    },
    {
        "id": "q_a13_2", "section_id": "sec_A_13", "node_id": "kn_a13_dialectics",
        "type": "concept_discrimination",
        "stem": "下列哪一项属于斯大林归纳的「马克思主义辩证法基本特征」之一？",
        "options": [
            "发展过程是由不显著的细小数变进到根本的质变，质变表现于由一种状态突变为另一种状态",
            "自然界现象彼此隔离、互不依赖，是各个对象的偶然堆积",
            "事物只有数量的简单增长，不存在飞跃与中断",
            "思维规律与自然界规律互不相干，各有各的领域",
        ],
        "answer": "A",
        "explanation": "四个基本特征分别是：普遍联系、不断运动发展、由量变到质变的飞跃式发展、内在矛盾的对立面"
                       "斗争是发展的实在内容。B、C 正是被他批判的形而上学特征；D 与「辩证方法同时就是认识论」相违。",
        "difficulty": 0.45, "source_chunk_id": "CH-SDL-005",
        "authority_status": "reviewed", "exempt_marked": False, "trial_only": False, "subjective": False,
    },
    {
        "id": "q_a13_3", "section_id": "sec_A_13", "node_id": "kn_a13_materialism",
        "type": "concept_discrimination",
        "stem": "关于马克思主义哲学唯物主义的基本特征，下列表述不正确的是？",
        "options": [
            "世界按其本质说来是物质的，形形色色的现象是运动着的物质的各种表现",
            "物质是第一性的，意识是第二性的，意识是物质与人脑的产物",
            "世界及其规律完全可以认识，不存在不可认识的自在之物",
            "意识是独立于物质而存在的本原，物质只是意识的外化",
        ],
        "answer": "D",
        "explanation": "A、B、C 正是斯大林归纳的三项基本特征。D 项把意识抬为本原、把物质降为意识的产物，"
                       "是典型的唯心主义命题，与该文立场根本相反。",
        "difficulty": 0.4, "source_chunk_id": "CH-SDL-013",
        "authority_status": "reviewed", "exempt_marked": False, "trial_only": False, "subjective": False,
    },
    {
        "id": "q_a13_4", "section_id": "sec_A_13", "node_id": "kn_a13_dialectics",
        "type": "logical_deduction",
        "stem": "斯大林从「发展是对立面的斗争、是由量到质的飞跃」这一辩证法结论，直接推出了什么政治结论？",
        "options": [
            "由被压迫阶级实行的革命变革是完全自然而必不可免的现象，因此不能靠改良主义使资本主义长入社会主义",
            "阶级斗争可以自行熄灭，因为量变会自然带来质变",
            "为了政治上不犯错误，应当向后看，指靠正在衰亡的阶级",
            "社会现象彼此孤立，因此只能就事论事地处理个别事件",
        ],
        "answer": "A",
        "explanation": "该文明确写道：既然由缓慢的数变进到迅速的突然的质变是发展的规律，那么由被压迫阶级"
                       "实行的革命变革当然也就是完全自然而必不可免的现象；由此「不是要熄灭阶级斗争，而是要把"
                       "阶级斗争进行到底」。B、C、D 都与原文结论相反。",
        "difficulty": 0.6, "source_chunk_id": "CH-SDL-011",
        "authority_status": "reviewed", "exempt_marked": False, "trial_only": False, "subjective": False,
    },
    {
        "id": "q_a13_5", "section_id": "sec_A_13", "node_id": "kn_a13_promotion",
        "type": "error_diagnosis",
        "stem": "有位同学说：「历史唯物主义是另一套独立的哲学，与辩证唯物主义没有关系；决定社会面貌的是"
                "地理环境和人口增长，而不是生产方式。」请指出这段话的错误所在。",
        "options": [
            "他把历史唯物主义与辩证唯物主义割裂为两套哲学，并把社会发展的决定力量错认为地理环境与人口增长",
            "他说得对，历史唯物主义确实是与辩证唯物主义无关的独立学科",
            "他的错误只在于用词不严谨，实质结论没有问题",
            "他的错误在于否认了地理环境的作用，而地理环境才是社会发展的决定原因",
        ],
        "answer": "A",
        "explanation": "两处错误：①历史唯物主义是把辩证唯物主义原理推广去研究社会生活和社会历史，"
                       "二者不可分割；②决定社会面貌、社会制度性质的不是地理环境、也不是人口增长，"
                       "而是物质资料的生产方式。原文用欧洲数千年间地理条件几乎不变而社会制度屡次更替、"
                       "以及中国人口密度高于美国却社会发展程度低于美国等事实，明确否定了地理环境决定论"
                       "与人口决定论。",
        "difficulty": 0.65, "source_chunk_id": "CH-SDL-025",
        "authority_status": "reviewed", "exempt_marked": True, "trial_only": False, "subjective": False,
    },
    {
        "id": "q_a13_6", "section_id": "sec_A_13", "node_id": "kn_a13_promotion",
        "type": "text_location",
        "stem": "「历史唯物主义就是把辩证唯物主义原理推广去研究社会生活，把辩证唯物主义原理应用于研究社会，"
                "应用于研究社会历史」——这一界定出现在该文的什么位置？",
        "options": [
            "开篇第一段的定义部分",
            "论述辩证法第四个基本特征的段落",
            "论述地理环境与人口增长的段落",
            "全书的结尾处",
        ],
        "answer": "A",
        "explanation": "该界定与「辩证唯物主义是马克思列宁主义党的世界观」同在第一段，是全篇的纲领性开头，"
                       "后续全部论述都围绕这一「推广」结构展开。",
        "difficulty": 0.45, "source_chunk_id": "CH-SDL-001",
        "authority_status": "reviewed", "exempt_marked": False, "trial_only": False, "subjective": False,
    },
    {
        "id": "q_a13_7", "section_id": "sec_A_13", "node_id": "kn_a13_dialectics",
        "type": "application",
        "stem": "某地用「每年多修 5% 的厂房、多招 5% 的工人」的渐进累积方式推进产业升级，多年后仍停留在"
                "低端加工环节。请用斯大林归纳的辩证法基本特征，指出这一做法的认识论问题，并给出改进思路。",
        "options": [],
        "answer": "",
        "explanation": "评分要点：①指出其只承认量的渐进增长，否认由量变到质变的飞跃（否认质变、否认关节点），"
                       "属形而上学发展观；②指出发展应着眼于内在矛盾的暴露与解决（技术、人才、体制的结构性矛盾），"
                       "而非单纯数量叠加；③指出「一切都依条件、地方和时间为转移」，产业升级必须抓住该地"
                       "在分工体系中的具体条件；④给出可操作建议：设定质变关节点指标、集中力量突破关键环节，"
                       "而不是平均分摊增量。给建议不代写。",
        "difficulty": 0.7, "source_chunk_id": "CH-SDL-005",
        "authority_status": "reviewed", "exempt_marked": False, "trial_only": False,
        "subjective": True,
    },
    {
        "id": "q_a13_8", "section_id": "sec_A_13", "node_id": "kn_a13_worldview",
        "type": "concept_discrimination",
        "stem": "斯大林说「辩证法不是把自然界看作静止不动的状态，而是看作不断运动、不断变化、不断革新、"
                "不断发展的状态」。这一特征在方法上的直接要求是什么？",
        "options": [
            "观察现象时不仅要从相互联系和相互制约方面去看，还要从它们的运动、变化、发展、产生和衰亡方面去看",
            "只要抓住现时似乎坚固的东西就够了，因为新生的东西总是不坚固的",
            "既然一切都在变化，就不存在任何客观规律可循",
            "既然一切都在变化，就应当只研究当下现象，不必追溯它的历史",
        ],
        "answer": "A",
        "explanation": "原文的结论是：辩证法要求我们观察现象时不仅要从各个现象的相互联系和相互制约方面去观察，"
                       "而且要从它们的运动、变化、发展、产生和衰亡方面去观察；并且「最重要的不是现时似乎坚固"
                       "但已经开始衰亡的东西，而是正在产生正在发展的东西」。B 与原文相反；C、D 把辩证法"
                       "歪曲成相对主义与非历史主义。",
        "difficulty": 0.55, "source_chunk_id": "CH-SDL-004",
        "authority_status": "reviewed", "exempt_marked": False, "trial_only": False, "subjective": False,
    },

    # ------------------------------ sec_A_14 历史唯物主义 ------------------------------
    {
        "id": "q_a14_1", "section_id": "sec_A_14", "node_id": "kn_a14_unity",
        "type": "concept_discrimination",
        "stem": "关于辩证唯物主义与历史唯物主义的关系，下列哪一说法符合艾思奇主编教科书的表述？",
        "options": [
            "二者是不可分割的有机统一整体，构成「由一整块钢铁铸成的」马克思主义哲学",
            "历史唯物主义是独立于辩证唯物主义之外的另一门学科",
            "辩证唯物主义只适用于自然界，历史唯物主义只适用于社会，两者互不贯通",
            "历史唯物主义可以先于辩证唯物主义单独成立",
        ],
        "answer": "A",
        "explanation": "教科书引列宁的话：在这个由一整块钢铁铸成的马克思主义哲学中，决不可去掉任何一个基本前提、"
                       "任何一个重要部分，不然就会离开客观真理。马克思主义哲学正是把辩证唯物主义推广到对人类"
                       "社会的认识，才把唯心主义从社会历史领域中驱逐出去。",
        "difficulty": 0.4, "source_chunk_id": "CH-DZJX-251",
        "authority_status": "reviewed", "exempt_marked": False, "trial_only": False, "subjective": False,
    },
    {
        "id": "q_a14_2", "section_id": "sec_A_14", "node_id": "kn_a14_mode",
        "type": "concept_discrimination",
        "stem": "按照历史唯物主义，一切社会发展和变革的最后决定力量是什么？",
        "options": [
            "物质资料的生产方式",
            "地理环境",
            "人口的数量与密度",
            "杰出人物的意志与智慧",
        ],
        "answer": "A",
        "explanation": "教科书明确指出：一切社会发展和变革的最后决定力量是生产方式；生产方式包含生产力和生产关系"
                       "两个方面，二者的矛盾是生产方式发展和变革的原因，也是一切社会形态的基本矛盾。"
                       "地理环境与人口增长只是社会物质生活条件，不是决定力量。",
        "difficulty": 0.4, "source_chunk_id": "CH-DZJX-267",
        "authority_status": "reviewed", "exempt_marked": False, "trial_only": False, "subjective": False,
    },
    {
        "id": "q_a14_3", "section_id": "sec_A_14", "node_id": "kn_a14_basesuper",
        "type": "concept_discrimination",
        "stem": "关于经济基础与上层建筑的矛盾同生产力与生产关系的矛盾之间的关系，教科书的表述是？",
        "options": [
            "经济基础与上层建筑矛盾的发展变化受生产力与生产关系矛盾的制约，而生产力与生产关系矛盾的解决"
            "又有赖于经济基础与上层建筑矛盾的解决",
            "经济基础与上层建筑的矛盾是唯一的基本矛盾，生产力与生产关系的矛盾从属于它且不起作用",
            "两种矛盾彼此孤立，各自在自己的领域内独立运行",
            "上层建筑决定经济基础，经济基础只是上层建筑的被动反映",
        ],
        "answer": "A",
        "explanation": "教科书指出：社会的基本矛盾除生产力和生产关系的矛盾而外，还有经济基础和上层建筑的矛盾；"
                       "后者的发展和变化受到前者的制约，而前者矛盾的解决又有赖于后者矛盾的解决。这是双向的辩证"
                       "关系，而非单向的、孤立的、或颠倒的决定关系。",
        "difficulty": 0.6, "source_chunk_id": "CH-DZJX-299",
        "authority_status": "reviewed", "exempt_marked": False, "trial_only": False, "subjective": False,
    },
    {
        "id": "q_a14_4", "section_id": "sec_A_14", "node_id": "kn_a14_classstate",
        "type": "concept_discrimination",
        "stem": "教科书如何界定国家在阶级社会中的地位？",
        "options": [
            "国家是阶级统治的工具，是上层建筑中最主要的东西",
            "国家是调和阶级矛盾、超越各阶级之上的中立机关",
            "国家是经济基础的组成部分，属于生产力范畴",
            "国家是永恒存在的社会组织形式，随人类社会一同产生",
        ],
        "answer": "A",
        "explanation": "教科书指出：在阶级社会里，生产力和生产关系之间、经济基础和上层建筑之间的矛盾，都必然表现为"
                       "阶级斗争；国家是阶级统治的工具，是上层建筑中最主要的东西。阶级、阶级斗争和国家都是社会"
                       "生产发展到一定历史阶段的产物，有自己的发生、发展和灭亡的规律——因此既非超阶级中立机关，"
                       "也非永恒存在。",
        "difficulty": 0.45, "source_chunk_id": "CH-DZJX-323",
        "authority_status": "reviewed", "exempt_marked": False, "trial_only": False, "subjective": False,
    },
    {
        "id": "q_a14_5", "section_id": "sec_A_14", "node_id": "kn_a14_masses",
        "type": "concept_discrimination",
        "stem": "历史唯物主义在「人民群众与个别人物在历史上的作用」问题上的主张是？",
        "options": [
            "肯定人民群众对历史发展具有决定作用，同时承认个别人物在历史上也有重大的作用",
            "历史是由少数英雄人物的意志决定的，人民群众只是被动追随者",
            "只有人民群众起作用，个别人物的任何作用都应被否认",
            "人民群众与个别人物在历史中的作用无法比较，也不存在谁决定谁的问题",
        ],
        "answer": "A",
        "explanation": "教科书指出：历史唯物主义从生产方式是人类社会存在和发展的基础的观点出发，肯定人民群众对于"
                       "历史的发展具有决定作用，同时承认个别人物在历史上也有重大的作用。这既反对英雄史观（B），"
                       "也避免了把个人作用一笔抹杀的片面性（C）。",
        "difficulty": 0.45, "source_chunk_id": "CH-DZJX-426",
        "authority_status": "reviewed", "exempt_marked": False, "trial_only": False, "subjective": False,
    },
    {
        "id": "q_a14_6", "section_id": "sec_A_14", "node_id": "kn_a14_mode",
        "type": "logical_deduction",
        "stem": "如果承认生产方式是社会发展的决定力量，那么研究社会历史规律的正确入手处应当是？",
        "options": [
            "到社会在每个一定历史时期所采取的生产方式中、即到社会的经济中去探求",
            "到人们的头脑中、到社会的观点和观念中去探求",
            "到地理环境的变迁中去探求",
            "到杰出人物的言论与文件中探求",
        ],
        "answer": "A",
        "explanation": "这是历史唯物主义的方法论结论：研究社会历史规律的关键并不是到人们底头脑中、到社会底观点和"
                       "观念中去探求，而是要到社会在每个一定历史时期所采取的生产方式中、即要到社会底经济中去探求；"
                       "历史科学的首要任务是研究和揭示生产力与生产关系发展的规律、社会经济发展的规律。",
        "difficulty": 0.6, "source_chunk_id": "CH-DZJX-267",
        "authority_status": "reviewed", "exempt_marked": False, "trial_only": False, "subjective": False,
    },
    {
        "id": "q_a14_7", "section_id": "sec_A_14", "node_id": "kn_a14_basesuper",
        "type": "error_diagnosis",
        "stem": "有人主张：「既然经济基础决定上层建筑，那么思想文化工作无关紧要，等着经济上去了自然会好。」"
                "请依据教科书关于上层建筑反作用的论述，指出这一看法的错误。",
        "options": [
            "它把「经济基础决定上层建筑」曲解为上层建筑消极无为，否认了上层建筑对经济基础的反作用",
            "它完全正确，因为决定作用就意味着被决定者没有任何反作用",
            "它的错误在于高估了上层建筑的反作用，经济基础其实并不起决定作用",
            "它的错误在于否认了经济基础的存在，把一切都归于思想文化",
        ],
        "answer": "A",
        "explanation": "错误在于把「决定」读成「唯一起作用」。教科书强调社会形态是经济基础与上层建筑的统一，"
                       "经济基础决定上层建筑，上层建筑又反作用于经济基础；两种基本矛盾相互制约、相互促进。"
                       "因此思想文化工作不是可有可无，而是参与矛盾解决的必要环节。B 项为错误话术本身，"
                       "C、D 又把关系颠倒或抹掉。",
        "difficulty": 0.65, "source_chunk_id": "CH-DZJX-299",
        "authority_status": "reviewed", "exempt_marked": True, "trial_only": False, "subjective": False,
    },
    {
        "id": "q_a14_8", "section_id": "sec_A_14", "node_id": "kn_a14_classstate",
        "type": "application",
        "stem": "某单位在推进改革时，把「阶级分析」简单等同于「给人贴标签、搞对立」，导致人心涣散。"
                "请依据教科书关于阶级、国家和阶级斗争的论述，说明应当如何正确运用阶级分析方法，"
                "并指出该单位做法的问题。",
        "options": [],
        "answer": "",
        "explanation": "评分要点：①阶级分析的根本对象是生产关系（对生产资料的占有关系）而不是个人的出身、"
                       "言论或人际恩怨；②阶级斗争是生产力和生产关系、经济基础和上层建筑矛盾的表现，"
                       "分析要落到社会基本矛盾上，而不是制造人际对立；③国家是阶级统治的工具，"
                       "社会主义国家的工作人员必须依靠群众、服务群众，不能把群众当作敌对面；"
                       "④改进建议：把分析对象从「人」转为「制度与利益关系」，用调查研究代替标签化。给建议不代写。",
        "difficulty": 0.75, "source_chunk_id": "CH-DZJX-323",
        "authority_status": "reviewed", "exempt_marked": False, "trial_only": False,
        "subjective": True,
    },
]


def main() -> int:
    with io.open(BANK, "r", encoding="utf-8") as f:
        doc = json.load(f)
    items = doc["items"]
    have = {it["id"] for it in items}
    added = 0
    for it in NEW_ITEMS:
        if it["id"] in have:
            # 幂等：覆盖同 id 条目
            for i, old in enumerate(items):
                if old["id"] == it["id"]:
                    items[i] = it
            continue
        items.append(it)
        have.add(it["id"])
        added += 1
    text = json.dumps(doc, ensure_ascii=False, indent=2) + "\n"
    raw = text.encode("utf-8")
    with open(BANK, "wb") as f:
        f.write(raw)
    chk = open(BANK, "rb").read()
    assert chk.count(b"\r") == 0, "写入后出现 CR，违反文本红线"
    print("added=%d total=%d" % (added, len(items)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
