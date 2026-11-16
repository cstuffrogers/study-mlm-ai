"""LLM 合成立场样本 — 调通义千问 API 生成多样化训练数据

用法（需先在 backend/.env 配 LLM_API_KEY）：
    python -m ml.synthesize_llm --count 500 --out ml/llm_samples.json

生成后合并到数据集重训：
    python -m ml.train_stance   # train_stance 自动读 llm_samples.json（如存在）

设计：
  - 复用 core.llm.cloud.CloudLayer（OpenAI 兼容协议，国产模型通用）
  - 4 类 prompt 轮询生成：orthodox / deviation / hard_negative / type_a_attack
  - 强调句式多样，避免模板重复（模板版 ml/synthesize_data 的已知局限）
  - 解析 LLM 输出（每条一行）+ 去重 + 抽检标签
  - key 缺失时友好报错，不崩
"""
from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
import logging

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")

# 4 类生成 prompt（强调多样性 + 明确标签）
GENERATION_PROMPTS = {
    "orthodox": """生成 15 条正统马克思主义哲学表述，每条一行，不带编号。

要求：
- 正典命题的原话或近原话（马克思/恩格斯/列宁/斯大林/毛泽东著作）
- 覆盖：唯物论/辩证法/认识论/历史唯物主义/政治经济学/科学社会主义
- 句式多样：定义式、命题式、论断式、引述式，不要都用同一种句式
- 每条独立成句，10-40 字
- 严禁出现西方马克思主义、修正主义、后现代、资产阶级学者的观点

示例（不要重复这些）：
- 社会存在决定社会意识，社会意识对社会存在有反作用。
- 对立统一规律是唯物辩证法的实质和核心。
- 资本的本质不是物，而是掩盖在物下面的人与人之间的生产关系。

直接输出 15 条，每条一行，无前言后语：""",

    "deviation": """生成 15 条偏离正统马克思主义的哲学表述，每条一行，不带编号。

要求：
- 西方马克思主义、修正主义、后马克思、唯心主义、资产阶级学者的观点
- 句式多样：宣扬式、断言式、引用式（"XX认为...""XX证明..."），不要都用同一种
- 覆盖：否认经济决定论、否定劳动价值论、否认阶级斗争、否认无产阶级专政、否认自然辩证法、唯心史观
- 每条独立成句，10-40 字
- 要真实体现这些思潮的错误立场（用于训练防偏离分类器）

示例（不要重复这些）：
- 社会存在与社会意识是相互决定的，不存在谁决定谁。
- 鲍德里亚的生产之镜批判了马克思的劳动价值论。
- 多种因素共同决定社会发展，经济不是唯一决定因素。

直接输出 15 条，每条一行，无前言后语：""",

    "hard_negative": """生成 15 条"批判性引用西马概念的正统文本"，每条一行，不带编号。

要求：
- 文本中**出现**西方马克思主义/修正主义/后现代的概念术语（如物化、总体性、文化领导权、生产之镜、多元决定、新教伦理等）
- 但整句是对这些概念的**批判**（指出其错误、谬误、偏离）
- 语境词：是错误的、是谬误、偏离了、不符合、是唯心主义、是修正主义、必须批判、是对...的歪曲
- 句式多样：定性式（"XX的YY是ZZ论"）、显式批判式（"XX的YY是错误的"）
- 这是困难负样本，标签是 orthodox（应放行），用于防止分类器把批判性引用误判为宣扬

示例（不要重复这些）：
- 韦伯的新教伦理是文化决定论，无法解释资本主义的全球扩张。
- 卢卡奇的物化概念是错误的，它把商品拜物教等同于异化，丢失了实践-革命维度。
- 阿尔都塞的多元决定论歪曲了经济基础决定上层建筑的原理。

直接输出 15 条，每条一行，无前言后语：""",

    "type_a_attack": """生成 15 条"批判对象攻击正统"的偏离表述，每条一行，不带编号。

要求：
- 句式：某西马/修正主义/反马学者 + 攻击动词 + 正统锚点
- 攻击动词：批判了、否定了、证伪了、推翻了、解构了、证明了...是错误的、揭示了...的矛盾
- 正统锚点：马克思的劳动价值论、剩余价值理论、历史唯物主义、阶级斗争、无产阶级专政、经济基础决定上层建筑等
- 学者：鲍德里亚、波普尔、哈耶克、韦伯、卢卡奇、阿尔都塞、葛兰西、哈贝马斯、萨特、德里达、利奥塔
- 句式多样，不要都用"XX批判了YY"一种结构
- 标签是 deviation（应拦截），关键特征是批判对象作为主体去攻击正统

示例（不要重复这些）：
- 波普尔证明历史决定论是错误的。
- 鲍德里亚的生产之镜批判了马克思的劳动价值论。
- 哈耶克论证计划经济是通往奴役之路。

直接输出 15 条，每条一行，无前言后语：""",
}

LABEL_MAP = {
    "orthodox": "orthodox",
    "deviation": "deviation",
    "hard_negative": "orthodox",  # 困难负样本标签是 orthodox
    "type_a_attack": "deviation",
}


async def _generate_batch(cloud, prompt: str, batch_size: int = 15) -> list[str]:
    """调 LLM 生成一批样本，解析成行"""
    from core.llm.base import LLMRequest
    req = LLMRequest(key=f"synth_{hash(prompt)}", prompt=prompt, task="general")
    resp = await cloud.run(req)
    lines = [ln.strip() for ln in resp.text.split("\n") if ln.strip()]
    # 去掉可能的编号前缀 "1." "2)" 等
    import re
    cleaned = []
    for ln in lines:
        ln = re.sub(r"^\s*[\d]+[\.\)]\s*", "", ln)
        if ln and len(ln) > 5:
            cleaned.append(ln)
    return cleaned[:batch_size]


async def synthesize(total: int = 500, out_path: str | None = None) -> list[dict]:
    """合成 total 条 LLM 样本（4 类轮询）"""
    from core.llm.cloud import CloudLayer
    cloud = CloudLayer()
    if not cloud.enabled:
        logger.error(
            "LLM_API_KEY 未配置。请在 backend/.env 设置：\n"
            "  LLM_API_KEY=你的通义千问key\n"
            "  LLM_BASE_URL=https://dashscope.aliyuncs.com/compatible-mode/v1\n"
            "  LLM_MODEL=qwen-plus\n"
            "申请：https://dashscope.console.aliyun.com"
        )
        return []

    categories = list(GENERATION_PROMPTS.keys())
    per_cat = total // len(categories)
    all_samples: list[dict] = []
    seen: set[str] = set()

    for cat in categories:
        batches = per_cat // 15 + 1
        for b in range(batches):
            try:
                lines = await _generate_batch(cloud, GENERATION_PROMPTS[cat])
            except Exception as e:
                logger.warning("生成 %s 批 %d 失败: %s", cat, b, e)
                continue
            for ln in lines:
                if ln in seen:
                    continue
                seen.add(ln)
                all_samples.append({
                    "text": ln, "label": LABEL_MAP[cat], "source": f"llm_{cat}",
                })
            logger.info("%s: 累计 %d 条", cat, sum(1 for s in all_samples if s["source"] == f"llm_{cat}"))
            if len([s for s in all_samples if s["source"] == f"llm_{cat}"]) >= per_cat:
                break

    if out_path:
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(all_samples, f, ensure_ascii=False, indent=2)
        logger.info("已保存 %d 条到 %s", len(all_samples), out_path)
    return all_samples


def main():
    parser = argparse.ArgumentParser(description="LLM 合成立场样本")
    parser.add_argument("--count", type=int, default=500, help="目标样本数")
    parser.add_argument("--out", type=str, default=os.path.join(os.path.dirname(__file__), "llm_samples.json"))
    args = parser.parse_args()

    samples = asyncio.run(synthesize(args.count, args.out))
    if not samples:
        sys.exit(1)
    from collections import Counter
    print(f"\n生成 {len(samples)} 条 LLM 样本")
    print(f"  按标签: {dict(Counter(s['label'] for s in samples))}")
    print(f"  按来源: {dict(Counter(s['source'] for s in samples))}")
    print(f"\n下一步：python -m ml.train_stance（自动合并 llm_samples.json 重训）")


if __name__ == "__main__":
    main()
