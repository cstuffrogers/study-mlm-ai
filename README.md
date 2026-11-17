
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

### 构建信息（v2 重打，合规加固后）

| 产物 | 路径 | 大小 |
|---|---|---|
| 安卓安装包 | `唯物马哲精读-单机安卓版.apk` | 72.1 MB（75,556,606 B） |
| 安卓构建产物 | `frontend/build/app/outputs/flutter-apk/app-release.apk` | 同上（sha1 `396de776d35f1d29b7ec62787e5fcc690ee9b672`） |
| Web 静态站 | `frontend/build/web/` | 72 MB |

- **签名已换成自建 release keystore**：`apksigner verify --print-certs` 显示
  `CN=xxmz, OU=Study, O=xxmz, L=Beijing, ST=Beijing, C=CN`，SHA-1 `d08bdd35c3b7a14652d185e14fc9cc2dbf6223d1`；
  不再是 `CN=Android Debug`。口令在 `frontend/android/key.properties`（已被 `.gitignore` 忽略），
  keystore 在 `frontend/android/keystore/xxmz-release.jks`——**丢了就再也发不了更新包，请离线备份**。
- 权限仍只有 `INTERNET`（详细核对：无第三方 SDK、无埋点、无广告）。
- 体积从 72.06 MB 涨到 75.56 MB，增量在 `assets/flutter_assets`（离线数据 23 MB → 23.4 MB）。

- **229 部原著 / 22,377 分片**（含 D127 考茨基 4 篇、D128 硬换行还原、D131 提纲统一库内通行本、D140 章节正则收紧补回 9 段正文）。前端测试 **288** 项全绿、`flutter analyze` 零问题；后端 **773 passed + 2 xfailed**（0 skipped）。
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

首页右上「功能中心」→「关于」展示应用名称、客户端版本（`frontend/pubspec.yaml` 的 `1.3.4+15`）、服务端版本（`backend/app.py` 的 `0.1.0-mvp`）、包名、技术栈与本地地址，以及项目 GitHub 地址、作者/版权和使用说明入口。

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
npm test              # = cd frontend && flutter test        （当前 288 passed）
npm run lint          # = scripts/lint_shim.js → flutter analyze lib/ test/（当前 No issues）
npm run analyze       # 同上，直连 flutter analyze
npm run test:backend  # = cd backend && python -m pytest tests/ -q（当前 735 passed + 2 xfailed）
```

后端测试：

```bash
cd backend
pip install -r requirements-dev.txt   # 含 pytest / scikit-learn / joblib / openai / websockets
python -m pytest tests/ -q
```

Phase 6 核心套件（含在整个 735 passed 里）：

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
| 前端 `flutter test` | 79 passed / 9 skipped / **0 failed** | 288 passed |

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

**MIT**，全文见 [`LICENSE`](LICENSE)。允许商用、修改、再分发与闭源集成，
唯一义务是保留版权与许可声明，且不提供担保。

许可覆盖**代码**与项目自撰的**辅助材料**（导读、注释、题库、路线设计、文档）。

**不覆盖**原著正文与译文：它们虽随仓库分发，但权利归各作者、译者与出版者，
本项目无法就它们授权。详见 **[`CONTENT-NOTICE.md`](CONTENT-NOTICE.md)**。

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
