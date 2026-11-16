"""D123 门禁：恽代英文献 22 篇（1925—1930）

收录口径（写死在这里）：

  * **只收理论著作、讲演、工人运动与苏维埃史料**，且必须能溯源到原刊
    （《中国青年》《黄埔潮》《革命生活》《少年先锋》《红旗》《少年先锋》）
    或权威单行本（广州国光书店版《中国民族革命运动史》、国民革命军第一军
    第三师政治部版《世界革命与中国革命》、《恽代英全集》、《革命烈士诗抄》）。
  * **《红旗》署「稚宜」的新闻体短评 6 篇不收**：1929—1930 年的千字时评，
    属宣传鼓动文字，不足以为理论文献（同 D122 不收向警予「振宇」短评的口径）。
    注意《中东路问题与一般流行的错误意见》也署「稚宜」，但它两期连载、
    通篇做帝国主义关系的分析，是理论长文，故收；引用时须看署名与文体差别。
  * **私人文字与散文 7 篇不收**：致柳亚子书信、《广东的青年劳动军人》、
    《主义》、《为自己的利益而奋斗》、《学生的背水阵》、《告愤激的国民》、
    《辟三种洋奴的论调》、《革命势力与反革命势力》、《国民党中央及各省区
    代表联席会议之经过》。
  * 长篇按章节标题行节选：《中国民族革命运动史》只留第五至七讲，
    《答〈醒狮周报〉三十二期的质难》只留第一、二节；其余 20 篇全文照录。

分档：理论著作与讲演 12 篇「经典原著／1.0」；工运与苏维埃史料 10 篇
「正统／0.9」（史料与总结，不占经典原著档）。
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
    "1-中国民族革命运动史节选.txt": (
        "中国民族革命运动史（节选）", "经典原著", 1.0,
        "本文是恽代英于一九二六年在广州所作的讲演",
        "据广州国光书店1927年3月初版单行本排印",
    ),
    "1-世界革命与中国革命.txt": (
        "世界革命与中国革命（讲演大纲）", "经典原著", 1.0,
        "一 革命的意义",
        "据国民革命军第一军第三师政治部出版单行本排印",
    ),
    "1-革命之障碍.txt": (
        "革命之障碍", "经典原著", 1.0,
        "这是恽代英在黄埔军校的讲演。",
        "载《黄埔潮》半周刊第46—52期",
    ),
    "1-国民革命与阶级斗争.txt": (
        "国民革命与阶级斗争", "经典原著", 1.0,
        "在讲国民革命与阶级斗争这个题之前",
        "载《革命生活》第17期",
    ),
    "1-与李琯卿君论新国家主义.txt": (
        "与李琯卿君论新国家主义", "经典原著", 1.0,
        "中国有无产阶级专政的可能性么？",
        "载《中国青年》第73期",
    ),
    "1-答醒狮周报三十二期的质难节选.txt": (
        "答《醒狮周报》三十二期的质难（节选）", "经典原著", 1.0,
        "十分对不住读者与《醒狮周报》诸君",
        "署名：代英",
    ),
    "1-读孙文主义之哲学的基础.txt": (
        "读《孙文主义之哲学的基础》", "经典原著", 1.0,
        "此书系戴季陶先生所著",
        "载《中国青年》第87期",
    ),
    "1-民族革命中的共产党.txt": (
        "民族革命中的共产党", "经典原著", 1.0,
        "人们对于一种秘密的革命党",
        "载《中国青年》第89期",
    ),
    "1-为什么产业无产阶级最富于革命性.txt": (
        "为什么产业无产阶级最富于革命性？", "经典原著", 1.0,
        "我从前听见人家说：产业无产阶级是比任何阶级都富于革命性的",
        "载《黄埔潮》半周刊第34期",
    ),
    "1-怎样做一个共产党员.txt": (
        "怎样做一个共产党员？", "经典原著", 1.0,
        "广东青年很少怕共产党的",
        "载《少年先锋》第1卷第4期",
    ),
    "1-什么是机会主义.txt": (
        "什么是机会主义？", "经典原著", 1.0,
        "在革命潮流高涨的时候",
        "载《中国青年》第151期",
    ),
    "1-我们的战略.txt": (
        "我们的战略", "经典原著", 1.0,
        "让那些妥协派去鼓吹和平了结的论调",
        "载《中国青年》第88期",
    ),
    "1-中国劳动阶级斗争第一幕.txt": (
        "中国劳动阶级斗争第一幕", "正统", 0.9,
        "“二七”是中国空前未有的劳动阶级的斗争",
        "署名：F.M.",
    ),
    "1-上海日纱厂罢工中所得的教训.txt": (
        "上海日纱厂罢工中所得的教训", "正统", 0.9,
        "四万余中国工人，以前没有工会的组织",
        "载《中国青年》第70期",
    ),
    "1-五卅运动与阶级争斗.txt": (
        "五卅运动与阶级争斗", "正统", 0.9,
        "你若仔细观察五卅以来各阶级的态度",
        "码头捐系于一八九八年由上海公共租界工部局",
    ),
    "1-农民中的宣传组织工作.txt": (
        "农民中的宣传组织工作", "正统", 0.9,
        "又要到寒假的期间了！",
        "载《中国青年》第106期",
    ),
    "1-苏维埃的建立.txt": (
        "苏维埃的建立", "正统", 0.9,
        "恽代英 李立三",
        "城市的总工会，有代表会议之组织",
    ),
    "1-广州暴动与工会.txt": (
        "广州暴动与工会", "正统", 0.9,
        "恽代英在广州苏维埃政府中任秘书长",
        "载广东《红旗》，1928年初出版",
    ),
    "1-闽西苏维埃的过去与将来.txt": (
        "闽西苏维埃的过去与将来", "正统", 0.9,
        "闽西八十万工农群众从斗争中建立的苏维埃政权",
        "载《红旗》第87期",
    ),
    "1-请看闽西农民造反的成绩.txt": (
        "请看闽西农民造反的成绩——福建通信", "正统", 0.9,
        "——福建通信",
        "现在这两种办法都在试验中",
    ),
    "1-中东路问题与一般流行的错误意见.txt": (
        "中东路问题与一般流行的错误意见", "正统", 0.9,
        "自中东路问题发生，反动的国民党",
        "载《红旗》第35、37期",
    ),
    "1-在狱中给党组织的信.txt": (
        "在狱中给党组织的信（附《狱中诗》）", "正统", 0.9,
        "他在看守所化名王作林",
        "中国青年出版社出版",
    ),
}

KEY_LINES = {
    "1-中国民族革命运动史节选.txt": [
        "这无异要帝国主义来打帝国主义，却未免是笑话",
        "殊不知因此而吓走瑞澂",
    ],
    "1-世界革命与中国革命.txt": [
        "革命是被压迫民众不能用寻常手段解放自己时所取的非常手段",
        "他们的地位等于是帝国主义的经手人",
    ],
    "1-革命之障碍.txt": [
        "（一）主观方面是革命党员自己的缺点；（二）客观方面是社会方面的妨害",
        "但他们不敢说巡捕房任意杀人更是过激了",
    ],
    "1-国民革命与阶级斗争.txt": [
        "实则阶级斗争是几千年来的事实，马克思不过将他说明罢了",
        "这就是说革命并不是少数人可能完成的",
    ],
    "1-与李琯卿君论新国家主义.txt": [
        "仍旧与“醒狮”诸君的“旧国家主义”不免有同样的错误",
        "我们常常用各种方法引导全国各阶级从事于国民革命",
    ],
    "1-答醒狮周报三十二期的质难节选.txt": [
        "我们心目中的政府，是为保障无产阶级平民的利益而存在的",
        "国家主义者总想拿国家观念来压倒阶级观念",
    ],
    "1-读孙文主义之哲学的基础.txt": [
        "革命的能力，发源于主义的信仰与群众的党的组织",
        "我颇觉他不能自圆其说",
    ],
    "1-民族革命中的共产党.txt": [
        "只有大空想家在“现在”便居然要实现共产主义",
        "使他们好为缙绅之士“抬轿子”、凑票数",
    ],
    "1-为什么产业无产阶级最富于革命性.txt": [
        "但他们确实是比任何阶级都富于革命性",
        "这种精神有甚么地方、那一种的人可以比得上他们呢？",
    ],
    "1-怎样做一个共产党员.txt": [
        "凡相信离开了群众的力量，仍旧可以解放甚么人的，一定不配做一个共产党员",
        "而且自己站在前线上面领导他们奋斗！",
    ],
    "1-什么是机会主义.txt": [
        "在革命运动风头顺利的时候，革命党必须谨防自身的腐化",
        "靠机运或某一个或某一部分人完成革命的心理",
    ],
    "1-我们的战略.txt": [
        "不是要被宣传者浪漫的暴动，更不是要他们悲愤而自杀",
        "宣传组织学生、工人、农民、小商人乃至于兵士",
    ],
    "1-中国劳动阶级斗争第一幕.txt": [
        "谁曾对于军阀的压迫有过这样大而有力的反抗运动呢？",
        "这便是京汉铁路工会运动的开始",
    ],
    "1-上海日纱厂罢工中所得的教训.txt": [
        "产业工人确实是革命的主要力量，只有他能做民族革命的主要军队",
        "是最有效力的帮助他们的法子",
    ],
    "1-五卅运动与阶级争斗.txt": [
        "还有甚么脸面要求工人对他们停止阶级斗争呢？",
        "对于阶级斗争我们只应问工人的要求是否正当",
    ],
    "1-农民中的宣传组织工作.txt": [
        "第一是政治方面，第二是经济方面，第三是文化方面",
        "他们是很愿意听的",
    ],
    "1-苏维埃的建立.txt": [
        "苏维埃政府是工农兵贫民代表会议政府",
        "决不是所谓全民的民主政治",
    ],
    "1-广州暴动与工会.txt": [
        "又没有正式布告将权力交给各工会去做，这实在是一个错误",
        "而工人仍旧没有钱用，没有饭吃",
    ],
    "1-闽西苏维埃的过去与将来.txt": [
        "一切权力都属于苏维埃",
        "只站在很少的中农以至富农利益的观点上反对平分土地，是不正确的",
    ],
    "1-请看闽西农民造反的成绩.txt": [
        "他是要闹一个天翻地覆，把全世界翻转过来",
        "坐地收捐、收税、派款、派粮的国民党官府",
    ],
    "1-中东路问题与一般流行的错误意见.txt": [
        "第一种意见，过分夸张了帝国主义之间的冲突",
        "他极力挑拨战争，而且积极进兵满洲",
    ],
    "1-在狱中给党组织的信.txt": [
        "敌人未能辨出他的确实身份",
        "买通看守送出给党组织",
    ],
}

# 延伸阅读挂接：章节 → 篇名集合
EXPECTED = {
    "sec_C_02": {"中国民族革命运动史（节选）", "闽西苏维埃的过去与将来"},
    "sec_B_06": {"世界革命与中国革命（讲演大纲）", "中东路问题与一般流行的错误意见"},
    "sec_B_01": {
        "革命之障碍", "与李琯卿君论新国家主义",
        "答《醒狮周报》三十二期的质难（节选）", "民族革命中的共产党",
        "怎样做一个共产党员？", "在狱中给党组织的信（附《狱中诗》）",
    },
    "sec_B_03": {
        "国民革命与阶级斗争", "为什么产业无产阶级最富于革命性？",
        "中国劳动阶级斗争第一幕", "五卅运动与阶级争斗",
    },
    "sec_A_14": {"读《孙文主义之哲学的基础》"},
    "sec_B_08": {"什么是机会主义？", "我们的战略"},
    "sec_B_09": {
        "上海日纱厂罢工中所得的教训", "农民中的宣传组织工作",
        "请看闽西农民造反的成绩——福建通信",
    },
    "sec_B_02": {"苏维埃的建立", "广州暴动与工会"},
}

# 排除项：这些篇目／作者一份也不许进来
EXCLUDED_FILENAME_WORDS = [
    "柳亚子", "青年劳动军人", "背水阵", "愤激的国民", "三种洋奴",
    "革命势力与反革命势力", "联席会议", "为自己的利益而奋斗", "学生的背水阵",
]
EXCLUDED_WORK_WORDS = [
    "柳亚子", "青年劳动军人", "背水阵", "愤激的国民", "三种洋奴",
    "革命势力与反革命势力", "联席会议", "为自己的利益而奋斗",
]
EXCLUDED_AUTHORS = ["柯伦泰", "陈碧兰", "郑超麟", "彭述之", "王凡西", "张国焘"]

QUOTE_ANCHOR = re.compile(r"[〔［\[][0-9]+[〕］\]]")
DISPLAY_JARGON = re.compile(r"D\d{2,3}|TRIM|sec_[A-C]_\d\d|OCR|PDF|HTML|入库|镜像|分片|\.txt|\.md")


@pytest.mark.parametrize("fname", sorted(WORKS))
def test_d123_text_present_and_traceable(fname):
    path = TEXTS / fname
    assert path.exists(), f"缺正文文件：{fname}"
    t = path.read_text(encoding="utf-8")
    _work, _tag, _score, head, tail = WORKS[fname]
    assert head in t[:900], f"{fname}: 篇首识别行缺失「{head}」"
    assert tail in t, f"{fname}: 篇末溯源行缺失「{tail}」"
    assert len(t) > 500, f"{fname}: 正文过短（{len(t)} 字符），疑似只剩导读"
    assert "\n\n\n\n" not in t, f"{fname}: 出现连续空行，疑似拼接残留"


@pytest.mark.parametrize("fname", sorted(WORKS))
def test_d123_key_lines_verbatim(fname):
    t = (TEXTS / fname).read_text(encoding="utf-8")
    for line in KEY_LINES[fname]:
        assert line in t, f"{fname}: 关键句不逐字匹配「{line}」"


@pytest.mark.parametrize("fname", sorted(WORKS))
def test_d123_book_meta(fname):
    work, tag, score, _head, _tail = WORKS[fname]
    hits = [b for b in BOOKS if b["file"] == fname]
    assert len(hits) == 1, f"{fname}: BOOKS 里应恰好登记一次，实际 {len(hits)}"
    b = hits[0]
    assert b["work"] == work, f"{fname}: work 应为「{work}」，实际「{b['work']}」"
    assert b["orthodoxy_tag"] == tag, f"{fname}: 分档应为「{tag}」，实际「{b['orthodoxy_tag']}」"
    assert b["authority_score"] == score, f"{fname}: 权重应为 {score}，实际 {b['authority_score']}"
    assert "恽代英" in (b.get("author") or ""), f"{fname}: 作者应是恽代英"


def test_d123_book_count_and_prefix():
    mine = [b for b in BOOKS if "恽代英" in (b.get("author") or "")]
    assert len(mine) == 22, f"恽代英条目应为 22 条，实际 {len(mine)}"
    prefixes = [b["id_prefix"] for b in mine]
    assert len(set(prefixes)) == 22, f"id_prefix 重复：{sorted(prefixes)}"
    slugs = [b["slug"] for b in mine]
    assert len(set(slugs)) == 22, f"slug 重复：{sorted(slugs)}"


def test_d123_chunks_indexed():
    chunks = all_book_chunks()
    for fname, (work, *_rest) in WORKS.items():
        mine = [c for c in chunks if c.get("source") == work]
        assert mine, f"{fname}: 分片未进索引进（work={work}）"
        assert all(c["text"].strip() for c in mine), f"{fname}: 存在空分片"


def test_d123_extensions_wired():
    all_works = {w for s in EXPECTED.values() for w in s}
    for sid, works in EXPECTED.items():
        items = extensions_for(sid)
        local = {i.get("local_work") for i in items if i.get("local_work")}
        missing = works - local
        assert not missing, f"{sid}: 缺延伸阅读挂接 {sorted(missing)}"
        for i in items:
            if i.get("local_work") in all_works:
                assert i["kind"] in {"classic", "historical"}, \
                    f"{sid}/《{i['title']}》: kind 非法「{i['kind']}」"
                assert i.get("points"), f"{sid}/《{i['title']}》: 缺要点"
                assert "一字未改" in i.get("caution", ""), \
                    f"{sid}/《{i['title']}》: caution 须写明「一字未改」"
                m = DISPLAY_JARGON.search(i.get("caution", ""))
                assert not m, f"{sid}/《{i['title']}》: caution 出现开发期术语「{m.group(0)}」"
    # 22 篇全部挂上了
    wired = {i.get("local_work") for sid in EXPECTED for i in extensions_for(sid)}
    assert all_works <= wired, f"未挂接：{sorted(all_works - wired)}"


def test_d123_excluded_works_absent():
    """稚宜新闻体短评、私人文字、散文与会议报告，一份也不许进来。"""
    for b in BOOKS:
        for name in EXCLUDED_AUTHORS:
            assert name not in (b.get("author") or ""), f"作者「{name}」不应出现：{b['file']}"
        for word in EXCLUDED_WORK_WORDS:
            assert word not in (b.get("work") or ""), f"《{b['work']}》属排除项（{word}）"
    files = {p.name for p in TEXTS.glob("*.txt")}
    for word in EXCLUDED_FILENAME_WORDS:
        bad = sorted(f for f in files if word in f)
        assert not bad, f"排除项文章混进了正文目录：{bad}"


def test_d123_selection_boundaries():
    """节选边界必须落在讲次／小节标题行，且被裁的讲次正文不在文件里。"""
    t = (TEXTS / "1-中国民族革命运动史节选.txt").read_text(encoding="utf-8")
    # 七讲目录保留
    for title in ("第一讲 由反清复明运动至鸦片战争", "第四讲 义和团与八国联军",
                  "第五讲 辛亥革命运动", "第七讲 五卅运动"):
        assert title in t, f"讲次目录缺「{title}」"
    # 正文只留第五至七讲：第五讲标题出现两次（目录 + 正文），第六、七讲同理
    assert t.count("第五讲 辛亥革命运动") == 2
    assert t.count("第六讲 五四运动前后的国民党") == 2
    assert t.count("第七讲 五卅运动") == 2
    # 被裁正文里的标志性内容不得残留（第一讲开篇讲反清复明）
    assert "反清复明" in t  # 目录行
    assert t.count("反清复明") <= 2, "第一讲正文似未裁净"

    s = (TEXTS / "1-答醒狮周报三十二期的质难节选.txt").read_text(encoding="utf-8")
    assert "一 民族解放运动决不是甚么“国家主义”" in s
    assert "二 谁能担保革命者不“出卖”救国事业" in s
    assert "三 联俄便是倚赖外力么" not in s, "第三节未裁净"
    assert "四 答余家菊君" not in s, "第四节未裁净"


def test_d123_concept_family():
    d = ConceptDictionary()
    assert d.extract_concepts("五卅运动") == ["五卅运动"]
    assert d.extract_concepts("帝国主义") == ["帝国主义"]
    assert d.extract_concepts("国民革命") == ["国民革命"]
    assert d.extract_concepts("苏维埃") == ["苏维埃"]
    chunks = all_book_chunks()
    mentions = {t for c in chunks if c.get("book_author", "").startswith("恽代英")
                for t in c.get("concept_mentions", [])}
    for term in ("苏维埃", "帝国主义", "国民革命", "军阀"):
        assert term in mentions, f"恽代英分片侧未抽到「{term}」mention"


def test_d123_quotes_verbatim():
    """延伸阅读里所有「」引文必须逐字出现在正文（只认原文逐字句）。"""
    all_works = {w for s in EXPECTED.values() for w in s}
    checked = 0
    miss = []
    for sid in EXPECTED:
        for item in extensions_for(sid):
            if item.get("local_work") not in all_works:
                continue
            fname = next(f for f, v in WORKS.items() if v[0] == item["local_work"])
            text = (TEXTS / fname).read_text(encoding="utf-8")
            flat = re.sub(r"\s+", "", text)
            blob = " ".join(item.get("points", [])) + " " + item.get("intro", "")
            for quote in re.findall(r"「([^」]{6,})」", blob):
                q = re.sub(r"\s+", "", QUOTE_ANCHOR.sub("", quote))
                if q.startswith("……") or q.endswith("……"):
                    q = q.strip("…")
                checked += 1
                if q and q not in flat:
                    miss.append(f"{sid}/《{item['title']}》: 「{quote[:40]}」")
    assert checked >= 80, f"引文核对样本过少：{checked}"
    assert not miss, "引文与正文不逐字一致：\n" + "\n".join(miss)


def test_d123_chapter_count_unchanged():
    from content.routes import SECTIONS
    assert len(SECTIONS) == 32


def test_d123_trim_reproducible_from_backup():
    """从裁剪前全文按 TRIM 重切，必须与现库逐字节一致（原文一字未改、可复现）。"""
    import importlib.util

    mp = Path(__file__).resolve().parents[2] / "scripts" / "import_mirror.py"
    spec = importlib.util.spec_from_file_location("import_mirror_d123", mp)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)

    backup = Path(__file__).resolve().parents[2] / "sources" / "_backup_d123_pretrim"
    trimmed = ("1-中国民族革命运动史节选.txt", "1-答醒狮周报三十二期的质难节选.txt")
    assert {p.name for p in backup.glob("*.txt")} == set(trimmed), \
        "备份应且只应含这 2 部裁剪前全文"
    for f in trimmed:
        full = (backup / f).read_text(encoding="utf-8")
        cur = (TEXTS / f).read_text(encoding="utf-8")
        assert len(cur) < len(full), f"{f} 未裁剪"
        assert 0.35 < len(cur) / len(full) < 0.80, f"{f} 裁剪比例异常"
        assert mod.apply_trim(f, full) == cur, f"{f} 裁剪结果不可复现（原文被改写？）"
