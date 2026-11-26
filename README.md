
# 正统马哲深度学习系统 <img width="30" height="30" alt="icon-1024" src="https://github.com/user-attachments/assets/6b927710-56ee-42c2-a5e1-6b5d78c9176d" />

> MVP：学习者阅读《关于费尔巴哈的提纲》11 条，选中文本唤起 AI 五模式会话，防偏离三重机制守门，溯源卡片可查——端到端闭环跑通且不偏离正统立场。

> ## ⚠️ 关于仓库里的原著正文
>
> 本仓库**包含 229 部中文马列原著全文**。它们的**著作权不属于本项目**，
> 而归各作者、译者与出版者所有。
>
> **必须知道的一点：毛泽东 48 部、周恩来 27 部共 75 部作品的著作权
> 至 2026-12-31 尚未届满**；其余 154 部作者已过保护期。
>
> 逐部的作者卒日、保护期届满日期、转录来源、用途限制与权利人异议处理方式，
> 全部写在 **[CONTENT-NOTICE.md](CONTENT-NOTICE.md)**。那是本项目对正文的
> 唯一权威说明，请在使用或再分发前读一遍。
>
> 本项目不主张对正文的任何权利，也无法就正文向任何人授权。
> 收到权利人的有效通知后，承诺七日内移除相关文件。

## 状态

| Phase | 内容 | 状态 |
|-------|------|------|
| 1 | 工程骨架（FastAPI + Flutter + docker-compose） | ✓ |
| 2 | RAG 检索 + 防偏离核心（OrthodoxyGuard + 五层过滤） | ✓（规则召回；pgvector/Neo4j 待 Docker 集成） |
| 3 | Prompt 渲染 + LLM 4 级路由 + 辩难豁免 + 双轨制 + 三重校验 | ✓（Mock LLM 默认；配 key 走真实国产模型） |
| 4 | 内容生产（《提纲》11 条 + 12 概念锚点 + 40 苏格拉底问题） | ✓ |
| 5 | Flutter 前端（三层阅读器 + 五模式会话浮层 + 溯源卡片 + 辩难豁免视觉） | ✓ |
| 6 | 测试门禁（SC-001/003/004/007） | ✓（规则版基线；BERT 待训练） |
| 7 | MVP 交付（docker-compose 一键启动 + README + 验收） | ✓ |
| 8 | 三路线学习闭环（feature 002：选路线→摸底测→学一章→章测掌握度→学情档案→推荐） | ✓（P0 提纲单章闭环；134 后端测试全绿） |
| 9 | 学习科学深化（间隔复习 FSRS-lite / 应用论证题型 / 元认知校准 / 推荐联动复习） | ✓（复习+应用+校准全覆盖，140 后端 + 11 前端测试全绿） |
| 10 | 学习分析 & 交错练习（交错复习队列 / 校准聚合 / 学习健康度看板） | ✓（140 后端 + 13 前端测试全绿） |
| 11 | 动机/挫折调节 + FSRS 参数拟合（分级鼓励/里程碑/easy-win；真实复习日志校准 GAIN/REGRESS） | ✓（145 后端 + 13 前端测试全绿） |
| 12 | 内容覆盖 & 工程收口（题库覆盖 12 知识点 / 章节内交错 / 主导错因回填 / 默认用户统一 / lint 清零） | ✓（149 后端 + 13 前端；flutter analyze 零问题） |
| 13 | 正确性 & 路径可用性（提交幂等/状态持久化 / 答案归一化 / 无题库章完成判定解锁 / 前端联动） | ✓（153 后端 + 13 前端；flutter analyze 零问题；无训练/无蒸馏） |
| 14 | 安全硬化（review 驱动：CORS 白名单 / `.gitignore`+`.env.example` / docker 口令变量化） | ✓（review Score 33→100；cors_check PASS） |
| 15 | 前端美化 & 动效（统一设计系统 / 渐变 hero / 入场动效 / 动画进度环·条形 / 数字滚动 / 光斑背景 / 卡片式全站改造） | ✓（flutter analyze 零问题 + 13 前端测试全绿 + web 构建通过） |
| 16 | 单机安卓版（无后端）：把 backend 的业务逻辑编译成 Dart，数据在构建期导出为 assets | ✓（`唯物马哲精读-单机安卓版.apk` 67MB；65 前端测试全绿；flutter analyze 零问题） |
| 17 | 单机版可选接入在线大模型（功能中心填自己的 API Key，OpenAI 兼容；断网自动回落本机引擎） | ✓（凭证只存本机、GET 只回掩码、输出仍过立场层） |
| 18 | 「多余部分」清理：分片 60 字下限合并 + 选集目录剔除检索索引 | ✓（分片 28,660→23,041、短碎片 20%→0.33%、检索 1400ms→668ms、基准 top1/top3 16/19 不变；692 后端测试全绿） |
| 19 | 合法合规加固（隐私政策/用户协议/免责声明/版权说明 + release 签名 + 立场守门误杀修复 + 后端加固） | ✓（新增「法律与隐私」页与 `NOTICE.md`；release keystore 替换 debug 签名；删「资产阶级」等误判词并加自指批判语境豁免；docker 端口绑回环 + 启动期安全告警；后端 696 全绿、前端 119 全绿） |
| 20 | 首页改「选学习路线」+ 朗读自动停止 + 大模型页收敛（D142） | ✓（首页三张路线卡直达章节地图，头部=功能中心/LLM 配置/学习分析/使用说明；朗读随页面切换与退后台自动停；大模型配置页删掉重复的「本机数据」卡片；前端 288 项测试全绿、`flutter analyze` 零问题） |
| 21 | 单机版「重新摸底测」不再点进去是空的（D142b） | ✓（单机 `LocalQuiz.startDiagnostic/submitDiagnostic` 补齐：按章节顺序每章抽 3 题、上限 12 题，全部带溯源锚点；判分与后端同口径逐章正确率 ≥0.8 判可跳过、起点=第一张未达标/无数据的章；两侧都**只出选项 ≥2 的题**（应用题/主观题没有选项，塞进摸底测就答不了）；结果页显示「阶段N · 标题」不再甩 `sec_A_03`；前端 297 项、后端 781 passed 全绿） |
| 22 | 「打开 GitHub / 下载最新安卓版」点了没反应 + 功能中心「语音包设置」+ 首页品牌标题改「唯物 / 马哲精读」+ 功能中心删「学习路线」（D143） | ✓（根因：`open_url.dart` 的非 Web 分支是**空实现**，原生端根本没有外链能力 → 换 `url_launcher`，manifest 补 Android 11+ 的 `VIEW`+`https` 声明；语音包设置页列本机已装中文语音、4 种风格预设（温柔女声/广播员男声/甜美女声/高亢有力的男声）+ 自然默认，试听与朗读同一条通道；首页标题从一行「马列毛思想AI伴读」改成两行「唯物」/「马哲精读」（白字 + 金色下划线/小方章，`GradientHeader` 新增 `titleWidget`+`titleHeight` 预留高度）；功能中心删掉重复的「学习路线」入口；`build.gradle.kts` 加阿里云 maven 镜像——本机直连 dl.google.com 被重置，APK 构建原本崩在 `mergeReleaseNativeLibs`；多音色再补一层：Web 端四档分别对接后端微软神经语音晓晓/晓伊/云扬/云健（请求带 voice 参数），安卓端按关键词去已装系统语音包里找对应音色、找不到就只做音调语速近似，页面如实写明「App 不内置语音包」；安卓端补上「男声/女声」标签（读引擎 features 的 gender，读不到就标未知，不按名字猜）+ 放宽语音包语言过滤（原来只认 zh|cmn|yue，有的引擎报 und/zh-Hans 会整张表空掉）；前端 341 项全绿） |
| 23 | 对话模式改版 + 选区浮框加「普通对话」+ 正文可复现门禁修复（D155/D156） | ✓（`ChatMode` 改为 `chat/explain/dig/debate/connect`：**删掉应试模式**（本机引擎里它只是「辩难+编题」的拼装）、普通对话成为对话框默认；模式只在**选中原文后浮出的小面板**里选一次，进对话框后固定普通对话、不可切换 —— 任何面板都遍历 `kSelectionModes`（禁 `ChatMode.values`）；只有「追问」把问题抛回给用户，其余模式（含普通对话）把话说完整即停，消除「四种模式结尾都追加追问、读起来一样」的问题；选区面板增至**五枚 chip**（普通对话排第一）：点它就是「带着这句原文直接问」，选中的文字作为 `selected_text` 一起进提示词（后端 `renderer` 对所有模式都注入「选中原文片段」），本机引擎在 chat 分支先逐字回显「你选的这句」；`prompt_engineering.yaml` 的 `test:` → `chat:`（2.2.0，chat 指令补「有选区就以选区为中心作答」）、后端 `protocol.mode` 默认值、`dialogue_service.q_by_mode`、`end_to_end_demo.py` 同步；另把 2026-11-20「全面排查错别字」的 44 处替换**回灌进抽取脚本** `scripts/import_mirror.py` 的 `fix_typos()`（接入 `build`/`apply_trim`/`append_ba`/`insert_sc`），197 部 SPECS 重新逐字节复现现库，D102/D103/D104/D105/D127 五道「正文可复现」门禁 8 个红用例全绿（备份目录不动，比对侧先过 `fix_typos`）；前端 607 项、后端 829 passed + 2 xfailed 全绿） |
| 24 | 复习卡「点了没反应」修复 + 「普通对话」改名「对话」+ 删输入框胶囊（D160） | ✓（根因：`ReviewItem.kind` 把两类条目混在一张卡里 —— `due`（真到期，看 `retention<0.9`/`next_review_at`）与 `interleave`（交错巩固，引擎**不看到期**，只要 `score>=0.6` 就补进池，池恒满 8 条）；交错条目永远不会因自评离开队列 → 「还记得」点了像没反应；到期条目自评后 `next_review_at` 立刻推后、本条本该消失，但既无提示、`route_map._onReview` 又用 `catch (_) {}` 吞错 → 像被卡片吞掉。`ReviewCard` 重写为 StatefulWidget 并按 `kind` 分两张清单：「到期复习」给「还记得(1.0)/忘了(0.2)」，成功后本地移出 + SnackBar 告知下次复习（明天 / N 天后 / M 月 D 日）；`applied:false` 保留条目并显示 `reason`，抛异常提示「记录失败」；「建议巩固」只给「去做混合练习」（跳该知识点章节），不再对未被提问的东西要自评；标题徽标「到期 N 项」只数 `kind=='due'`，交错另记「建议巩固 M 项」；`onReview` 签名改为返回 `Map`；`ChatMode.chat.label` 由「普通对话」改为「对话」（唯一来源 `models/message.dart`），连带 `inputHint`/`askPrompt`/选区 chip/提示词「【本模式】对话」同步；`floating_chat.dart` 删除输入区左侧的 `_modeTag()` 胶囊（含 Tooltip 与 `SizedBox`），输入区只剩「输入框 + 发送」；使用说明补第十节「到期复习 / 建议巩固」两张清单怎么用；新增 `test/review_card_actions_test.dart` 7 条门禁（计数只数 due / 交错无自评 / 还记得移出+下次时间 / 忘了回写 0.2 / `applied:false` 保留+原因 / 抛异常提示 / 全清后收起）；前端 **614** 项、后端 829 passed + 2 xfailed 全绿） |
| 25 | 选中原文点「对话」不再替用户发问（D161） | ✓（旧行为：点「对话」直接 `send('这段在说什么？')`，用户还没输入提示词消息已经发出去；新增 `ChatService.stageSelection/clearStagedSelection` —— 只把选中原文挂起，`send()` 在显式 `selectedText` 为空时合并挂起内容并在发出后立即清空（一条提问只带一次选区）；`work_reader_screen._ask` 与 `chapter_guide_screen._askWith` 的 `ChatMode.chat` 分支改为「挂起 + 打开浮窗」不发问，其余四枚模式仍一点即发；`FloatingChat` 新增 `stagedSelection`/`onClearStaged`，输入框上方显示「已带入你选的原句，输入问题后一起发送」并可点 × 取消，输入提示改为「就你选的那句提问…」；使用说明第三节/第四节同步改写；新增 `test/chat_stage_selection_test.dart` 10 条（挂起不发问 / 输入后合并 / 显式选区不被覆盖 / 取消后不带 / 提示条显隐与 × / 两处 `_ask` 源码分支门禁）；前端 **624** 项全绿、`flutter analyze` 零问题；后端未改动 829 passed + 2 xfailed） |
| 26 | 巩固条目跳章节测试而非导读页（D162） | ✓（旧行为：`route_map._practice` 推 `ChapterGuideScreen`，点「去做练习」落到只读导读页；改为直接推 `ChapterTestScreen`（章节测试本身按知识点 `interleaveItems` 交错排题，正好对上「巩固」语义），返回 `true` 时同时 `_reload()` 与 `_loadDue()` 刷新队列；`review_card` 按钮改名「去做巩固题」、条目说明改「已掌握、不到期；进本章测试做几道题巩固」、组标题「建议巩固 · 不到期，做几道巩固题即可」；使用说明第十节同步；新增 `test/review_practice_jump_test.dart` 3 条源码门禁；前端 **627** 项全绿） |
| 27 | 逐题解析补齐题目/我的答案/正确答案 + 申诉按钮不再「点了没反应」（D166/D167） | ✓（用户实报①「逐题解析只有解析」②「点申诉没反应」。① `chapter_test` 的 `_buildReviewCard` 只渲染 explanation/错因/溯源，而后端 `quiz_service.submit` 与 `LocalQuiz.submit` 早已同构回 `stem`/`options`/`answer_key`/`chosen` —— 抽出 `widgets/quiz_review_card.dart`（`QuizReviewCard`）按「题号+题型+对错 → 题干 → 我的答案 → 正确答案 → 评分反馈 → 解析/参考答案 → 错因 → 溯源」渲染，错因回推 5 个私有 helper 一并搬过去；客观题只报**选项正文**不报字母（作答时选项被 `choice_shuffle` 乱序过，报原始字母会出现「我选 A 怎么显示 C」），未选写「未作答」；主观题凭反馈体标「主观复述/应用论证」（题库里主观题挂在 `error_diagnosis` 题型下，直摆题型名会错位）、解析改标「参考答案」。② 申诉原先 `_api.appeal()` 一调了事——不收理由、不看回执、不提示，本机侧也只往 `LocalDb.tests[tid].appeals` 记一笔，既不改分也无复核台：新增 `widgets/quiz_appeal_dialog.dart`（弹窗明写「本机只记录、不会自动改分」+ 引导先点溯源核原文 + 可选填理由 + 失败不关框就地报错），提交后卡片换「已申诉 · 待复核」、`LocalInsight.appeal` 改为同题去重（`appeal_id` 一题一条对齐后端）并强制回 `status/message`，`LocalQuiz.history` 行补 `appealed`/`appeal_reason` 让错题本标出申诉理由；后端 `/api/quiz/appeal` 补齐 `message` 并注明「不重判、不落库」；新增 `test/quiz_review_card_test.dart` 4 条、`test/quiz_appeal_test.dart` 6 条；前端 **637** 项全绿、`flutter analyze` 零问题；后端 `pytest -k quiz` 26 passed） |
| 28 | 勋章达成动画重做：正中爆开烟花 + 勋章从无到有弹出，一次拿几枚显示几枚（D168） | ✓（用户实报「得到勋章弹出的界面有问题」） | 旧版是「礼物盒掀盖 + 一枚勋章」，且 `badge_screen._load` 只把 `unseenAwards.first` 传进动画、其余静默标记已读 —— 一次拿多枚永远只看得到第一枚。新版 `BadgeGiftOpen` 换成 「一个 340×330 的舞台」：`_FireworksPainter` 自绘三簇烟花（中心 + 左上 + 右三处、各自 delay/span/半径/配色，扩散圆环 + 拖尾粒子 + 爆心白光，progress 用 `easeOutCubic`、粒子角度与速度在 `initState` 一次算好避免抖动）；勋章改 `_Medal`（金盘 + 专属图标 + 小字名），按数量分档 118/92/74/62/54 px、Wrap 自动换行（超多枚时 `SingleChildScrollView` 兜底），每枚用 `Interval(0.22+i*0.055, +0.34)` 的 `Curves.elasticOut` 做 `scale 0→1` 过冲弹出 + `Opacity` 渐显（真·从无到有）；标题单枚显示勋章名+描述、多枚显示「一次获得 N 枚勋章」+ 名称串。同时修 `_c.status` 变化不重建导致「收下勋章」按钮不出现（`addStatusListener` 触发 `setState`）；`badge_screen` 改为整批传入、关掉动画后整批 `markRead`。新增 `test/d168_badge_fireworks_test.dart` 8 条（多枚全显示 / 开场 opacity=0 / 单枚 / 空列表兜底 / 烟花 CustomPaint / 12 枚小屏不溢出 / 源码门禁两条）；前端 **645** 全绿、analyze 零问题） |
| 29 | 章节测试按「易 / 中 / 难 / 拓展」分层出题 + 清除重复题（D169） | ✓（用户实报「题目重复太多、根本没有易中难三个层次」） | 旧题库由固定模板生成（`关于「X」，下列说法正确的是？` 等四套句式），选项是「与其他概念混淆」「应当完整把握」这类不看知识点也能选对的套话，答案恒为 A —— 于是每道题看起来都一样。重写 `backend/content/expand_quiz_bank.py`：① 干扰项改用**其它知识点的真实定义**（同章 → 同路线 → 全书逐级扩池），`crc32` 种子确定性打乱选项位置（答案字母不再恒为 A）；② 四档按认知层次重排 —— 易 0.30「这条表述说的是哪个概念」/中 0.50「给一段表述认出概念名」/难 0.70「四个定义里有一对概念名标错，找出它」（`error_diagnosis` + `exempt_marked`，含刻意错配故豁免立场守门）/ 拓展 0.70「案例应用题（`application`，走 rubric 三维评分）」+「费曼自述题（`error_diagnosis`+`subjective`，走三维度批改）」；③ `quiz_service` 侧新增 `band_of`/`band_quota`（12 题 → 易 4/中 4/难 2/拓展 2）、`_select_items`（同题干归一化去重 + 档内未做过的优先 + 种子乱序，重考换一批）与 `_order_by_tier`（易→中→难→拓展，档内 `_interleave_items` 按知识点轮转）；拓展档「应用—费曼」交替排位，保证每卷各一题；④ `_recent_item_ids` 让同章重考优先避开最近两次做过的题；⑤ 单机侧 `frontend/lib/offline/local_quiz.dart` 同口径复刻（含 `difficulty_band` 下发、`recentItemIds`/`seedForSection`），`QuizItem.band` 供界面用；⑥ 清掉题库 9 组重复题（同知识点挂两章、模板化题干成对），题库 427 → **524 道**；⑦ 修「应用题怎么写都不及格」—— 概念词典没覆盖的新节点 `concept_use` 恒为 0，改为退回按知识点名/题干引号词计分（前后端同改）。界面：`chapter_test` 每题右上角加 易/中/难/拓展 徽标、卷首加「本套 N 题 · 由易到难」+ 各档题数摘要。新增 `backend/tests/test_d169_quiz_tiers.py`（15 条）+ `frontend/test/d169_quiz_tiers_test.dart`（10 条）；前端 **655** 全绿、`flutter analyze` 零问题、后端 **844 passed + 2 xfailed**） |
| 30 | 收下勋章后首页红点不消失、点开重复弹获得页面（D170） | ✓（用户实报「已经点击获得勋章了，还是显示数字，点击又弹出获得页面，要 2 到 3 次数字才消失」） | 根因两条叠加：① `ApiClient.post('/api/badges/read')` 的失效前缀清单里**没有 `/api/badges`**，`GET /api/badges/unseen` 的 30s 短缓存照旧命中 —— 收下勋章的 30s 内仍判「未查看」，红点不消、动画再弹一遍，TTL 到期（约 30s，正好点两三次）才突然正常；② 首页勋章入口在**进入**勋章页之前刷红点数量、返回后不刷。修法：`post` 增 `invalidatePrefix('/api/badges')`；`BadgeApi.mine/unseen` 增 `fresh` 参数绕过短缓存，勋章页与首页都用 `fresh: true`；首页 `onTap` 改 `await _push(BadgeScreen()) → await _loadUnseenBadges()`；勋章页把原本并发的 `mine`+`unseen` 改成**先 mine（内部懒评估会落盘新授予）再 unseen**，否则刚达成的勋章要下次进页面才弹。新增 `test/d170_badge_unseen_after_read_test.dart` 7 条（已读后 unseen 立刻归零 / read_flag 落盘且 mine.read=true / 连读三次仍为空 / 再进页面不弹 / 三条源码门禁）；前端 **663** 全绿、`flutter analyze` 零问题） |
| 31 | 防偏离从「关键词命中」升到「主张归属 + 整体判读」（D171） | ✓（用户实报「不能只靠关键词就拦截了，应该是整体的回答符不符合马列毛思想。要是指出反面例子，不就被拦截了？」） | 体检数据（改前）：涉及批判对象术语的教学式回答 8 条 → **7 条被整段拦掉**；真正的偏离断言 7 条 → **0 条拦得住**；单机版拿输出侧规则审**用户提问** 13 条 → 4 条被拒答；ML 分类器 317 条合成样本置信度 0.53~0.71 ≈ 抛硬币，不能当仲裁。改三层：① **疑点召回**（句子级，`core/guard/orthodoxy.py`）—— 新增 8 条断言级规则（剩余价值不存在 / 资本主义永恒 / 阶级斗争过时 / 技术·文化决定论 / 放弃党的领导 / 解构正统 / 话语建构现实 / 运动就是一切）；② **主张归属** —— 每处命中逐句判 `citation`（引号内 / 有引述框架「有人说、所谓、在他看来」/ 同句有转折纠偏「是错误的、应当批判」/ 输入侧用户在提问）/ `neutral`（批判对象术语的定义·比较·教学式使用）/ `deviation`（作者自己下结论），只对 `deviation` 拦；`critical_object_unwrapped` 从拦截项降级为**标注**（一个术语不再能整段 block，这是「过严」的主因）；③ **整体精判** —— 新建 `core/guard/judge.py`（`StanceJudge`：结构化 JSON、先分 assertion/quotation/rebuttal/example 只判 assertion、256 条缓存、连败 3 次熔断 300s、`STANCE_JUDGE=0` 可关、**任何失败一律 `unavailable` → 标注不拦**），只在规则层有 `annotations` 时调用，正常回答不付成本。动作由二值改四值：`pass` / `annotate`（照常展示 + 标黄）/ `strip`（未实现）/ `block`；④ 单机侧 `local_guard.dart` 同口径复刻（`contextMode: input\|output`、`_assessOccurrence`、`GuardResult.notes`），`local_dialogue` 修掉「拿输出侧规则审用户提问」（P0-1 根因），`stance_notes` 透到界面新增 `StanceNoteChip`（默认一行「立场待核 N 处」，点开看理由，**不拦正文**）；⑤ 补题/评分侧踏坑：出题种子 `hash()` 在 Python 里对 str 是**进程级随机化**的，同一章每次启动选出不同题集 → 掌握度在 0.8 阈值上下抖、测试偶发红，改 `crc32`（`_seed_for_section`）后稳定。新增 `backend/tests/test_d171_holistic_stance.py`（81 条：30+ 正例必放行 / 30 条负例 ≥90% 拦、单条 100% / 11 条用户提问必放行 / judge 5 条）+ `frontend/test/d171_holistic_stance_test.dart`（9 条）；后端 **925 passed + 2 xfailed**、前端 **671** 全绿、`flutter analyze lib` 零问题） |

### 构建信息（v2 重打，合规加固后）

| 产物 | 路径 | 大小 |
|---|---|---|
| 安卓安装包 | `xxmz-1.4.28-android-universal.apk` | 74.4 MB（78,056,700 B） |
| 安卓构建产物 | `frontend/build/app/outputs/flutter-apk/app-release.apk` | 同上（sha1 `719c8c5f927b76eab674757c5824b237659a68d7`） |
| Web 静态站 | `frontend/build/web/` | 72 MB |

- **签名已换成自建 release keystore**：`apksigner verify --print-certs` 显示
  `CN=xxmz, OU=Study, O=xxmz, L=Beijing, ST=Beijing, C=CN`，SHA-1 `d08bdd35c3b7a14652d185e14fc9cc2dbf6223d1`；
  不再是 `CN=Android Debug`。口令在 `frontend/android/key.properties`（已被 `.gitignore` 忽略），
  keystore 在 `frontend/android/keystore/xxmz-release.jks`——**丢了就再也发不了更新包，请离线备份**。
- 权限仍只有 `INTERNET`（详细核对：无第三方 SDK、无埋点、无广告）。
- 体积 74.4 MB（v1.4.28）。增量仍在 `assets/flutter_assets`（离线数据约 23.4 MB）与通用 ABI 的多架构原生库。

- **229 部原著 / 22,377 分片**（含 D127 考茨基 4 篇、D128 硬换行还原、D131 提纲统一库内通行本、D140 章节正则收紧补回 9 段正文）。前端测试 **671** 项全绿、`flutter analyze` 零问题；后端 **925 passed + 2 xfailed**（0 skipped）。
- 三个分片数各自的口径（**都是预期，不是不一致**）：
  - **22,371** = `all_book_chunks()`：229 部本书的分片（书目与分片浏览用全量）。
  - **22,243** = `retrievable_chunks()`：再剔「选集目录序言」等导览专用条目，是 AI 对话实际建的索引。
  - **22,415** = 离线导出 `content_provider.all_chunks()`：在上面基础上**加上统编教材的「正典注释」「正典解析」两层**（44 片，是我们自己写的注疏，`logical_type` 是 annotation/analysis，**不算原著**——所以原著书单 `works` 是 229，不含这两层；分片本身仍可按 id 取到，对话溯源要用）。

## 单机安卓版（无后端，推荐给终端用户）

**装好后不联网也能用**：不需要 Docker、不需要启动后端、不需要任何 API Key。

```bash
# 1) 重新导出离线数据（改了原著/题库/路线后必须重跑）
python scripts/export_offline_assets.py
#    导出脚本会把「著作名集合 + 分片总数」的 sha1 写进 manifest.json 的 fingerprint；
#    忘了重跑会被后端门禁抓到：
#      cd backend && python -m pytest tests/test_d114_offline_assets_fresh.py -q
#    同目录还导出 work_sections.json（书 → 章节反向索引），
#    阅读器顶部「这本书在路线里的哪几章」与书单的「N 章」都读它；
#    原著漏挂路线会被 tests/test_d114_route_covers_all_books.py 抓到。

# 2) 先杀残留 java 进程（否则 aapt2 守护进程会连锁报
#    `AAPT2 Daemon startup failed / Please check if you installed the Windows Universal C Runtime`，
#    报错与资源本身无关，改 XML/删 PNG 都无效，只有杀进程能恢复）
taskkill //F //IM java.exe

# 3) 打安卓包（release 签名读 android/key.properties；缺失才回落 debug）
cd frontend
flutter build apk --release
# 产物：frontend/build/app/outputs/flutter-apk/app-release.apk
# 核对签名：apksigner verify --print-certs <apk>   # 应为 CN=xxmz，不是 CN=Android Debug
```

- **数据来源**：构建期把 `sources/texts` 正文、章节导读、题库、概念卡、红线规则、阈值参数
  编译进 `frontend/assets/offline/`（`meta/knowledge/quiz/chunks.json` + `sections/*.json`），随 APK 分发。
- **运行时**：`frontend/lib/offline/` 里的 `LocalRouter` 顶替原来的 HTTP 层，界面代码零改动；
  掌握度 / 门控 / 间隔复习 / 判分 / 校准 / 推荐 / 激励 / 分析 全部在 Dart 侧按后端同一套公式重算。
- **对话（默认）**：本机「原文检索（字符 n-gram）+ 概念卡 + 苏格拉底追问」生成回答，
  只引用库内真实原文（红线：不伪造引文），偏离表述由 `LocalGuard` 拦下，可切「批判性阅读」分析。
- **对话（可选在线）**：功能中心 →「LLM 大模型 API 配置」填 API Key / Base URL / 模型
  （OpenAI 兼容：通义 / DeepSeek / 文心 / Kimi / 智谱均可），保存即生效、可先「测试连接」。
  凭证只写本机 `SharedPreferences`、不上传，GET 只回掩码；模型输出同样过立场层，
  偏离即拦截并回落本机回答；断网/超时自动回落，回答上方标注「本机引擎 / 在线模型」。
  实现见 `frontend/lib/services/llm_{config_store,client}.dart` 与 `offline/local_router.dart::_llmConfig`。
- **学习数据**：只存在本机 `SharedPreferences`（无账号、无上传）；卸载即清空。
- **已知取舍**：原文分片约 15MB，首次进入原文/题库页需 1~2 秒解析（已懒加载）；应用常驻内存随之增加。

## 快速开始（联网 / 开发版）

### ⚡ 一键安装 / 一键启动（推荐）

**Windows**：双击根目录的 **`一键安装.bat`**（首次安装依赖），然后双击 **`一键启动.bat`**。
启动后自动打开浏览器；停止双击 **`停止.bat`**（或直接关窗口）。

**Git Bash / Linux / macOS**：
```bash
./一键安装启动.sh          # 安装 + 启动（一步到位）
./一键安装启动.sh install  # 仅安装
./一键安装启动.sh start    # 仅启动
./一键安装启动.sh stop     # 停止
```

脚本做的事：① 建虚拟环境 `backend/.venv`（复用本机已装依赖，秒建）+ 装 `requirements.txt`；② 由 `.env.example` 生成 `backend/.env`；③ 有 Flutter 则构建前端（可选）；④ 轻量模式启动后端 `:8190` + 前端静态服务 `:8080`，打开浏览器。

> 所有逻辑在 `scripts/oneclick.py`（纯标准库），`.bat`/`.sh` 仅为薄封装（避免 Windows GBK 控制台中文乱码）。

### 🔑 网址 / 账号 / 密码

| 项 | 值 |
|---|---|
| **网页界面** | http://localhost:8080 |
| **接口文档（Swagger）** | http://localhost:8190/docs |
| **登录账号 / 密码** | **无 —— 本系统当前没有登录页，打开即用** |
| 当前用户身份 | 固定演示用户 `demo_user`（前端常量，后端按此用户记录学情） |

说明：后端虽已内置 `/api/auth/register`、`/api/auth/login`（bcrypt+JWT）接口，但**前端 UI 尚未接入登录**，所有页面默认以 `demo_user` 直接使用。若后续需要多用户/鉴权，需另接入登录页。

### ℹ️ 关于页

首页右上「功能中心」→「关于」展示应用名称、客户端版本（`frontend/pubspec.yaml` 的 `1.4.7+28`）、服务端版本（`backend/app.py` 的 `0.1.0-mvp`）、包名、技术栈与本地地址，以及项目 GitHub 地址、作者/版权和使用说明入口。

「功能中心」另有「**法律与隐私**」入口，含隐私政策、用户协议、免责声明、内容来源与著作权说明、AI 生成内容提示。运营者名称/邮箱/APP 备案号未配置时，该页顶部会显示醒目待办横幅——**未补齐不可上架**。

> 版本与名称均取自仓库内权威文件；本仓库**没有** `.git`/remote、LICENSE 或 author 字段，所以 GitHub 地址与作者默认显示为「未配置 / 未声明」，不会编造或用第三方仓库冒充。补填方式二选一：① 在关于页点「编辑项目信息」（存本机 `shared_preferences`，仅本机生效）；② 直接改 `frontend/lib/config/app_meta.dart` 里的 `githubUrl` / `author` 常量（随代码生效）。

### 模式 A：轻量模式（无 Docker，最快验收，一键脚本默认用此模式）

后端用 Mock LLM + 规则召回 + 内存对话，**不需要任何外部服务**（DB 懒加载，`AUTO_CREATE_TABLES=0` 时完全不碰 asyncpg），学习闭环引擎用 SQLite 内存库（`LEARNING_DB_MODE=memory`）。

```bash
cd backend
pip install -r requirements.txt
# 用 python -m uvicorn 确保走装了依赖的 Python（不是全局 uvicorn.exe）
AUTO_CREATE_TABLES=0 python -m uvicorn app:app --host 0.0.0.0 --port 8190
```

验证闭环（4 用例：解释+溯源 / 越狱拦截 / 辩难豁免 / 偏离拦截）：

```bash
pip install websockets
python demo_e2e.py
```

前端：

```bash
cd frontend
flutter pub get
flutter run -d web  # 开发模式，或 windows / chrome
```

生产构建（打成静态站点，由 `scripts/serve_frontend.py` 无缓存托管）：

```bash
flutter build web --pwa-strategy=none --no-web-resources-cdn --no-tree-shake-icons
# ↑ --no-web-resources-cdn 关键：把 CanvasKit 打进本地 canvaskit/ 目录，
#   否则默认从 www.gstatic.com 拉取——国内网络访问不到会导致【页面一片空白】。
# ↑ --pwa-strategy=none：禁用 Service Worker，避免旧缓存导致白屏。
# ↑ --no-tree-shake-icons 关键：Flutter 的图标 tree-shaking 不会收录「框架自动注入」的
#   图标（AppBar 返回箭头 arrow_back、下拉箭头 arrow_drop_down、close、check 等），
#   这些码点缺失后 CanvasKit 会渲染成【方框内带 X】的 .notdef 豆腐块（左上角返回箭头即如此）。
#   因此必须关闭 tree-shaking，打包官方全量图标字体（1.57MB，localhost 无所谓）。
# 字体已随包（assets/fonts/Deng.ttf 等），web/flutter_bootstrap.js 把字体回退基址
#   指向本地 assets/fonts/，全程不请求 fonts.gstatic.com，中文不再乱码。
# 前端由 scripts/serve_frontend.py 托管会带 no-cache 头，避免旧 main.dart.js 被浏览器
#   启发式缓存（Flutter 的 main.dart.js 文件名不含 hash，缓存住就会“改好了仍显示旧bug”）。
```

> 若浏览器打开只有白屏：多半是构建时没加 `--no-web-resources-cdn`（CanvasKit 走 gstatic 被墙），
> 或旧 Service Worker 缓存。重新用上面命令构建并强制刷新（Ctrl+F5）即可。
>
> 中文乱码 / 字体下载超时（`fonts.gstatic.com`）：本项目已内置中文字体并把回退基址本地化，
> 正常构建后不会再出现。若自行改动构建，请保留 `web/flutter_bootstrap.js` 与 `pubspec.yaml` 的 fonts 段。

### ML 立场分类器（可选，提升 SC-004）

```bash
cd backend
python -m ml.synthesize_data   # 模板合成 ~500 条训练数据（无 API）
python -m ml.train_stance      # 训练 + 保存 ml/stance_model.joblib
```

训练后 `DialogueService` 自动注入 `StanceClassifier`（confidence ≥0.6 覆盖规则，低置信回退）。模型缺失时回退规则版，不阻塞运行。

**LLM 合成升级（可选，提升泛化）**：模板样本句式单一，配 `LLM_API_KEY` 后可调通义千问生成更多样样本：

```bash
# 先在 .env 填 LLM_API_KEY（申请：https://dashscope.console.aliyun.com）
python -m ml.synthesize_llm --count 500   # 生成 ml/llm_samples.json
python -m ml.train_stance                 # 自动合并 LLM 样本重训
```

### 模式 B：完整模式（Docker 一键启动）

含 PostgreSQL(pgvector) + Redis + Neo4j + 后端 app，真实持久化 + 向量/图召回。

```bash
cp backend/.env.example backend/.env   # 填 LLM_API_KEY 走真实模型（可选）
docker compose up --build
```

- 后端 API：http://localhost:8190
- 健康检查：http://localhost:8190/health
- Neo4j Browser：http://localhost:7474（neo4j / marxism_pass）

## 测试

本项目不是 Node 工程，但根目录放了一个**只含脚本入口的** `package.json`（不装任何 npm 依赖），
让 `npm` 系工具（含 claude-scene 的 loop / review 门禁）有统一入口：

```bash
npm test              # = cd frontend && flutter test        （当前 671 passed）
npm run lint          # = scripts/lint_shim.js → flutter analyze lib/ test/（当前 No issues）
npm run analyze       # 同上，直连 flutter analyze
npm run test:backend  # = cd backend && python -m pytest tests/ -q（当前 925 passed + 2 xfailed）
```

后端测试：

```bash
cd backend
pip install -r requirements-dev.txt   # 含 pytest / scikit-learn / joblib / openai / websockets
python -m pytest tests/ -q
```

Phase 6 核心套件（含在整个 925 passed 里）：

| 测试文件 | 验证 |
|----------|------|
| `test_sc003_interception.py` | SC-003 防偏离拦截率（规则版 100%，误拦截 0%） |
| `test_sc007_exemption.py` | SC-007 FR-006 标记豁免四象限（含未闭合防绕过） |
| `test_sc004_stance_f1.py` | SC-004 立场 F1（规则版 0.933）+ P0-2 困难负样本 |
| `test_sc001_latency.py` | SC-001 端到端延迟 ≤3s（解释/拦截/豁免/P95） |

## 架构

```
用户选中文本 ──ws──▶ FastAPI (app.py)
                      │
            ┌─────────┴──────────┐
            ▼                    ▼
   DialogueService        WebSocket (ws/protocol.py)
      │  编排
      ├─ PromptSanitizer   输入侧防注入（NFKC + 12 正则 + 关键词）
      ├─ OrthodoxyGuard    生成侧立场校验（CRITICAL_OBJECTS + STANCE_PATTERNS + 标记豁免）
      ├─ PromptRenderer    YAML 驱动渲染（五模式 + 批判性阅读叠加）
      ├─ LLMRouter         4 级路由（cache → 语义缓存 → 本地 → 云）
      └─ TripleCheck       生成后三重校验（事实 + 术语 + 立场）
                      │
            ┌─────────┴──────────┐
            ▼                    ▼
   RAG 召回（content/）    溯源卡片（FR-017）
   提纲11条 + 概念锚点       chunk_id/权威分/三重校验状态
```

防偏离三重机制（产品命门）：

1. **输入侧** `PromptSanitizer` — 越狱/角色切换/系统提示探测/全角绕过拦截
2. **生成侧** `OrthodoxyGuard` — 批判对象清单 + 立场模式正则（12 条）+ 辩难豁免标记
   - 「正统限定语豁免」双向：恩格斯「决定性因素**归根到底**是…」、毛「**能动的**革命的反映论」
     这类原话放行，但同句出现「共同决定/互为决定」等**否决词**即不豁免
   - **毛泽东思想三项基本点**（两类矛盾 / 群众路线 / 独立自主）各有专门规则：
     只拦「否认、替换、说已经过时」，正统论述不误拦
3. **生成后** `TripleCheck` — 事实一致性 + 术语红线 + 立场二分类（BERT 接口位）

口径（D141 修订，避免自我矛盾）：**原理层一元**（唯物论/辩证法/唯物史观/阶级分析没有
「多个版本」）＋**具体结论可争**（个别论断、具体策略、文本解读历来有真实争论，照实讲）＋
**原著内部论战不算「多种解读」**（马克思对蒲鲁东、恩格斯对杜林、列宁对经验批判主义、
毛泽东对苏联政治经济学教科书）。不再声称「正统体系是唯一科学的体系」——那与恩格斯
《致威·桑巴特》、毛泽东《整顿党的作风》的原话冲突。

## 防偏离数据集

`backend/tests/deviation_dataset.py`（53 条内测样本）：

- `ORTHODOX_SAMPLES`（15）— 正统表述，应 pass
- `DEVIATION_SAMPLES`（30）— 西马/修正主义/后马克思/唯心话术，应 block
- `HARD_NEGATIVE_SAMPLES`（8）— 批判性引用西马概念的正统文本，应 pass（P0-2）

生产目标：SC-003 扩到 500 条 / SC-004 扩到 2000 条。

## 已知边界（留后续阶段）

- **ML 立场分类器已实现**：`ml/train_stance.py`（TF-IDF char n-gram + logreg，317 条合成数据训练，macro-F1=0.90）注入 `TripleCheck.stance_classifier`，配合 confidence 阈值降级（≥0.6 覆盖规则，低置信回退）解除规则版 4 条语义方向 xfailed。模型缺失时自动回退规则版。生产升级：扩充到 500+ 条标注数据 + 真实 BERT（需 GPU）。
- **RAG 真实召回接口就绪，待 Docker 联调**：`HybridRetriever` 三路混合召回（向量+图+关键词）已接入对话流，默认 in-memory store（3-gram 哈希 + 邻接表图）。`PgvectorStore` / `Neo4jGraphStore` 接口骨架已留（标注 `NotImplementedError`），Docker up 后实现 search/upsert 即切换，`retrieve()` 接口不变。
- **6 阶段结构化索引未补**：MVP 仅第 2 阶段提纲 11 条；第 0/1/3-6 阶段原著后续。
- **内容层仅提纲 11 条**：内容由项目编写（基于艾思奇/统编教材正典阐释）。

## 配置（`backend/.env`）

见 `backend/.env.example`。关键项：

- `LLM_API_KEY` — 配齐走真实国产模型（通义/文心/DeepSeek，OpenAI 兼容）；留空走 Mock
- `AUTO_CREATE_TABLES` — 完整模式 `1`（建表），轻量模式 `0`（跳过）
- `ENABLE_SEMANTIC_CACHE` — 语义缓存开关
- `SECRET_KEY` — 默认 `change-me-in-production`，**对外提供服务前必须换成 32 字节以上随机值**

### ⚠️ 部署边界（务必先看）

本后端**所有 `/api/*` 路由都不做身份校验**，`user_id` 由调用方自报（默认 `demo_user`）。
这意味着：**任何能访问到 8190 端口的人，都能读写任何人的学习数据、改 LLM 配置、消耗你的 API 额度。**

因此：

- 默认只允许跑在**本机回环地址**；`docker-compose.yml` 已把 8190 / 5432 / 6379 / 7474 / 7687 全部绑到 `127.0.0.1`
- 启动时会打印安全告警（弱口令 / CORS 通配 / 无鉴权），看到告警就说明「这份服务只能自己用」
- 要多人使用，必须先补鉴权（`auth_routes.py` 已能签发 JWT，但**没有任何路由校验它**）

## 版权与合规

- **[`CONTENT-NOTICE.md`](CONTENT-NOTICE.md) — 原著正文的来源、逐部权利状态与异议处理（正文相关的一切以此为准）**
- [`NOTICE.md`](NOTICE.md)：项目性质（个人非官方）、软件许可、内容来源、著作权状态、已排除内容、隐私口径
- 应用内「功能 → 法律与隐私」提供同口径的隐私政策 / 用户协议 / 免责声明

三句话概括正文的法律状态：

1. 229 部正文的著作权**不在本项目手里**，本项目不主张权利、不授予许可。
2. 其中 **75 部（毛泽东 48、周恩来 27）至 2026-12-31 仍在保护期**；其余 154 部已届满。
3. 译者权与版式设计权**尚未逐部核实**。用于出版、教学分发或商业用途前，请咨询执业律师。

项目所有者在了解上述风险后选择公开本体，并承诺收到权利人有效通知后七日内移除相关文件。
本文件不构成法律意见，也不构成任何形式的免责——它只是把事实写清楚。

## 原著正文数据

**正文随仓库分发**：`sources/texts/*.txt`（229 部，18 MB）与派生的
`frontend/assets/offline/`（23.4 MB，含 22,415 段原文）都已入库，克隆即完整可用。

权利状态与使用限制见 **[`CONTENT-NOTICE.md`](CONTENT-NOTICE.md)**。
逐部的来源页面、字数、版本说明与取舍理由在
[`sources/texts/SOURCE_MANIFEST.md`](sources/texts/SOURCE_MANIFEST.md)。

如果你**删掉了正文**（或只想跑纯代码），项目仍能启动，但只有教学框架：

| 能力 | 无正文 | 有正文 |
|---|---|---|
| 后端启动 / 路由挂载 | ✓ 19 组路由 | ✓ |
| 学习路线 / 章节导读 / 题库 | ✓ 32 节 / 119 题 | ✓ |
| 立场守门 / 离线学习闭环 | ✓ | ✓ |
| 检索命中 | 0（书单空） | 22,371 分片 |
| 后端 `pytest` | 184 passed / 517 skipped / **0 failed** | 735 passed / 0 skipped / 2 xfailed |
| 前端 `flutter test` | 79 passed / 9 skipped / **0 failed** | 341 passed |

依赖正文的用例都打了 `needs_texts` 标记（后端 `backend/conftest.py`）或调用
`skipWithoutOfflineAssets()`（前端 `frontend/test/helpers/`），缺数据时自动跳过并给出
补齐指引——不会把「缺数据」伪装成「代码坏了」。

重新补正文的方式：

```bash
# 方式 1：自己准备 txt（文件名/格式见 sources/texts/README.md 与 SOURCE_MANIFEST.md）
#   放入 sources/texts/ 后确认 backend/content/book_chunks.py 的 BOOKS 里有登记
#   （id_prefix 必须是 CH- + 四个大写字母）

# 方式 2：用仓库自带的镜像导入脚本，从你有权使用的镜像批量照录
cd backend
python ../scripts/import_mirror.py --help   # 镜像路径用环境变量 XXMZ_MIRROR 指定

# 改过正文必须重新导出前端离线数据，否则门禁会失败
python ../scripts/export_offline_assets.py
cd backend && python -m pytest tests/test_d114_offline_assets_fresh.py -q
```

⚠️ `book_chunks` 是进程内 `lru_cache`：改完 `.txt` 要**重启后端**才生效；
新增书还要在 `BOOKS` 登记并挂上学习路线（`local_work`），否则只在索引里、进不了章节。

## 许可

**CC BY-NC 4.0（署名-非商业性使用 4.0 国际）**，全文见 [`LICENSE`](LICENSE)。

源码完全公开，允许**非商业性**使用、修改、再分发（含改编作品的非商业分发）；
**禁止任何以商业利益或金钱报酬为主要目的的使用**（商用销售、付费服务、商业集成等）。

唯一义务是保留署名、版权与许可声明、注明修改，且不提供任何担保。

许可覆盖**代码**与项目自撰的**辅助材料**（导读、注释、题库、路线设计、文档）。

**不覆盖**原著正文与译文：它们虽随仓库分发，但权利归各作者、译者与出版者，
本项目无法就它们授权。详见 **[`CONTENT-NOTICE.md`](CONTENT-NOTICE.md)**。

> 说明：CC BY-NC 是「源码公开、非商业使用」类许可——代码完全公开、可自由阅读和非商业使用，
> 但它**不是** OSI 认证的开源许可，因为「非商业」限制与开源定义（不限制使用领域）不兼容。

## 文档

仓库只保留与运行、内容、权利相关的六份文档，其余设计过程记录不随仓库分发。

| 文件 | 内容 |
|---|---|
| [`README.md`](README.md) | 本文件：能力、启动、架构、配置 |
| [`原著入库清单.md`](原著入库清单.md) | 229 部正文的逐部判定：收录理由、取舍、红线决策 |
| [`CONTENT-NOTICE.md`](CONTENT-NOTICE.md) | 正文的权利状态、来源、用途与异议处理 |
| [`NOTICE.md`](NOTICE.md) | 项目性质、软件许可、已排除内容、隐私口径 |
| [`sources/texts/SOURCE_MANIFEST.md`](sources/texts/SOURCE_MANIFEST.md) | 每部正文的镜像来源页面、字数、版本说明 |
| [`sources/texts/README.md`](sources/texts/README.md) | 正文文件命名与格式规范 |

代码即文档：路由在 `backend/api/`，业务编排在 `backend/services/`，
检索/守门/提示词引擎在 `backend/core/`，学习路线内容在 `backend/content/`。

端到端演示：

```bash
cd backend && python demo_routes_flow.py   # 无需 Docker，学习引擎默认内存 SQLite
```
