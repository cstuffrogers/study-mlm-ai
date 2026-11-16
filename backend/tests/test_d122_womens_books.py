"""D122 门禁：妇女运动文献 13 篇（1920—1933）

收录口径（本批最关键的约束，写死在这里）：

  * **只收妇女解放与劳动解放这条马列主义主线上的文献**，且必须能溯源到正式
    中文出版物或原刊。向警予 8 篇（原刊出处可核）＋党的三大、四大两份妇女
    决议案（中央档案馆 1981 年汇编本）＋蔡特金 3 篇（第二国际大会文件、库钦斯基
    德文版中译、宋城译本）。
  * **柯伦泰整批不收**：她名下的中译没有一份能溯源到正式中文出版物，全部是当代
    志愿者从俄文、英文新译；且《工人反对派》《给有翼的爱若斯让路吧》属被列宁
    批判的路线与思潮，与「符合马列毛思想」的收录要求直接冲突。
  * **蔡特金《罗莎·卢森堡对俄国革命的态度》不收**：为卢森堡对俄国革命的批评作
    辩护，涉重大政治争议。
  * 现代学者的二手纪念文（McGrath 2020、Riddell 2013 等）一律不入。
  * 全文照录、不设 TRIM、不改一字；原刊出处行、译注、俄文版说明一律保留。

分档：向警予 8 篇「经典原著／1.0」（党史正面人物，1928 年遇害，妇女解放与劳动
解放主线）；三大、四大决议 2 篇「正统／0.9」（党的文献）；蔡特金 3 篇
「正统／0.9」（外国理论来源，不占经典原著档）。
"""
import re
from pathlib import Path

import pytest

from content.book_chunks import BOOKS, all_book_chunks
from content.reading_extensions import extensions_for
from core.rag.concept_dict import ConceptDictionary

TEXTS = Path(__file__).resolve().parents[2] / "sources" / "texts"

# 文件 → (work, 分档, authority_score, 篇首识别行, 篇末溯源行)
WORKS = {
    "1-女子解放与改造的商榷.txt": (
        "女子解放与改造的商榷", "经典原著", 1.0,
        "向警予",
        "载《少年中国》1920年第二卷第二期",
    ),
    "1-留法女生对海外大学之要求.txt": (
        "留法女生对海外大学之要求", "经典原著", 1.0,
        "向警予",
        "（载湖南《大公报》1921年7月20日—26日）",
    ),
    "1-中国知识妇女的三派.txt": (
        "中国知识妇女的三派", "经典原著", 1.0,
        "向警予",
        "载《妇女周报》第十五号",
    ),
    "1-对于万国女权同盟大会的感想.txt": (
        "对于万国女权同盟大会的感想", "经典原著", 1.0,
        "向警予",
        "载《前锋》第二期",
    ),
    "1-中国妇女运动杂评.txt": (
        "中国妇女运动杂评（从六月到八月）", "经典原著", 1.0,
        "向警予",
        "载《前锋》第二期",
    ),
    "1-今后中国妇女的国民革命运动.txt": (
        "今后中国妇女的国民革命运动", "经典原著", 1.0,
        "向警予",
        "载《妇女周报》第十卷第一号",
    ),
    "1-丝厂女工团结起来.txt": (
        "丝厂女工团结起来", "经典原著", 1.0,
        "向警予",
        "载《妇女周报》第十四号",
    ),
    "1-妇女运动的基础.txt": (
        "妇女运动的基础", "经典原著", 1.0,
        "妇女中生活最痛苦的，只有下层妇女——工厂的女工",
        "载《妇女周报》第八十一号",
    ),
    "1-中共三大关于妇女运动的决议案.txt": (
        "中国共产党第三次全国代表大会关于妇女运动的决议案", "正统", 0.9,
        "中国共产党第三次全国代表大会关于妇女运动的决议案",
        "按一九二三年七月中国共产党中央执行委员会印行的",
    ),
    "1-中共四大对于妇女运动之议决案.txt": (
        "中国共产党第四次全国代表大会对于妇女运动之议决案", "正统", 0.9,
        "中国共产党第四次全国代表大会对于妇女运动之议决案",
        "按一九二五年二月中国共产党中央执行委员会印行的",
    ),
    "1-关于妇女劳动问题.txt": (
        "关于妇女劳动问题", "正统", 0.9,
        "克拉拉·蔡特金",
        "节选自《第二国际第一次代表大会文件》",
    ),
    "1-无产阶级妇女们准备起来.txt": (
        "无产阶级妇女们，准备起来！", "正统", 0.9,
        "原文原载于1914年8月5日《平等》杂志第23期",
        "中译文译自库钦斯基《第一次世界大战与德国社会民主党》，1957年德文版",
    ),
    "1-列宁给全世界妇女的遗教.txt": (
        "列宁给全世界妇女的遗教", "正统", 0.9,
        "译者：宋城",
        "[1] 《列宁全集》，第三十卷，1957年人民出版社版",
    ),
}

# 逐篇的关键句：必须逐字出现在正文里（防正文被截断、改写、替换）
KEY_LINES = {
    "1-女子解放与改造的商榷.txt": [
        "女子解放的问题，是新思潮中一个重要的问题，是社会改造的一个根本问题",
        "财产私有制这位先生是个人快乐主义孕育出来的，他是万恶之源",
        "家庭制度不完全打破，女子是终不会解放的",
        "苏维埃的政治不产生于英美德法，而独产生于极端专制极端黑暗的俄罗斯",
    ],
    "1-留法女生对海外大学之要求.txt": [
        "是故女子今日实力之不足实社会之制度与教育有以致之，而非女子本身之过也",
        "夫平等平权，实公理所在，不可磨灭",
        "宜扫除一切贵族式男系式的大学之恶习",
        "胡慕昭 向警予 吴孟班 魏壁 熊淑彬 李自新 劳启荣 蔡畅",
    ],
    "1-中国知识妇女的三派.txt": [
        "我国今日知识妇女最普遍的趋向，约可分为三派",
        "人生价值的大小是以人们对于社会贡献的大小而判定的",
        "小家庭派，浪漫派完全建筑在个人的快乐主义之上",
        "以上三派之所以形成，都是伊们各别环境的产物",
    ],
    "1-对于万国女权同盟大会的感想.txt": [
        "一面高唱和平，一面准备世界第二次大战，这是近代资本帝国主义者的常态",
        "我们只有亲密地结合全世界被压迫群众——妇女，弱小民族，劳动阶级成一坚实伟大的三角同盟",
        "参加万国女权同盟会的中国姊妹们，尤应努力完成此一段工作，以为世界各国姊妹倡",
    ],
    "1-中国妇女运动杂评.txt": [
        "女权运动是妇女的人权运动，也是妇女的民权运动",
        "我们妇女团体一向所做的多是法的运动，而所缺乏的正是“社会的基础”",
        "娼妓制度所以存在的原因虽然复杂，而经济一项实为主因",
        "四川女权同盟会的宣言是中国妇女觉悟的声音",
    ],
    "1-今后中国妇女的国民革命运动.txt": [
        "而且妇女运动也绝对不能有超政治经济的存在",
        "现在全世界处奴隶地位的两性人口总在人类全数的五分之四以上",
        "所以我说劳动解放与妇女解放是天造地设的伴侣",
        "为国民革命运动的前驱，以开女权之路",
    ],
    "1-丝厂女工团结起来.txt": [
        "要免除厂主的虐待和剥削，也只有劳工本身团结的力量",
        "法律也是专帮富人欺压穷人的",
        "我正告你们，甚么社会官厅都靠不住，靠得住的，还是：你们本身的团结",
        "呻吟于资本家铁鞭之下的姊妹们，团结起来呵！",
    ],
    "1-妇女运动的基础.txt": [
        "妇女中生活最痛苦的，只有下层妇女——工厂的女工",
        "伊们天然成为妇女解放的前卫",
        "这种群众，方是我们妇女运动真正的基础",
    ],
    "1-中共三大关于妇女运动的决议案.txt": [
        "此种冲突之来源大致由宗法社会轻蔑妇女之习惯与成见，还保留于男工之中",
        "此实为工人阶级分裂之危机",
        "不仅要号召男女工亲密团结，而且要扫荡男工轻侮女工之习惯与成见",
        "应创办一种出版物，以指导并批评日常的妇女生活及妇女运动",
    ],
    "1-中共四大对于妇女运动之议决案.txt": [
        "本党妇女运动应以工农妇女为骨干",
        "故妇女解放与劳动解放实有极大关联",
        "我们的责任是领导一般妇女运动为民族解放运动中的一要素",
        "打破奴隶女性的礼教",
    ],
    "1-关于妇女劳动问题.txt": [
        "妇女解放问题，也就是说，归根到底妇女劳动问题是一个经济问题",
        "社会的奴役或自由是建立在经济附属或经济独立之上的",
        "妇女解放问题是新时代的产儿，是机器生育了它",
        "从男人的奴隶变成了雇主的奴隶",
        "妇女的解放同全人类的解放一样，最终必将是劳动从资本中解放出来的事业",
    ],
    "1-无产阶级妇女们准备起来.txt": [
        "欧洲各国人民所担心害怕的事，已经化为现实了",
        "在大街上，工人阶级群众的强有力的和平呼声，必然压倒杀气腾腾的护国分子的叫嚣",
        "在战争中利用一切可以利用的武器来反对战争",
        "无产阶级妇女们，准备起来！",
    ],
    "1-列宁给全世界妇女的遗教.txt": [
        "劳动妇女的解放应当是劳动妇女自己的事情",
        "妇女要不是完全得到解放和平等，她们之中的大多数就得继续受阶级压迫和日常生活上的不平等这双重枷锁的压迫和奴役",
        "1917年3月8日，彼得格勒在“面包、和平和自由！”的口号下在巷战中举行了忠实于自己的革命本质的国际妇女节",
        "不是资本主义（即把世界引导到崩溃的经济和社会制度），就是共产主义",
    ],
}

# 延伸阅读挂接：章节 → (local_work, kind)
EXPECTED = {
    "sec_C_06": {
        "女子解放与改造的商榷",
        "对于万国女权同盟大会的感想",
        "中国妇女运动杂评（从六月到八月）",
        "今后中国妇女的国民革命运动",
        "妇女运动的基础",
        "中国共产党第三次全国代表大会关于妇女运动的决议案",
        "中国共产党第四次全国代表大会对于妇女运动之议决案",
        "关于妇女劳动问题",
        "列宁给全世界妇女的遗教",
    },
    "sec_B_03": {"中国知识妇女的三派"},
    "sec_B_09": {"丝厂女工团结起来", "留法女生对海外大学之要求"},
    "sec_B_06": {"无产阶级妇女们，准备起来！"},
}

# 排除项：这些作者／书名一份也不许出现在本库正文清单里
EXCLUDED_AUTHORS = ["柯伦泰", "McGrath", "Riddell", "亚历山德拉"]
EXCLUDED_WORKS = [
    "卢森堡", "工人反对派", "爱若斯", "组织起劳动女性", "工人们的国际节日",
    "打倒战争", "关于蔡特金", "革命家克拉拉·蔡特金",
]

QUOTE_ANCHOR = re.compile(r"[〔［\[][0-9]+[〕］\]]")
DISPLAY_JARGON = re.compile(r"D\d{2,3}|TRIM|sec_[A-C]_\d\d|OCR|PDF|HTML|入库|镜像|分片")


def _paths():
    return {f: TEXTS / f for f in WORKS}


@pytest.mark.parametrize("fname", sorted(WORKS))
def test_d122_text_present_and_traceable(fname):
    path = TEXTS / fname
    assert path.exists(), f"缺正文文件：{fname}"
    t = path.read_text(encoding="utf-8")
    work, tag, score, head, tail = WORKS[fname]
    assert head in t.split("\n\n")[0] + t[:400] or head in t[:400], \
        f"{fname}: 篇首识别行缺失「{head}」"
    assert tail in t, f"{fname}: 篇末溯源行缺失「{tail}」"
    # 全文照录：13 篇都有实体内容，不允许只剩导读
    assert len(t) > 700, f"{fname}: 正文过短（{len(t)} 字符），疑似只剩导读"
    assert "\n\n\n\n" not in t, f"{fname}: 出现连续空行，疑似拼接残留"


@pytest.mark.parametrize("fname", sorted(WORKS))
def test_d122_key_lines_verbatim(fname):
    t = (TEXTS / fname).read_text(encoding="utf-8")
    for line in KEY_LINES[fname]:
        assert line in t, f"{fname}: 关键句不逐字匹配「{line}」"


@pytest.mark.parametrize("fname", sorted(WORKS))
def test_d122_book_meta(fname):
    work, tag, score, _head, _tail = WORKS[fname]
    hits = [b for b in BOOKS if b["file"] == fname]
    assert len(hits) == 1, f"{fname}: BOOKS 里应恰好登记一次，实际 {len(hits)}"
    b = hits[0]
    assert b["work"] == work, f"{fname}: work 应为「{work}」，实际「{b['work']}」"
    assert b["orthodoxy_tag"] == tag, f"{fname}: 分档应为「{tag}」，实际「{b['orthodoxy_tag']}」"
    assert b["authority_score"] == score, f"{fname}: 权重应为 {score}，实际 {b['authority_score']}"


def test_d122_chunks_indexed():
    chunks = all_book_chunks()
    names = {b["file"] for b in BOOKS}
    assert set(WORKS) <= names
    for fname, (work, *_rest) in WORKS.items():
        mine = [c for c in chunks if c.get("source") == work]
        assert mine, f"{fname}: 分片未进索引进（work={work}）"
        assert all(c["text"].strip() for c in mine), f"{fname}: 存在空分片"


def test_d122_extensions_wired():
    for sid, works in EXPECTED.items():
        items = extensions_for(sid)
        local = {i.get("local_work") for i in items if i.get("local_work")}
        missing = works - local
        assert not missing, f"{sid}: 缺延伸阅读挂接 {sorted(missing)}"
        for i in items:
            if i.get("local_work") in works:
                assert i["kind"] in {"classic", "historical"}, \
                    f"{sid}/《{i['title']}》: kind 非法「{i['kind']}」"
                assert i.get("points"), f"{sid}/《{i['title']}》: 缺要点"
                assert "一字未改" in i.get("caution", ""), \
                    f"{sid}/《{i['title']}》: caution 须写明「一字未改」"
                m = DISPLAY_JARGON.search(i.get("caution", ""))
                assert not m, f"{sid}/《{i['title']}》: caution 出现开发期术语「{m.group(0)}」"


def test_d122_import_blacklist_respected():
    """柯伦泰、卢森堡批评、二手纪念文与无底本中译，一份也不许进来。"""
    for b in BOOKS:
        for name in EXCLUDED_AUTHORS:
            assert name not in (b.get("author") or ""), \
                f"作者「{name}」不应出现在本库：{b['file']}"
        for word in EXCLUDED_WORKS:
            assert word not in (b.get("work") or ""), \
                f"《{b['work']}》属排除项（{word}），不应收录"
    # 正文侧再查一遍：排除项的文章标题不得出现在 sources/texts 的文件名里
    files = {p.name for p in TEXTS.glob("*.txt")}
    for word in ("卢森堡", "反对派", "爱若斯", "组织起劳动女性", "打倒战争"):
        bad = sorted(f for f in files if word in f)
        assert not bad, f"排除项文章混进了正文目录：{bad}"


def test_d122_concept_family():
    d = ConceptDictionary()
    assert d.extract_concepts("劳动妇女") == ["劳动妇女"]
    # 「女工」「女权运动」只做图召回 mention，不往概念层拉
    assert d.extract_concepts("女工") == []
    assert d.extract_concepts("女权运动") == []
    chunks = all_book_chunks()
    women = [c for c in chunks if "劳动妇女" in c.get("concept_mentions", [])]
    assert women, "分片侧未抽到「劳动妇女」mention"


def test_d122_quotes_verbatim():
    """延伸阅读里所有「」引文必须逐字出现在正文（只认原文逐字句）。"""
    checked = 0
    miss = []
    for sid in EXPECTED:
        for item in extensions_for(sid):
            if item.get("local_work") not in {w for s in EXPECTED.values() for w in s}:
                continue
            text = (TEXTS / next(f for f, v in WORKS.items() if v[0] == item["local_work"])).read_text(
                encoding="utf-8")
            flat = re.sub(r"\s+", "", text)
            for quote in re.findall(r"「([^」]{6,})」", " ".join(item.get("points", []))
                                    + " " + item.get("intro", "")):
                q = re.sub(r"\s+", "", QUOTE_ANCHOR.sub("", quote))
                if q.startswith("……") or q.endswith("……"):
                    q = q.strip("…")
                checked += 1
                if q and q not in flat:
                    miss.append(f"{sid}/《{item['title']}》: 「{quote[:40]}」")
    assert checked >= 60, f"引文核对样本过少：{checked}"
    assert not miss, "引文与正文不逐字一致：\n" + "\n".join(miss)


def test_d122_chapter_count_unchanged():
    from content.routes import SECTIONS
    assert len(SECTIONS) == 32

# 依赖 sources/texts/ 原著正文；无正文时由 conftest.py 自动跳过。
pytestmark = pytest.mark.needs_texts
