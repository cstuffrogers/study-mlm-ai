"""
题库扩充脚本：为每个知识点生成 1 道客观题 + 费曼自述题 + 案例应用题。

D169 重做过一次干扰项（用户实报「题目重复太多、完全没有易中难层次」）：
旧版每档的干扰项都是套话 ——
  「将「X」与其他概念混淆，并未准确表述其含义」「认为「X」的含义与实际定义相反」
  「在学习和运用中，应当完整把握「X」的含义，避免片面理解」
四选项里只有一个「读起来像正确答案」，**不认识知识点也能选对**。
于是改成拿知识图谱里其它知识点人工撰写的定义做选项。

D176（用户再报：「所谓不同难度实际上就换了一种表述而已」）——
分档本身才是重复的来源：易＝四段定义里挑一条、中＝给定义反查概念名、
难＝四条配对里找张冠李戴，**三种问法共用同一张「概念—定义」对照表**，
把同一句定义问了三遍；难档 88 个知识点的题干还是同一句模板。
所以中/难两档（gen_med / gen_hard）全部删掉，一个知识点只留：

  客观题 concept_discrimination 0.30  四段真实定义里挑出属于「X」的那一条
  费曼   subjective            0.70  自述含义 + 指出常见错误理解
  应用   application           0.70  拿准确定义当材料，举现实例子

同一知识点的这几道变体只用于**重考轮换** —— 一套卷子里每个知识点只出一道，
口径见 services.quiz_service._select_items。
答案字母按题目 id 做确定性打乱，不再恒为 A。
"""
import json
import random
import re
import sys
import os
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# backend 目录需在 path 中，因为 chapter_content 内部用 `from content.xxx`
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import chapter_content as cc

QUIZ_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'quiz_bank')

# 客观题难度（与 quiz_service 同口径：低难度客观题）
EASY_MAX = 0.45
LETTERS = 'ABCD'


def _norm(s: str) -> str:
    return re.sub(r'\s+', '', s or '')


def _seed(*parts) -> int:
    return zlib.crc32('|'.join(str(p) for p in parts).encode('utf-8'))


def _pack(correct: str, distractors: list, *seed_parts):
    """把正确答案和干扰项打散，返回 (options, answer_letter)。"""
    opts = [correct]
    seen = {_norm(correct)}
    for d in distractors:
        if _norm(d) in seen or not d:
            continue
        seen.add(_norm(d))
        opts.append(d)
        if len(opts) == 4:
            break
    if len(opts) < 4:
        return None
    random.Random(_seed(*seed_parts)).shuffle(opts)
    return opts, LETTERS[opts.index(correct)]


def concept_pool(node: dict, node_map: dict) -> list:
    """可做干扰项的 (概念名, 定义)：同一章优先 → 同一路线 → 全库。

    只收有人工撰写定义的知识点，保证选项都是准确、像样的理论表述。
    """
    sec = node.get('section_id', '')
    route = sec.split('_')[0]
    own = _norm(node.get('definition') or '')
    same_sec, same_route, other = [], [], []
    seen: set[str] = {own}   # 定义重复的知识点（如「实践」与「革命的实践」）只取一条，
                            # 否则干扰项不足 3 条，客观题生成不出来（D176）
    for nid, n in node_map.items():
        if nid == node.get('id'):
            continue
        d = (n.get('definition') or '').strip()
        if not d or _norm(d) in seen:
            continue
        seen.add(_norm(d))
        pair = (n.get('name', ''), d)
        nsec = n.get('section_id') or ''
        if nsec and nsec == sec:
            same_sec.append(pair)
        elif nsec and nsec.split('_')[0] == route:
            same_route.append(pair)
        else:
            other.append(pair)
    return same_sec + same_route + other


def _item(node, sec_id, band, typ, stem, options, answer, explanation,
          difficulty, subjective=False, exempt=False):
    return {
        'id': f'q_{node["id"]}_{band}',
        'section_id': sec_id,
        'node_id': node['id'],
        'type': typ,
        'stem': stem,
        'options': options,
        'answer': answer,
        'explanation': explanation,
        'difficulty': difficulty,
        'source_chunk_id': node.get('source_chunk_id', ''),
        'authority_status': 'reviewed',
        'exempt_marked': exempt,
        'trial_only': False,
        'subjective': subjective,
    }


def gen_easy(node: dict, pool: list, sec_id: str):
    """易：四段真实定义里挑出属于「X」的那一条。"""
    name = node['name']
    defn = (node.get('definition') or '').strip()
    if not defn:
        return None
    others = [d for (_n, d) in pool][:3]
    if len(others) < 3:
        return None
    packed = _pack(defn, others, node['id'], 'easy')
    if not packed:
        return None
    options, answer = packed
    return _item(
        node, sec_id, 'easy', 'concept_discrimination',
        f'关于「{name}」，下列说法正确的是？',
        options, answer,
        f'「{name}」：{defn}其余三项分别是其他概念的表述，注意别把相邻概念的定义当成本概念的定义。',
        0.30,
    )


def gen_feyn(node: dict, sec_id: str):
    """拓展（费曼自述）：不伪造原文，只要求复述 + 指出常见错误理解。"""
    name = node['name']
    defn = (node.get('definition') or '').strip()
    if not defn:
        return None
    return _item(
        node, sec_id, 'feyn', 'error_diagnosis',
        f'（论述/费曼）请用自己的话阐述「{name}」的含义，并指出一种常见的错误理解。',
        [], '',
        f'参考要点：「{name}」——{defn}常见错误理解：把核心关系颠倒、丢掉关键限定，'
        f'或把相邻概念的表述套到「{name}」头上。',
        0.70, subjective=True,
    )


def gen_apply(node: dict, pool: list, sec_id: str):
    """拓展（应用/案例）：把本知识点的准确表述当材料，要求落到现实例子上。

    材料就是知识图谱里这条定义本身，不编造原文；作答按论证结构 + 术语使用评分。
    """
    name = node['name']
    defn = (node.get('definition') or '').strip()
    if not defn:
        return None
    peer = f'（可与「{pool[0][0]}」对照）' if pool else ''
    item = _item(
        node, sec_id, 'apply', 'application',
        f'（应用/案例）材料：{defn}{peer}　'
        f'请结合原著关于「{name}」的论述，举一个现实中的例子，说明这条原理在什么条件下成立、'
        f'机械套用会出什么问题。',
        [], '',
        f'参考要点：先复述「{name}」的科学内涵，再指出它成立的条件与边界，最后用一个具体事例'
        f'说明怎样按这一原理办事；只堆术语、不给例子或把原理绝对化都要扣分。',
        0.70, subjective=True,
    )
    return item


def gen_questions(node: dict, sec_id: str, pool: list = None):
    """为一个知识点生成客观题 + 费曼题 + 案例应用题（缺料时跳过）。

    D176：不再生成「中（反查概念名）」「难（找张冠李戴）」—— 它们和客观题共用
    同一张概念—定义对照表，只是换个问法，一套卷子里全出来就成了重复题。
    """
    pool = pool if pool is not None else []
    out = [q for q in (
        gen_easy(node, pool, sec_id),
        gen_feyn(node, sec_id),
        gen_apply(node, pool, sec_id),
    ) if q]
    return out


def difficulty_band(difficulty: float, subjective: bool) -> str:
    if subjective:
        return 'feynman'
    return 'easy' if difficulty < EASY_MAX else 'objective'


def bank_band(it: dict) -> str:
    """题库里的「难度档」键：案例应用题单独一档，否则按 difficulty 分档。

    注意别和 services.quiz_service.band_of 混：那个是「出题档」
    （主观/应用一律 challenge），这个只管「这个知识点还缺哪类题」。
    """
    if it.get('type') == 'application' and it.get('subjective'):
        return 'apply'
    return difficulty_band(it.get('difficulty', 0.5), it.get('subjective', False))


def process_file(filename: str, section_ids: set, node_map: dict):
    """处理一个题库文件，为缺失难度的知识点补充题目。"""
    path = os.path.join(QUIZ_DIR, filename)
    with open(path, encoding='utf-8') as f:
        data = json.load(f)

    existing_items = data.get('items', [])
    existing_ids = {it['id'] for it in existing_items}

    # 统计每个知识点已有的难度分档
    node_bands = {}  # node_id -> set of bands
    for it in existing_items:
        nid = it.get('node_id', '')
        if not nid:
            continue
        band = bank_band(it)
        if nid not in node_bands:
            node_bands[nid] = set()
        node_bands[nid].add(band)

    new_questions = []
    for nid, node in node_map.items():
        sec = node.get('section_id', '')
        if sec not in section_ids:
            continue
        bands = node_bands.get(nid, set())

        # 需要补充的题型（D176：只补客观题 / 费曼 / 应用，不再补中、难档）
        needed = []
        if 'easy' not in bands and 'objective' not in bands:
            needed.append('easy')
        if 'feynman' not in bands:
            needed.append('feynman')
        if 'apply' not in bands:
            needed.append('apply')

        if not needed:
            continue

        # 生成该知识点的所有题目，然后只取需要的
        all_qs = gen_questions(node, sec, concept_pool({**node, 'section_id': sec}, node_map))
        for q in all_qs:
            band = bank_band(q)
            if band in needed:
                # 确保 ID 不冲突
                if q['id'] in existing_ids:
                    # 添加后缀避免冲突
                    suffix = 1
                    while f'{q["id"]}_{suffix}' in existing_ids:
                        suffix += 1
                    q['id'] = f'{q["id"]}_{suffix}'
                existing_ids.add(q['id'])
                new_questions.append(q)
                bands.add(band)
                needed.remove(band)

    if new_questions:
        # 新题追加到末尾，排序由 quiz_service._interleave_items 负责
        merged = list(existing_items) + new_questions

        data['items'] = merged
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

    return len(new_questions)


def main():
    # 收集所有知识点
    node_map = {}  # node_id -> node dict
    section_ids = set()

    # ROUTE_NODES 中的知识点
    for sec_id, nodes in cc.ROUTE_NODES.items():
        section_ids.add(sec_id)
        for n in nodes:
            nid = n['id']
            n_with_sec = {**n, 'section_id': sec_id}
            if nid not in node_map:
                node_map[nid] = n_with_sec

    # outline_chapter (sec_A_02) 的知识点
    outline_nodes = cc.nodes_for_section('sec_A_02')
    if outline_nodes:
        section_ids.add('sec_A_02')
        for n in outline_nodes:
            nid = n['id']
            if nid not in node_map:
                node_map[nid] = n

    print(f'共 {len(node_map)} 个知识点，涉及 {len(section_ids)} 个章节')

    # 处理四个题库文件
    # route_A.json: sec_A_00, sec_A_01, sec_A_03, sec_A_04, sec_A_05, sec_A_06, sec_A_07, sec_A_08, sec_A_09, sec_A_11, sec_A_12, sec_A_13, sec_A_14
    # route_B.json: sec_B_00~sec_B_06, sec_B_08, sec_B_09, sec_B_10
    # route_C.json: sec_C_00~sec_C_07
    # outline_chapter.json: sec_A_02

    file_sections = {
        'route_A.json': {'sec_A_00', 'sec_A_01', 'sec_A_03', 'sec_A_04', 'sec_A_05',
                         'sec_A_06', 'sec_A_07', 'sec_A_08', 'sec_A_09',
                         'sec_A_11', 'sec_A_12', 'sec_A_13', 'sec_A_14'},
        'route_B.json': {'sec_B_00', 'sec_B_01', 'sec_B_02', 'sec_B_03', 'sec_B_04',
                         'sec_B_05', 'sec_B_06', 'sec_B_08', 'sec_B_09', 'sec_B_10'},
        'route_C.json': {'sec_C_00', 'sec_C_01', 'sec_C_02', 'sec_C_03',
                         'sec_C_04', 'sec_C_05', 'sec_C_06', 'sec_C_07'},
        'outline_chapter.json': {'sec_A_02'},
    }

    total_added = 0
    for fname, secs in file_sections.items():
        n = process_file(fname, secs, node_map)
        print(f'  {fname}: 新增 {n} 道题')
        total_added += n

    print(f'\n共新增 {total_added} 道题')


if __name__ == '__main__':
    main()
