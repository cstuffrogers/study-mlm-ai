
// ============================================================
// 正统马克思主义哲学知识图谱 — Neo4j Schema & Seed Data
// 版本: v1.0-precision
// 用途: RAG检索的图索引层，支撑概念推理与立场校验
// ============================================================

// --------------------------------------------------
// 1. 约束与索引（性能与唯一性保障）
// --------------------------------------------------
CREATE CONSTRAINT concept_name IF NOT EXISTS
  FOR (c:Concept) REQUIRE c.name IS UNIQUE;

CREATE CONSTRAINT proposition_id IF NOT EXISTS
  FOR (p:Proposition) REQUIRE p.id IS UNIQUE;

CREATE CONSTRAINT chunk_id IF NOT EXISTS
  FOR (ch:TextChunk) REQUIRE ch.chunk_id IS UNIQUE;

CREATE CONSTRAINT author_name IF NOT EXISTS
  FOR (a:Author) REQUIRE a.name IS UNIQUE;

CREATE CONSTRAINT work_title IF NOT EXISTS
  FOR (w:Work) REQUIRE w.title IS UNIQUE;

CREATE INDEX concept_layer_idx IF NOT EXISTS
  FOR (c:Concept) ON (c.layer);

CREATE INDEX concept_authority_idx IF NOT EXISTS
  FOR (c:Concept) ON (c.authority_score);

CREATE INDEX chunk_layer_idx IF NOT EXISTS
  FOR (ch:TextChunk) ON (ch.layer);

CREATE INDEX chunk_orthodoxy_idx IF NOT EXISTS
  FOR (ch:TextChunk) ON (ch.orthodoxy_tag);

CREATE INDEX proposition_logic_idx IF NOT EXISTS
  FOR (p:Proposition) ON (p.logical_type);

// --------------------------------------------------
// 2. 作者节点（Author）
// --------------------------------------------------
MERGE (marx:Author {name: "马克思", era: "经典", camp: "正统"})
MERGE (engels:Author {name: "恩格斯", era: "经典", camp: "正统"})
MERGE (lenin:Author {name: "列宁", era: "发展", camp: "正统"})
MERGE (stalin:Author {name: "斯大林", era: "体系化", camp: "正统"})
MERGE (mao:Author {name: "毛泽东", era: "中国化", camp: "正统"})
MERGE (aishi:Author {name: "艾思奇", era: "中国化", camp: "正统"})
MERGE (lukacs:Author {name: "卢卡奇", era: "西马", camp: "非正统"})
MERGE (althusser:Author {name: "阿尔都塞", era: "西马", camp: "非正统"})
MERGE (laclau:Author {name: "拉克劳", era: "后马", camp: "非正统"});

// --------------------------------------------------
// 3. 著作节点（Work）
// --------------------------------------------------
MERGE (thesen:Work {title: "关于费尔巴哈的提纲", year: 1845, type: "原著", language: "德文"})
MERGE (de:Work {title: "德意志意识形态", year: 1846, type: "原著", language: "德文"})
MERGE (capital1:Work {title: "资本论第一卷", year: 1867, type: "原著", language: "德文"})
MERGE (aem:Work {title: "唯物主义和经验批判主义", year: 1908, type: "发展", language: "俄文"})
MERGE (phil_notes:Work {title: "哲学笔记", year: 1916, type: "发展", language: "俄文"})
MERGE (diamat:Work {title: "论辩证唯物主义和历史唯物主义", year: 1938, type: "体系化", language: "俄文"})
MERGE (prac:Work {title: "实践论", year: 1937, type: "中国化", language: "中文"})
MERGE (contradiction:Work {title: "矛盾论", year: 1937, type: "中国化", language: "中文"})
MERGE (textbook2023:Work {title: "马克思主义基本原理2023版", year: 2023, type: "教科书", language: "中文"})
MERGE (aishi_book:Work {title: "辩证唯物主义历史唯物主义", year: 1961, type: "教科书", language: "中文"})
MERGE (hist_con:Work {title: "历史与阶级意识", year: 1923, type: "西马", language: "德文"})
MERGE (pm:Work {title: "保卫马克思", year: 1965, type: "西马", language: "法文"})
MERGE (hs:Work {title: "领导权与社会主义策略", year: 1985, type: "后马", language: "英文"});

// --------------------------------------------------
// 4. 概念节点（Concept）— Layer 1 术语层
// --------------------------------------------------
MERGE (matter:Concept {
  name: "物质",
  canonical_definition: "标志客观实在的哲学范畴，这种客观实在是人通过感觉感知的，它不依赖于我们的感觉而存在，为我们的感觉所复写、摄影、反映。",
  layer: 1,
  authority_score: 1.0,
  category: "本体论",
  camp: "正统"
})
MERGE (consciousness:Concept {
  name: "意识",
  canonical_definition: "人脑的机能和属性，是客观存在的主观映象。",
  layer: 1,
  authority_score: 1.0,
  category: "本体论",
  camp: "正统"
})
MERGE (practice:Concept {
  name: "实践",
  canonical_definition: "人类能动地改造世界的社会性的物质活动。",
  layer: 1,
  authority_score: 1.0,
  category: "认识论",
  camp: "正统"
})
MERGE (sensuous_activity:Concept {
  name: "感性活动",
  canonical_definition: "马克思在《提纲》中使用的术语，与实践同义，强调人的活动的感性、对象性特征。",
  layer: 1,
  authority_score: 0.95,
  category: "认识论",
  camp: "正统"
})
MERGE (contradiction:Concept {
  name: "矛盾",
  canonical_definition: "事物内部对立着的诸方面之间的互相依赖又互相排斥的关系。",
  layer: 1,
  authority_score: 1.0,
  category: "辩证法",
  camp: "正统"
})
MERGE (social_being:Concept {
  name: "社会存在",
  canonical_definition: "社会生活的物质方面，主要指物质生活资料的生产及生产方式，也包括地理环境和人口因素。",
  layer: 1,
  authority_score: 1.0,
  category: "历史唯物主义",
  camp: "正统"
})
MERGE (social_consciousness:Concept {
  name: "社会意识",
  canonical_definition: "社会生活的精神方面，是社会存在的反映。",
  layer: 1,
  authority_score: 1.0,
  category: "历史唯物主义",
  camp: "正统"
})
MERGE (civil_society:Concept {
  name: "市民社会",
  canonical_definition: "在马克思历史唯物主义语境中，指与政治国家相对的物质生活关系总和，是资产阶级社会的同义语。",
  layer: 1,
  authority_score: 0.95,
  category: "历史唯物主义",
  camp: "正统"
})
MERGE (reification:Concept {
  name: "物化",
  canonical_definition: "马克思在《资本论》中使用的术语，指商品拜物教中人与人的关系表现为物与物的关系。注意：此概念在正统语境中专指商品拜物教，不可与卢卡奇的'物化'（异化）混淆。",
  layer: 1,
  authority_score: 0.9,
  category: "政治经济学",
  camp: "正统"
})
MERGE (overdetermination:Concept {
  name: "多元决定",
  canonical_definition: "阿尔都塞提出的概念，认为历史由政治、经济、意识形态等多种因素复杂地共同决定，反对经济决定论。此概念不属于正统马克思主义。",
  layer: 1,
  authority_score: 0.0,
  category: "非正统",
  camp: "非正统"
});

// --------------------------------------------------
// 5. 命题节点（Proposition）— Layer 2 精确命题
// --------------------------------------------------
MERGE (prop1:Proposition {
  id: "PROP-ME-TH-001-001",
  text: "从前的一切唯物主义（包括费尔巴哈的唯物主义）的主要缺点是：对对象、现实、感性，只是从客体的或者直观的形式去理解，而不是把它们当作感性的人的活动，当作实践去理解。",
  logical_type: "critique",
  layer: 2,
  authority_score: 1.0,
  camp: "正统"
})
MERGE (prop2:Proposition {
  id: "PROP-ME-TH-001-010",
  text: "旧唯物主义的立脚点是市民社会，新唯物主义的立脚点则是人类社会或社会的人类。",
  logical_type: "determination",
  layer: 2,
  authority_score: 1.0,
  camp: "正统"
})
MERGE (prop3:Proposition {
  id: "PROP-ME-DE-001-003",
  text: "不是人们的意识决定人们的存在，相反，是人们的社会存在决定人们的意识。",
  logical_type: "determination",
  layer: 2,
  authority_score: 1.0,
  camp: "正统"
})
MERGE (prop4:Proposition {
  id: "PROP-LENIN-AEM-004-012",
  text: "物质是标志客观实在的哲学范畴，这种客观实在是人通过感觉感知的，它不依赖于我们的感觉而存在。",
  logical_type: "definition",
  layer: 2,
  authority_score: 1.0,
  camp: "正统"
})
MERGE (prop5:Proposition {
  id: "PROP-MAO-SJ-002-001",
  text: "实践、认识、再实践、再认识，这种形式，循环往复以至无穷，而实践和认识之每一循环的内容，都比较地进到了高一级的程度。",
  logical_type: "dialectical_movement",
  layer: 2,
  authority_score: 1.0,
  camp: "正统"
})
MERGE (prop6:Proposition {
  id: "PROP-LUK-HC-001-001",
  text: "辩证法仅限于主体与客体的相互作用之中，自然界本身不存在辩证法。",
  logical_type: "negation",
  layer: 2,
  authority_score: 0.0,
  camp: "非正统"
});

// --------------------------------------------------
// 6. 文本块节点（TextChunk）— Layer 3-4 阐释与语境
// --------------------------------------------------
MERGE (ch1:TextChunk {
  chunk_id: "CH-ME-TH-001-001",
  text: "从前的一切唯物主义（包括费尔巴哈的唯物主义）的主要缺点是：对对象、现实、感性，只是从客体的或者直观的形式去理解，而不是把它们当作感性的人的活动，当作实践去理解，不是从主体方面去理解。",
  layer: 2,
  orthodoxy_tag: "正统",
  paragraph_num: 1,
  concept_mentions: ["唯物主义", "费尔巴哈", "客体", "直观", "感性", "实践", "主体"],
  authority_score: 1.0
})
MERGE (ch2:TextChunk {
  chunk_id: "CH-ME-TH-001-010",
  text: "旧唯物主义的立脚点是市民社会，新唯物主义的立脚点则是人类社会或社会的人类。",
  layer: 2,
  orthodoxy_tag: "正统",
  paragraph_num: 10,
  concept_mentions: ["旧唯物主义", "市民社会", "新唯物主义", "人类社会"],
  authority_score: 1.0
})
MERGE (ch3:TextChunk {
  chunk_id: "CH-ME-DE-001-003",
  text: "不是人们的意识决定人们的存在，相反，是人们的社会存在决定人们的意识。",
  layer: 2,
  orthodoxy_tag: "正统",
  paragraph_num: 3,
  concept_mentions: ["意识", "社会存在"],
  authority_score: 1.0
})
MERGE (ch4:TextChunk {
  chunk_id: "CH-AISHI-1961-003-015",
  text: "马克思在《提纲》第十条中指出，旧唯物主义的立脚点是市民社会。这就是说，旧唯物主义不自觉地站在了资产阶级意识形态的立场上，因为他们把抽象的、孤立的个人作为出发点，而这个个人正是资本主义市民社会的产物。",
  layer: 4,
  orthodoxy_tag: "正统",
  paragraph_num: 15,
  concept_mentions: ["旧唯物主义", "市民社会", "资产阶级", "意识形态", "个人"],
  authority_score: 0.95
})
MERGE (ch5:TextChunk {
  chunk_id: "CH-TEXTBOOK-2023-001-003",
  text: "实践是人类能动地改造世界的社会性的物质活动。实践具有直接现实性、自觉能动性和社会历史性三个基本特征。",
  layer: 4,
  orthodoxy_tag: "正统",
  paragraph_num: 3,
  concept_mentions: ["实践", "物质活动", "直接现实性", "自觉能动性", "社会历史性"],
  authority_score: 1.0
})
MERGE (ch6:TextChunk {
  chunk_id: "CH-LUK-HC-001-001",
  text: "自然辩证法不存在，辩证法只存在于主体与客体的相互作用中。如果承认自然辩证法，就是把辩证法变成了脱离人的客观规律，退回到了机械唯物主义。",
  layer: 2,
  orthodoxy_tag: "非正统",
  paragraph_num: 1,
  concept_mentions: ["自然辩证法", "主体", "客体", "机械唯物主义"],
  authority_score: 0.0
});

// --------------------------------------------------
// 7. 关系建立
// --------------------------------------------------

// 7.1 作者-著作关系
MATCH (marx:Author {name: "马克思"}), (thesen:Work {title: "关于费尔巴哈的提纲"})
MERGE (marx)-[:AUTHORED]->(thesen);

MATCH (marx:Author {name: "马克思"}), (engels:Author {name: "恩格斯"}), (de:Work {title: "德意志意识形态"})
MERGE (marx)-[:AUTHORED]->(de)
MERGE (engels)-[:CO_AUTHORED]->(de);

MATCH (lenin:Author {name: "列宁"}), (aem:Work {title: "唯物主义和经验批判主义"})
MERGE (lenin)-[:AUTHORED]->(aem);

MATCH (stalin:Author {name: "斯大林"}), (diamat:Work {title: "论辩证唯物主义和历史唯物主义"})
MERGE (stalin)-[:AUTHORED]->(diamat);

MATCH (mao:Author {name: "毛泽东"}), (prac:Work {title: "实践论"})
MERGE (mao)-[:AUTHORED]->(prac);

MATCH (mao:Author {name: "毛泽东"}), (contradiction:Work {title: "矛盾论"})
MERGE (mao)-[:AUTHORED]->(contradiction);

MATCH (aishi:Author {name: "艾思奇"}), (aishi_book:Work {title: "辩证唯物主义历史唯物主义"})
MERGE (aishi)-[:AUTHORED]->(aishi_book);

MATCH (lukacs:Author {name: "卢卡奇"}), (hist_con:Work {title: "历史与阶级意识"})
MERGE (lukacs)-[:AUTHORED]->(hist_con);

// 7.2 著作-文本块关系
MATCH (thesen:Work {title: "关于费尔巴哈的提纲"}), (ch1:TextChunk {chunk_id: "CH-ME-TH-001-001"})
MERGE (ch1)-[:BELONGS_TO {chapter: "全文", section: "第一条"}]->(thesen);

MATCH (thesen:Work {title: "关于费尔巴哈的提纲"}), (ch2:TextChunk {chunk_id: "CH-ME-TH-001-010"})
MERGE (ch2)-[:BELONGS_TO {chapter: "全文", section: "第十条"}]->(thesen);

MATCH (de:Work {title: "德意志意识形态"}), (ch3:TextChunk {chunk_id: "CH-ME-DE-001-003"})
MERGE (ch3)-[:BELONGS_TO {chapter: "第一章", section: "费尔巴哈"}]->(de);

MATCH (aishi_book:Work {title: "辩证唯物主义历史唯物主义"}), (ch4:TextChunk {chunk_id: "CH-AISHI-1961-003-015"})
MERGE (ch4)-[:BELONGS_TO {chapter: "第三章", section: "历史唯物主义"}]->(aishi_book);

MATCH (textbook2023:Work {title: "马克思主义基本原理2023版"}), (ch5:TextChunk {chunk_id: "CH-TEXTBOOK-2023-001-003"})
MERGE (ch5)-[:BELONGS_TO {chapter: "第一章", section: "实践与认识"}]->(textbook2023);

MATCH (hist_con:Work {title: "历史与阶级意识"}), (ch6:TextChunk {chunk_id: "CH-LUK-HC-001-001"})
MERGE (ch6)-[:BELONGS_TO {chapter: "什么是正统马克思主义", section: "辩证法"}]->(hist_con);

// 7.3 命题-著作关系
MATCH (prop1:Proposition {id: "PROP-ME-TH-001-001"}), (thesen:Work {title: "关于费尔巴哈的提纲"})
MERGE (prop1)-[:APPEARS_IN {location: "第一条"}]->(thesen);

MATCH (prop2:Proposition {id: "PROP-ME-TH-001-010"}), (thesen:Work {title: "关于费尔巴哈的提纲"})
MERGE (prop2)-[:APPEARS_IN {location: "第十条"}]->(thesen);

MATCH (prop3:Proposition {id: "PROP-ME-DE-001-003"}), (de:Work {title: "德意志意识形态"})
MERGE (prop3)-[:APPEARS_IN {location: "第一章"}]->(de);

MATCH (prop4:Proposition {id: "PROP-LENIN-AEM-004-012"}), (aem:Work {title: "唯物主义和经验批判主义"})
MERGE (prop4)-[:APPEARS_IN {location: "第四章"}]->(aem);

MATCH (prop5:Proposition {id: "PROP-MAO-SJ-002-001"}), (prac:Work {title: "实践论"})
MERGE (prop5)-[:APPEARS_IN {location: "全文"}]->(prac);

MATCH (prop6:Proposition {id: "PROP-LUK-HC-001-001"}), (hist_con:Work {title: "历史与阶级意识"})
MERGE (prop6)-[:APPEARS_IN {location: "什么是正统马克思主义"}]->(hist_con);

// 7.4 概念-命题关系（定义关系）
MATCH (matter:Concept {name: "物质"}), (prop4:Proposition {id: "PROP-LENIN-AEM-004-012"})
MERGE (prop4)-[:DEFINES]->(matter);

MATCH (practice:Concept {name: "实践"}), (prop1:Proposition {id: "PROP-ME-TH-001-001"})
MERGE (prop1)-[:INTRODUCES]->(practice);

MATCH (civil_society:Concept {name: "市民社会"}), (prop2:Proposition {id: "PROP-ME-TH-001-010"})
MERGE (prop2)-[:MENTIONS]->(civil_society);

MATCH (social_being:Concept {name: "社会存在"}), (prop3:Proposition {id: "PROP-ME-DE-001-003"})
MERGE (prop3)-[:DEFINES]->(social_being);

MATCH (social_consciousness:Concept {name: "社会意识"}), (prop3:Proposition {id: "PROP-ME-DE-001-003"})
MERGE (prop3)-[:DEFINES]->(social_consciousness);

// 7.5 概念等价关系（EQUIVALENT_TO）— 精度核心
MATCH (practice:Concept {name: "实践"}), (sensuous_activity:Concept {name: "感性活动"})
MERGE (practice)-[:EQUIVALENT_TO {
  equivalence_type: "同义",
  note: "马克思在《提纲》中使用'感性活动'，在《德意志意识形态》及以后使用'实践'，二者在正统体系中视为同义。",
  bidirectional: true
}]->(sensuous_activity);

MATCH (civil_society:Concept {name: "市民社会"}), (social_being:Concept {name: "社会存在"})
MERGE (civil_society)-[:EQUIVALENT_TO {
  equivalence_type: "语境等价",
  note: "在《提纲》语境中，市民社会可理解为社会存在的一种历史形态（资产阶级社会形态）。",
  bidirectional: false
}]->(social_being);

// 7.6 概念决定关系（DETERMINES）— 唯物史观核心逻辑
MATCH (social_being:Concept {name: "社会存在"}), (social_consciousness:Concept {name: "社会意识"})
MERGE (social_being)-[:DETERMINES {
  relation_type: "决定",
  note: "社会存在决定社会意识，这是历史唯物主义的根本原理。",
  exceptions: "社会意识具有相对独立性"
}]->(social_consciousness);

MATCH (matter:Concept {name: "物质"}), (consciousness:Concept {name: "意识"})
MERGE (matter)-[:DETERMINES {
  relation_type: "决定",
  note: "物质决定意识，意识是物质的反映。",
  exceptions: "意识具有能动性"
}]->(consciousness);

MATCH (practice:Concept {name: "实践"}), (consciousness:Concept {name: "意识"})
MERGE (practice)-[:DETERMINES {
  relation_type: "决定",
  note: "实践决定认识（意识的一种形式），认识来源于实践。",
  exceptions: "认识对实践有反作用"
}]->(consciousness);

// 7.7 概念对立关系（IS_OPPOSED_TO）
MATCH (matter:Concept {name: "物质"}), (consciousness:Concept {name: "意识"})
MERGE (matter)-[:IS_OPPOSED_TO {
  opposition_type: "哲学基本问题第一方面",
  note: "物质与意识何者为第一性，是划分唯物主义与唯心主义的唯一标准。"
}]->(consciousness);

MATCH (social_being:Concept {name: "社会存在"}), (social_consciousness:Concept {name: "社会意识"})
MERGE (social_being)-[:IS_OPPOSED_TO {
  opposition_type: "历史观基本问题",
  note: "社会存在与社会意识何者为第一性，是划分唯物史观与唯心史观的标准。"
}]->(social_consciousness);

// 7.8 概念-文本块关系（MENTIONS）
MATCH (matter:Concept {name: "物质"}), (ch5:TextChunk {chunk_id: "CH-TEXTBOOK-2023-001-003"})
MERGE (ch5)-[:MENTIONS {frequency: 1}]->(matter);

MATCH (practice:Concept {name: "实践"}), (ch1:TextChunk {chunk_id: "CH-ME-TH-001-001"})
MERGE (ch1)-[:MENTIONS {frequency: 1}]->(practice);

MATCH (civil_society:Concept {name: "市民社会"}), (ch2:TextChunk {chunk_id: "CH-ME-TH-001-010"})
MERGE (ch2)-[:MENTIONS {frequency: 1}]->(civil_society);

MATCH (civil_society:Concept {name: "市民社会"}), (ch4:TextChunk {chunk_id: "CH-AISHI-1961-003-015"})
MERGE (ch4)-[:MENTIONS {frequency: 2}]->(civil_society);

// 7.9 命题支持关系（SUPPORTS）
MATCH (prop2:Proposition {id: "PROP-ME-TH-001-010"}), (ch4:TextChunk {chunk_id: "CH-AISHI-1961-003-015"})
MERGE (ch4)-[:SUPPORTS {support_type: "阐释", strength: 0.95}]->(prop2);

MATCH (prop3:Proposition {id: "PROP-ME-DE-001-003"}), (ch4:TextChunk {chunk_id: "CH-AISHI-1961-003-015"})
MERGE (ch4)-[:SUPPORTS {support_type: "体系化阐释", strength: 0.9}]->(prop3);

// 7.10 命题矛盾关系（CONTRADICTS）— 用于立场校验
MATCH (prop4:Proposition {id: "PROP-LENIN-AEM-004-012"}), (prop6:Proposition {id: "PROP-LUK-HC-001-001"})
MERGE (prop6)-[:CONTRADICTS {
  contradiction_type: "根本对立",
  note: "列宁承认自然辩证法（物质客观实在），卢卡奇否认自然辩证法，认为辩证法只在主体-客体关系中存在。",
  orthodoxy_position: "列宁的立场是正统，卢卡奇的立场是非正统。"
}]->(prop4);

// 7.11 概念层级关系（IS_A / IS_FORM_OF）
MATCH (practice:Concept {name: "实践"}), (matter:Concept {name: "物质"})
MERGE (practice)-[:IS_FORM_OF {
  note: "实践是物质性的活动，属于物质范畴的一种特殊形态（人的活动形态）。"
}]->(matter);

MATCH (social_being:Concept {name: "社会存在"}), (matter:Concept {name: "物质"})
MERGE (social_being)-[:IS_FORM_OF {
  note: "社会存在是物质在社会历史领域的表现形式。"
}]->(matter);

// 7.12 文本块-命题推导关系（DERIVES_FROM）
MATCH (ch4:TextChunk {chunk_id: "CH-AISHI-1961-003-015"}), (prop2:Proposition {id: "PROP-ME-TH-001-010"})
MERGE (ch4)-[:DERIVES_FROM {derivation_type: "直接阐释"}]->(prop2);

// --------------------------------------------------
// 8. 查询示例（用于验证建库成功）
// --------------------------------------------------

// 查询1：查找"实践"的所有等价概念
// MATCH (c:Concept {name: "实践"})-[:EQUIVALENT_TO]-(e) RETURN c.name, e.name;

// 查询2：查找"市民社会"的正统定义及支持文本
// MATCH (c:Concept {name: "市民社会"})<-[:DEFINES|:MENTIONS]-(ch:TextChunk {orthodoxy_tag: "正统"})
// RETURN c.canonical_definition, ch.text, ch.chunk_id;

// 查询3：查找与卢卡奇命题矛盾的命题
// MATCH (p:Proposition {id: "PROP-LUK-HC-001-001"})-[:CONTRADICTS]-(q:Proposition)
// RETURN p.text, q.text;

// 查询4：查找"社会存在"决定的所有概念
// MATCH (c:Concept {name: "社会存在"})-[:DETERMINES]->(d:Concept)
// RETURN c.name, d.name, d.canonical_definition;

// 查询5：查找支持"旧唯物主义立脚点是市民社会"这一命题的所有正统文本块
// MATCH (p:Proposition {id: "PROP-ME-TH-001-010"})<-[:SUPPORTS]-(ch:TextChunk {orthodoxy_tag: "正统"})
// RETURN ch.chunk_id, ch.text, ch.authority_score;
