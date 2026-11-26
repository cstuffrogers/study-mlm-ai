"""
题库扩充脚本：为每个知识点生成 易/中/难 3 道客观题 + 1 道费曼自述题。

D169 重做（用户实报「题目重复太多、完全没有易中难层次」）：
旧版每档的干扰项都是套话 ——
  「将「X」与其他概念混淆，并未准确表述其含义」「认为「X」的含义与实际定义相反」
  「在学习和运用中，应当完整把握「X」的含义，避免片面理解」
四选项里只有一个「读起来像正确答案」，**不认识知识点也能选对**，于是 103 个知识点
生成了 103 道几乎一样的题，正确项也全是「应当完整把握X」这类空话。这就是重复感的根因。

新版一律拿**真内容**做选项（来源：知识图谱里其它知识点人工撰写的定义），
四个选项都是像样的理论表述，必须真分清概念才选得出，且三档考的技能各不相同：

  易 concept_discrimination 0.30  四个真实定义里挑出属于「X」的那一条
  中 logical_deduction      0.50  给出定义，反查它对应哪个概念名
  难 error_diagnosis        0.70  四条「定义 —— 概念名」配对里找出标错（张冠李戴）的那条
  拓展 费曼 subjective      0.70  自述含义 + 指出常见错误理解（每卷只出 1 道，见 band_quota）

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

# 难度分档（与 quiz_service.BAND_* / 前端 LocalQuiz.bandOf 同口径）
EASY_MAX = 0.45
MED_MAX = 0.65
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
    for nid, n in node_map.items():
        if nid == node.get('id'):
            continue
        d = (n.get('definition') or '').strip()
        if not d or _norm(d) == own:
            continue
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


def gen_med(node: dict, pool: list, sec_id: str):
    """中：给出定义，反查是哪一个概念。"""
    name = node['name']
    defn = (node.get('definition') or '').strip()
    if not defn:
        return None
    others = [n for (n, _d) in pool][:3]
    if len(others) < 3:
        return None
    packed = _pack(name, others, node['id'], 'med')
    if not packed:
        return None
    options, answer = packed
    return _item(
        node, sec_id, 'med', 'logical_deduction',
        f'下列哪一概念，其表述是：{defn}',
        options, answer,
        f'这句话讲的是「{name}」，是它的完整表述；另三个名字各有别的对应内容，别按字面猜。',
        0.50,
    )


def gen_hard(node: dict, pool: list, sec_id: str):
    """难：四条「定义——概念名」配对里，找出把名字标错的那条（张冠李戴）。"""
    name = node['name']
    defn = (node.get('definition') or '').strip()
    if not defn or len(pool) < 3:
        return None
    pairs = [(name, defn)] + pool[:3]
    pairs = pairs[:4]                      # 4 个真实概念（含自己）
    lines = [f'「{d}」——{n}' for (n, d) in pairs]
    # 把第 2 条的定义挂到第 3 条的名字上：两个概念共用一个定义，必有一错
    if len(pairs) < 3:
        return None
    wrong = f'「{pairs[1][1]}」——{pairs[2][0]}'
    correct_line = f'「{pairs[1][1]}」——{pairs[1][0]}'
    distract = [ln for ln in lines if ln not in (wrong, correct_line)]
    packed = _pack(wrong, distract, node['id'], 'hard')
    if not packed:
        return None
    options, answer = packed
    return _item(
        node, sec_id, 'hard', 'error_diagnosis',
        f'下列关于「{name}」及相关概念的配对中，有一项把概念的名称标错了（张冠李戴），它是？',
        options, answer,
        f'标错的是「{pairs[1][1]}」这一条 —— 它对应的是「{pairs[1][0]}」，不是「{pairs[2][0]}」。'
        f'「{pairs[2][0]}」的表述是：{pairs[2][1]}',
        0.70, exempt=True,   # 里含刻意标错的配对，立场守门豁免
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
    """为一个知识点生成 易/中/难 3 道客观题 + 费曼题 + 案例应用题（缺料时跳过）。"""
    pool = pool if pool is not None else []
    out = [q for q in (
        gen_easy(node, pool, sec_id),
        gen_med(node, pool, sec_id),
        gen_hard(node, pool, sec_id),
        gen_feyn(node, sec_id),
        gen_apply(node, pool, sec_id),
    ) if q]
    return out


def difficulty_band(difficulty: float, subjective: bool) -> str:
    if subjective:
        return 'feynman'
    if difficulty < EASY_MAX:
        return 'easy'
    elif difficulty < MED_MAX:
        return 'medium'
    return 'hard'


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

        # 需要补充的难度
        needed = []
        if 'easy' not in bands:
            needed.append('easy')
        if 'medium' not in bands:
            needed.append('medium')
        if 'hard' not in bands:
            needed.append('hard')
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
