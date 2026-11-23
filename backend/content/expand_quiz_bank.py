"""
题库扩充脚本：为每个知识点生成 易/中/难 3 道客观题 + 1 道费曼自述题。

策略：
- 易 (concept_discrimination, diff ~0.30): 直接考查定义识别
- 中 (logical_deduction, diff ~0.55): 考查从定义推出的逻辑判断
- 难 (application, diff ~0.75): 考查正确运用
- 费曼 (error_diagnosis, subjective=True, diff ~0.70): 论述自述

干扰项生成：
- 反转：检测定义中的"A决定B"等关系，反转为"B决定A"
- 否定：对定义做自然否定
- 局部：仅取定义首句（不完整）
"""
import json
import re
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# backend 目录需在 path 中，因为 chapter_content 内部用 `from content.xxx`
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import chapter_content as cc

QUIZ_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'quiz_bank')

# 难度分档
EASY_MAX = 0.45
MED_MAX = 0.65


def reverse_definition(definition: str):
    """检测并反转定义中的关键关系，生成一个合理但错误的干扰项。"""
    patterns = [
        (r'(.+?)决定(.+?)(?:[，。；]|$)', lambda m: f'{m.group(2)}决定{m.group(1)}'),
        (r'(.+?)是(.+?)的(基础|前提|核心|实质|关键|根本)(?:[，。；]|$)',
         lambda m: f'{m.group(2)}是{m.group(1)}的{m.group(3)}'),
        (r'(.+?)作用于(.+?)(?:[，。；]|$)', lambda m: f'{m.group(2)}作用于{m.group(1)}'),
        (r'(.+?)产生(.+?)(?:[，。；]|$)', lambda m: f'{m.group(2)}产生{m.group(1)}'),
        (r'(.+?)反映(.+?)(?:[，。；]|$)', lambda m: f'{m.group(2)}反映{m.group(1)}'),
        (r'(.+?)源于(.+?)(?:[，。；]|$)', lambda m: f'{m.group(2)}源于{m.group(1)}'),
        (r'(.+?)来源于(.+?)(?:[，。；]|$)', lambda m: f'{m.group(2)}来源于{m.group(1)}'),
        (r'(.+?)决定着(.+?)(?:[，。；]|$)', lambda m: f'{m.group(2)}决定着{m.group(1)}'),
    ]
    for pat, fn in patterns:
        m = re.search(pat, definition)
        if m:
            result = fn(m)
            if result != definition and len(result) > 4:
                return result
    return None


def partial_definition(definition: str):
    """取定义的首句作为不完整干扰项。"""
    parts = re.split(r'[，。；]', definition)
    if len(parts) > 1:
        return parts[0]
    return None


def negate_definition(definition: str, name: str):
    """生成一个自然否定的干扰项。"""
    # 尝试否定关键动词
    for verb in ['决定', '是', '产生', '反映', '源于', '来源于', '作用于']:
        if verb in definition:
            idx = definition.index(verb)
            before = definition[:idx]
            after = definition[idx + len(verb):]
            return f'{before}并不{verb}{after}'
    # 通用否定
    return f'认为「{name}」的含义与实际定义相反'


def gen_consequence(definition: str, name: str) -> str:
    """从定义生成逻辑推论（中题的正确答案）。"""
    if '决定' in definition:
        return f'把握「{name}」是正确认识相关原理的前提与基础'
    if '基础' in definition or '前提' in definition:
        return f'离开对「{name}」的正确认识，相关理解就失去了根基'
    if any(k in definition for k in ['核心', '实质', '关键', '枢纽']):
        return f'理解「{name}」才能抓住事物的根本与关键'
    if '动力' in definition:
        return f'把握「{name}」是理解事物发展变化的关键所在'
    if '来源' in definition:
        return f'认识「{name}」的来源，是把握其作用的必要前提'
    return f'正确认识「{name}」，是把握相关原理的必要条件'


def gen_application(definition: str, name: str) -> str:
    """生成正确运用表述（难题的正确答案）。"""
    if '决定' in definition:
        return f'分析实际问题时，应当从「{name}」所揭示的关系入手，把握其决定性作用'
    if '基础' in definition or '前提' in definition:
        return f'运用「{name}」的原理，需先把握其基础地位，再分析具体问题'
    if any(k in definition for k in ['核心', '实质', '关键', '枢纽']):
        return f'运用「{name}」分析问题，关键在于把握其核心内涵，避免停留表面'
    if '动力' in definition:
        return f'运用「{name}」分析发展变化，需抓住其作为动力的机制'
    return f'在学习和运用中，应当完整把握「{name}」的含义，避免片面理解'


def gen_distractors(definition: str, name: str, correct: str):
    """生成三个干扰项。"""
    distractors = []

    # 1. 反转
    rev = reverse_definition(definition)
    if rev and rev != correct:
        distractors.append(rev)

    # 2. 局部（不完整）
    part = partial_definition(definition)
    if part and part != correct and part not in distractors:
        distractors.append(part)

    # 3. 否定
    neg = negate_definition(definition, name)
    if neg != correct and neg not in distractors:
        distractors.append(neg)

    # 确保有三个不同的干扰项
    if len(distractors) < 3:
        fallback = [
            f'将「{name}」与其他概念混淆，并未准确表述其含义',
            f'对「{name}」的表述偏离了其核心要义，不够准确',
            f'仅涉及「{name}」的表象，未触及本质',
        ]
        for f in fallback:
            if f not in distractors and f != correct:
                distractors.append(f)
            if len(distractors) >= 3:
                break

    return distractors[:3]


def gen_questions(node: dict, sec_id: str):
    """为一个知识点生成 3 道客观题 + 1 道费曼题。"""
    name = node['name']
    defn = node['definition']
    chunk = node.get('source_chunk_id', '')
    node_id = node['id']

    questions = []

    # === 易题：concept_discrimination ===
    distractors_e = gen_distractors(defn, name, defn)
    questions.append({
        'id': f'q_{node_id}_easy',
        'section_id': sec_id,
        'node_id': node_id,
        'type': 'concept_discrimination',
        'stem': f'关于「{name}」，下列说法正确的是？',
        'options': [defn, *distractors_e],
        'answer': 'A',
        'explanation': f'「{name}」的核心定义是：{defn}。B、C、D 项分别在核心关系、完整性和准确性上与定义不符。',
        'difficulty': 0.30,
        'source_chunk_id': chunk,
        'authority_status': 'reviewed',
        'exempt_marked': False,
        'trial_only': False,
        'subjective': False,
    })

    # === 中题：logical_deduction ===
    consequence = gen_consequence(defn, name)
    distractors_m = gen_distractors(defn, name, consequence)
    # 如果干扰项与正确答案重复，替换
    while len(distractors_m) < 3:
        distractors_m.append(f'对「{name}」的推论偏离了其定义所揭示的关系')
    questions.append({
        'id': f'q_{node_id}_med',
        'section_id': sec_id,
        'node_id': node_id,
        'type': 'logical_deduction',
        'stem': f'根据「{name}」的内涵，可以判断下列哪一说法成立？',
        'options': [consequence, *distractors_m[:3]],
        'answer': 'A',
        'explanation': f'由「{name}」的定义（{defn}）可推出：{consequence}。其余选项的推论与定义所揭示的关系不符。',
        'difficulty': 0.55,
        'source_chunk_id': chunk,
        'authority_status': 'reviewed',
        'exempt_marked': False,
        'trial_only': False,
        'subjective': False,
    })

    # === 难题：logical_deduction（客观选择题）
    # 注意：不能标 type=application —— application 走自由文本论证评分
    #（_grade_application），带 options 的选择题会被当成空作答判 0。
    application = gen_application(defn, name)
    distractors_h = gen_distractors(defn, name, application)
    while len(distractors_h) < 3:
        distractors_h.append(f'对「{name}」的运用偏离了其核心原理，属于错误应用')
    questions.append({
        'id': f'q_{node_id}_hard',
        'section_id': sec_id,
        'node_id': node_id,
        'type': 'logical_deduction',
        'stem': f'在学习与运用「{name}」时，下列做法正确的是？',
        'options': [application, *distractors_h[:3]],
        'answer': 'A',
        'explanation': f'「{name}」的定义是{defn}，正确运用要求把握其完整内涵：{application}。其余选项在运用中偏离了核心原理。',
        'difficulty': 0.75,
        'source_chunk_id': chunk,
        'authority_status': 'reviewed',
        'exempt_marked': False,
        'trial_only': False,
        'subjective': False,
    })

    # === 费曼自述题 ===
    questions.append({
        'id': f'q_{node_id}_feyn',
        'section_id': sec_id,
        'node_id': node_id,
        'type': 'error_diagnosis',
        'stem': f'（论述/费曼）请用自己的话阐述「{name}」的含义，并指出一种常见的错误理解。',
        'options': [],
        'answer': '',
        'explanation': f'参考要点：「{name}」的核心含义是{defn}。常见错误理解：将核心关系颠倒或忽略关键限定，导致对「{name}」的认识偏离其本义。',
        'difficulty': 0.70,
        'source_chunk_id': chunk,
        'authority_status': 'reviewed',
        'exempt_marked': False,
        'trial_only': False,
        'subjective': True,
    })

    return questions


def difficulty_band(difficulty: float, subjective: bool) -> str:
    if subjective:
        return 'feynman'
    if difficulty < EASY_MAX:
        return 'easy'
    elif difficulty < MED_MAX:
        return 'medium'
    return 'hard'


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
        band = difficulty_band(it.get('difficulty', 0.5), it.get('subjective', False))
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

        if not needed:
            continue

        # 生成该知识点的所有题目，然后只取需要的
        all_qs = gen_questions(node, sec)
        for q in all_qs:
            band = difficulty_band(q['difficulty'], q['subjective'])
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
