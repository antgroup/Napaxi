# compaction deterministic floor — 升级路线图（审计基线）

> 来源：DIMA 工单 2026111100120544211（OpenClaw 巡检 2026-11-11）。
> 本文件记录 OpenClaw #197105 / #197179 的"deterministic floor"语义、Napaxi 现状基线对照、
> 以及后续精修 CR 的升级行动项。本 CR **不引入任何生产改动**，仅确立 audit baseline +
> 回归测试 + 路线图文档。
>
> 11-16 更新（DIMA 工单 2026111600120683137，OpenClaw 巡检 2026-11-16）：增补 11-12~11-16
> compaction 正确性族延续性（§5），并新增「反向验证 / 设计参照」备忘条目（§6）。仍不引入
> 生产改动。
>
> 11-17 更新（DIMA 工单 2026111700120722148，OpenClaw 巡检 2026-11-17）：
> 增补 11-17 窗口 compaction 正确性族延续性（§5 新增一行），并扩充 §6 defensive-design
> boundary 簇（per-page skills-used REVERT 两例并轨 + OAuth MCP 单 owner 对齐验证
> + subagent 持久族 + compaction 准备工作线程化 + secrets redaction + restart
> 资源退役族互链）。仍不引入生产改动。
>
> 11-18 更新（DIMA 工单 2026111800120760358，OpenClaw 巡检 2026-11-18）：
> 增补 11-18 窗口延续性（§5 末追加一行），并新增 §6 子节「11-18 新增条目」——含
> defensive-design boundary 簇第 3 对（#200899 = 11-17 REVERT #196065 答案形态：
> admission-prepare + lazy-invalidate + immutable-witness）、#200249 簇 subagent
> 持久续修（outage/steer/expiry 第 4 迭代）、sandbox checkpoint lease-contention
> 仲裁族。仍不引入生产改动。

## 1. OpenClaw 修复语义

- **#197105 `fix(compaction): keep a deterministic record when summarization is refused`**
  summarizer 拒绝时，旧实现 `compactWithoutSummary` 丢压缩区、只留一行 notice——对承载中的
  durable turn 等同"丢永久记录"。修复 carry 一份 **model-free deterministic floor**：
  - 用户消息 **verbatim**（newest first、按预算、omissions 计数）；
  - 最被引用 identifiers；
  - 最后 assistant replies；
  - credential shapes redacted；
  - 后续 notice 指向 stored transcript；
  - floor messages 按 recorded origin 归因（避免 inter-session/internal/multi-sender 输入
    被当成 user 自语）。

- **#197179 `keep the deterministic floor on successful summaries`**
  每个成功生成的 summary 在 session commit 点附 floor：
  - floor 自身 6,000-char 预算独立于 `maxSummaryChars`，按 foreground token budget 缩/丢；
  - cut walk 为 floor 留位；
  - next compaction 从 carried summary 剥旧 floor，**floors 不累积**；
  - no-summary artifacts 保各自 floor。

## 2. Napaxi 现状 ground check（本周基线）

模块 `crates/core/src/context/compaction.rs`：

- `summarize_middle`（compaction.rs:149）：LLM summarizer 失败时 fallback 到
  `summarize_middle_locally`，strategy=`local_summary_fallback`，显式 warn
  "Context compaction LLM summary failed; falling back to local summary"
  （compaction.rs:179）。**起点高于 OpenClaw 修复前的"drop 一行 notice"**——不会丢永久记录。

- `summarize_middle_locally`（compaction.rs:192）的保真度差距：
  - user 消息走 `compact_text_preview(&message.content, 280)`——截到 280 字符 + "..."，
    非 verbatim 全保留；
  - `bullet_list(&user_items, 8)`——仅保留前 8 条 user item，第 9 条起 **完全丢弃**，
    无 omission 计数；
  - 产物是合成 bullet 摘要（User Goals / Assistant Progress / Tool Outcomes 三段），
    无"最被引用 identifiers"提取、无 credential shape redact。

  → 即"已有 fallback、非 drop"，但在 summarizer 失败/截断处仍有保真度差距：
  真实用户原话（尤其较长/含关键约束的旧 user 措辞）被截断成 bullet 而非 verbatim 保留。

## 3. 本 CR 的 audit-baseline 回归测试

`crates/core/src/context/tests.rs` 新增
`local_summary_fallback_truncates_long_user_wording_and_omits_beyond_eighth_user_item`：
快照 **deterministic-floor 升级前** 的 `local_summary_fallback` 行为——
- 280-char preview 截断长 user 措辞（unique tail 不存活，非 verbatim）；
- bullet_list(.., 8) 省略第 9 条及之后 user item（无 omission 计数）。

升级后该 test 须更新为「verbatim 保留 + omission 计数」断言，届时改 test，本 CR 不动生产码。

## 4. 升级行动项（后续精修 CR，非本 CR）

把 `summarize_middle_locally` 从"280-char preview + 8 条 bullet 合成摘要"升级为
model-free deterministic floor：
- verbatim 用户消息（newest first、按预算）；
- omission 计数（被截断/省略的 user 条目计数，写入 floor notice）；
- 最被引用 identifiers 提取；
- 最后 assistant replies；
- credential shapes redacted；
- floor 自身预算独立于 summary budget；
- 后续 compaction 从 carried summary 剥旧 floor，防 accumulate。

估时 1–1.5 天（verbatim floor 实现 + omission counting 单测 + 防 accumulate 单测覆盖
二次 compaction）。

## 5. 延续性

延续 compaction 正确性族深化序列：
- 11-08 compaction-watchdog nested-attach；
- 11-10 compaction default-window fallback audit；
- **11-11 deterministic floor（拒/成两路径）**；
- 11-12 floor 纵深 credential-redaction；
- 11-13 prefix append-only / OAuth 单 owner；
- 11-14 skill-snapshot 多入口 / item 冲突；
- 11-15 并发协调 + 中断 abort；
- **11-16 REVERT 并发协调 + manual 扁拷贝 + provider-side compaction 归因 + 重启资源**。
- **11-17 prepare 大 history out-of-thread + REVERT #200159/#196065 skills-used
  per-page 全扫 + subagent 持久族（#200249 簇）+ OAuth MCP 在线 sign-in 单 owner
  （#200538）**。本周 REVERT 反向信号达**两例**（11-16 #196550 + 11-17 #196065，
  两处 per-page/per-session 全扫描/全量共享设计在大型 session 上 cost 不可接受被证伪）；
  Napaxi 单进程同步 in-memory 单 turn 串行 compaction **两形态均不触达**，叠加
  11-15/11-16 反向验证，防御性边界确认。

11-16 #199561 REVERT #196550 是本周首次 REVERT 反向信号：OpenClaw "并发会话共享 compaction
facts" 在 cold-path 成本不可接受而被回退，**反向验证 Napaxi 单会话 compaction 形态为正确基本
形态**（详见 §6 第一条 defensive-design boundary）。

本 CR 只落基线 + 路线图，不动生产路径，与上述序列的"补/审"层一致。

- **11-18 subagent 持久簇门跨窗第 4 迭代（outage/steer/expiry）+ sandbox
  checkpoint lease 仲裁 + session-list admission-prepare 正确形态（#200899
  = 11-17 REVERT #196065 答案）** —— OpenClaw compaction 主题本周转入
  subagent/sandbox 持久资源治理线，与 compaction 正确性族并行持续；本轮
  ground check 全部零命中（Napaxi inline 单进程同步）。

## 6. 不在范围（workitem 已确认非缺口／备忘）

- **#196550 被 #199561 REVERT — 反向验证（defensive-design boundary）**：OpenClaw "并发会话
  共享 compaction facts"（11-15 备忘的"未来若并发须共享 facts"）在 cold-path 成本不可接受被
  回退，跨会话共享 compaction facts **不应被默认基建**。Napaxi `crates/core/src/context/compaction.rs`
  单会话 compaction（`summarize_middle` / `summarize_middle_with_llm` 单 turn 串行，无跨会话
  facts 共享）是被反向验证印证的正确基本形态。**降级 / 撤回 11-15"未来若并发须共享 facts"备忘**：
  若未来确需多会话并发，走"每会话独立 compaction + 共享稳定 transcript 读取缓存"，而非"共享
  compaction facts"。记入本节作为 defensive-design boundary。
- **#199840 manual compaction 省冗余拷贝（设计参照）**：OpenClaw manual preflight 用既有 read-only
  branch accessor 替代可写 SDK copies，省重复 transcript 拷贝。Napaxi manual compact 直接在
  in-memory `Vec<Value>` 上 read in place，无多 worker 跨进程 branch read、无 writable SDK copies
  重复，**不撞**。设计参照：未来 daemon 化 + 跨进程 transcript 共享须用 read-only branch accessor
  而非每路 request writable copy。仅备忘。
- **#198730 provider server-side compaction 当 rebuild point 显式宣告（设计参照）**：OpenAI
  Responses 在 70% context window 触发 server-side compaction，须把 checkpoint 显式宣告为 prompt
  history rewrite（compaction rebuild point）而非 provider drift，否则 prompt-cache audit 误报
  unexplained warm cache breaks。Napaxi 路由当前**无 OpenAI Responses `context_management`
  通路**（仅客户端检测 provider overflow 后 compact-and-retry-once），不撞。设计参照：未来引入
  该路由时须把 server compaction-induced checkpoint 显式宣告为 "compaction rebuild point"——与
  11-13 prefix append-only / system-prompt pin 同处 prompt-cache prefix 协同线。仅备忘。
- **#196868 tool_describe default 不发 output schema**：Napaxi 工具定义静态嵌 prompt
  （`crates/core/src/tools/file/descriptors.rs` 等 const 描述），无动态 tool_describe /
  Tool-Search 按需拉取，不撞 #196868 同形问题。设计参照：若未来引入按需 tool describe，
  须默认只发 description + input schema，output schema 显式 opt-in。仅备忘，不立项。
- **#197230 reindex shadow admission 退役**：Napaxi memory 非 in-place FTS reindex 路径，
  无 SQLite 文件 lifetime admission / POSIX-lock-bound descriptor retention 概念，不构成
  现状缺口。设计参照：若 daemon 化引入 shadow/template/临时 DB 文件，须在删文件前显式
  退役 admission 避免残 inode——与 sandbox template 跨 restart 复用同族资源卫生。仅备忘。

### 11-17 新增条目（DIMA 工单 2026111700120722148）

- **#196065 被 #200159 REVERT — 反向验证（defensive-design boundary，本周第二例）**：
  OpenClaw 每打开一次 chat 在 first-page skills-used 读扫**全 transcript**，在 36k-event
  session 上每分钟挂 55–60s 上下文，冻结 transcript appends / pendingInputs
  mutations / subagent deliveries；被 REVERT，bounded re-land 改"per-run
  skillsUsed facts, no full scan"。与 11-16 #196550 同形态（per-page/per-session
  全扫描 + 共享 facts 在大型 session 冷启动/反复开销不可接受）。Napaxi
  `crates/core/src/context/` grep `skills.used|skills_used|skillsUsed` 零命中 ——
  **Napaxi 无此 feature，never 触及，非反向回退的受害者**。**防御性边界结论**：
  未来若 Napaxi 引入 per-page/per-session 触发 feature + 全 transcript 扫描基线，
  须预先证 cost（限扫 + per-run facts，**不 each-page full scan**）——与 11-16
  #196550 的"不默认共享 compaction facts"同处一簇，记入本节作 defensive-design
  boundary。仅借鉴设计思路与边界规则，不直接移植代码。

- **#200538 OAuth MCP 在线 sign-in / running-Gateway 为 single owner — 对齐验证 Napaxi 既有方向**：
  OpenClaw 把 running Gateway 成 MCP 共享 sign-in 的单 owner——`openclaw mcp
  login`/`logout` 在 Gateway 运行时也 work，direct chat 内"connect Linear"→
  拿 sign-in link→同 reply 批准→下条消息用 Linear，不重启；安全边界：owner-only +
  direct chat 未处理 untrusted + 链路单次 + PKCE verifier 绑定 + 无
  `gateway.publicOrigin` 时 redirect 走 loopback。**Napaxi ground check**：
  `crates/core/src/mcp/oauth.rs`（use_pkce @ oauth.rs:108/125）、
  `crates/core/src/mcp/oauth_flow.rs`（code_verifier @ oauth_flow.rs:181）、
  `crates/core/src/mcp/types.rs` 已具备 PKCE + `napaxi://oauth/callback` redirect
  flow；Napaxi **单进程**——`mcp login`/`add/configure`/callback 全在同进程，
  "running Gateway = single OAuth MCP owner" 的不变量**天然成立**，不撞
  #200538。**对齐验证**：Napaxi 既有 PKCE/callback 设计方向正确。**保留 11-13
  备忘**：未来若引入并发 worker / 进程外旁路刷新，须加 state-owner 仲裁（并发旁路
  为触发条件，单进程目前不构成）。仅借鉴设计思路与边界规则，不直接移植代码。

- **#200249 簇 subagent requester-settle durable-delivery — daemon-fork 备忘**：
  OpenClaw requester wake 把 child result commit 进 parent transcript 再调 model；
  修复 turn 失败曾记 `delivery=failed/permanent_failure` 导致 broadcast/批量二次
  派发。新语义：**已 commit → 永不再 dispatch；turn answer 前失败 → delivered；
  answer 后 miss channel → 留失败；未 commit → stays owed 无 attempt limit/ladder/expiry**；
  删除 REQUESTER_SETTLE_WAKE_MAX_ATTEMPTS 重试梯 + resolveRequesterSettleRetryState
  + exhausted settle；real-Gateway proof: down 300s 下 base 失败/head 仍 delivered
  不 loop。承 #200279/#200165/#200190/#199868/#197137/#200516 同族。**Napaxi
  ground check**：`crates/` 全目录 grep
  `requester.*settle|child.*result.*commit|delivery.?state|permanent_failure|REQUESTER_SETTLE_WAKE_MAX_ATTEMPTS`
  零命中 —— inline 同步子 agent 调用，**无 requester-settle/durable-delivery
  协议，不撞**。**daemon-fork 备忘**：若未来引入 daemon-distributed subagent +
  requester transcript 持久化，须采 #200249 语义（committed=delivered、
  refused-replay、owed-uncommitted 无梯）——避免重试梯广播放大失败成 batch。仅
  借鉴设计思路与边界规则，不直接移植代码。

- **#472cd0a2 compaction 准备工作线程化 — 设计参照（async 工作线程化备忘）**：
  OpenClaw 把大型 history 准备工作拆出 Gateway 主线程（新增 compaction-preparation.ts
  +328 行、compaction-floor.ts +110/-39），避免主线程在 compaction 准备阶段被
  blocking。**Napaxi ground check**：`crates/core/src/context/` grep
  `compaction-preparation|prepare.*history|outside.*thread` 零命中 —— 单进程
  同步，**无主线程/worker 划分**，compaction 与执行同线程；"outside the Gateway
  thread" 这样的 thread 解耦对 Napaxi**不直接成立 / 不撞**。**备备忘**：若未来
  Napaxi 引入 async 工作线程，须把大型 history 准备移出执行 keypath 避免 blocking，
  与 §5 11-17 行"compaction 准备工作线程化"同处一线。仅借鉴设计思路，不直接移植代码。

- **#200539 / #200255 secrets 保留 SecretRef / redaction 不扩散明文 — 设计参照**：
  OpenClaw `skills.update` 不得用 plaintext 替换 SecretRef API key；QA live run
  配置 SecretRef 时 live run 须 fail（不准 fallback 明文）。Napaxi 已 11-12
  落地 compaction credential redaction（commit f9d43db，crates/core/src/context/
  compaction.rs summary/preview write-out paths redact credentials）。**扩展参照**：
  skills/credential 配置全路径应保留 SecretRef-not-plaintext、明文 redact；当前
  无 skills.update 同形 API 入口，**不撞**。低优先备备忘。仅借鉴设计思路，不直接移植代码。

- **restart 资源生命周期 daemon 族（#200435/#200504/#200330/#200370/#200136/#200306/#200457/#200383/#200321 等）— 归 daemon 资源退役族**：
  OpenClaw 本窗集中修：completed restart recovery input / published admission
  closures 不保留完成 work（#200435）；startup state 在 signal handlers 前释放
  （#200504）；clean exit 时释放 retained state leases（#200330）；readiness probe
  不冻结主线程（#200370）；catalog refresh 避免文件系统 stall（#200136）；缺
  store 时 first session 允许读（#200306）；Windows home 路径在 SQLite 失败报告
  redact（#200457）；PostgreSQL→SQLite 回退（#200383）；updater 拒下个 release
  （transcript worker re-emits Gateway graph）（#200321）。**Napaxi 现状**：无
  Gateway daemon restart 生命周期、无 readiness probe / catalog refresh —— 全部
  **非现状缺口**。**归 daemon 资源退役族**（承 11-12 #197230/#195369、11-16
  #199873/#7de99f0419）。详细 checklist 落于
  `docs/process-hosting-roadmap.md` §4（见下文文件 B 互锚）。本节仅作互链锚点。
  仅借鉴设计思路与边界规则，不直接移植代码。

### 11-18 新增条目（DIMA 工单 2026111800120760358）

- **#200899 — defensive-design boundary 簇第 3 对（#196065 REVERT 的正确答案形态）**：
  来源：#200899 `perf(gateway): avoid repeated session-list invalidation scans`。
  OpenClaw 11-17 REVERT 把 first-page skills-used per-chat-open full scan 撤了；
  11-18 给出正确替代 = "admission 阶段准备 list membership + invalidate selections
  lazily + 保留 immutable comparison witnesses + Float64 identity vectors 直接填
  避免 temp allocation"，并 "release invalidated selections before idle readers"
  （只 retire populated selections，保 no-next-reader 收集契约，不做重复账务）。
  **Napaxi ground check**：`crates/` grep
  `session.?list.*invalidat|membership.*admission|Float64.*ident|session.?list.?view|comparison witness`
  零命中——单进程同步 in-memory 无 session-list-view-cache / 跨进程 ready tracking，
  **不撞**。**反向验证结论**：OpenClaw 11-17 REVERT 后的正确形态 = admission-prepare +
  lazy-invalidate + immutable-witness，**反推 Napaxi in-memory 同步"按需重算、不缓存
  跨页 membership"的朴素形态 = 正确**；前两对（#196550 共享 facts、#196065 per-page
  scan）反面，本对补"若须加 session-list / membership 视图缓存，正确形态 =
  admission-prepare 而非 per-page / per-session scan"。**不须立刻改**：当前 Napaxi
  in-memory 即未加视图缓存的"朴素 = 正确"形态。**daemon-fork 备忘**：未来 daemon 化 +
  多 session stream 并发若需 session-list / membership 视图缓存，须采
  admission-prepare + lazy-invalidate + immutable-witness 形态，**不**取 11-17
  #196065 per-page full-scan 形态（与第 1 对 #196550 / 第 2 对 #196065 同簇同形态
  denial）。仅借鉴设计思路与边界规则，不直接移植代码（OpenClaw MIT vs Napaxi
  GPL-3.0-or-later，见 THIRD-PARTY-LICENSES.md）。

- **#200249 簇 subagent requester-settle durable-delivery 续修 — daemon-fork
  资源/持久族**（扩既有 §6 #200249 条目，作为续记）：11-18 第 4 窗口迭代：
  - **#200649** "stop losing finished subagent results during access-policy
    outages, steer races and expiry"：三种丢 completed child result 路径分别 fix：
    (a) access-policy outage 被记成永久 delivery failure、policy 恢复后父仍未收到；
    (b) busy parent 用 steer 接 child result、delivery owner 后续切换被记
    intentional non-delivery，父实际收了但记录说没收到、run 后续过期发误导 failure；
    (c) suspended required completion 7 天后被丢且 requester 对话里无任何 notice，
    仅 operator log 记录。某 Gateway 光 access-policy outage 一类一周 25 次失败
    child result。
  - 同簇续修：**#200823** keep subagent results owed after a Gateway restart /
    **#200873** preserve subagent results under each requester turn / **#200924**
    resume requester turns after committed subagent input / **#200760** deliver
    finished results instead of refusing on store path or operator authority /
    **#200807** fail children interrupted by a Gateway crash / **#200636** plugin
    forks read/ls/run owner exec under session policy。
  - **Napaxi ground check（11-18 重跑）**：`crates/` grep
    `subagent.*result.*persist|requester.*settle|child result.*commit|fork.*workspace|session.?fork|delivered.?to.?parent`
    零命中——inline 同步子 agent 调用，无 requester-settle / durable-delivery /
    fork-workspace 协议，本轮所有持久簇 bug 不撞。
  - **daemon-fork 备忘（续 #200249）**：若未来引入 daemon-distributed subagent，须
    同时采 (i) 11-17 #200249 committed-never-replayed 幂等铁律；(ii) 本窗 #200649
    outage / steer-race / expiry 三条 delivery correctness 边界；(iii) Gateway
    重启 / requester turn / committed input 三对 result owed 保护。一并归
    "daemon-fork resource/lifetime 持久族"备备忘。仅借鉴设计思路与边界规则，不直接
    移植代码（OpenClaw MIT vs Napaxi GPL-3.0-or-later，见 THIRD-PARTY-LICENSES.md）。

- **sandbox checkpoint lease-contention 仲裁族 — daemon-fork/sandbox 资源族备备忘**：
  来源：**#200643** `keep sandbox tools from starving behind checkpoints`
  （`local-workspace-lease.ts` +77 行 lease-contention 模型，sandbox 工具不被
  checkpoint 饿死）+ 同簇 **#200669** / **#200787** / **#200800** / **#200984** /
  **#200989** / **#201037** / **#201039**。
  - **Napaxi ground check**：`crates/` grep
    `workspace.?lease|sandbox.*lease|checkpoint.*starv|tool.?lease|workspace.?contention|lease.*contention`
    零命中——Napaxi 工具调同步路径，无 OpenClaw local-workspace-lease 模型、无
    sandbox checkpoint 对工具饿死场景，**不撞**。
  - **daemon-fork/sandbox 备备忘**：若未来 daemon 化 fork worker + sandbox 在
    fork 与 turn 间共享工作目录、引入 checkpoint 仲裁，须参照 workspace-lease
    lease-contention 模型防"工具被 checkpoint 饿死"，并落 #201039 类可观测性
    （"show what keeps sandboxes paused during publication"）记录暂停归因。归
    daemon-fork/sandbox 资源族。仅借鉴设计思路与边界规则，不直接移植代码
    （OpenClaw MIT vs Napaxi GPL-3.0-or-later，见 THIRD-PARTY-LICENSES.md）。

## 7. 许可证

OpenClaw MIT vs Napaxi GPL-3.0-or-later（见 `THIRD-PARTY-LICENSES.md`）。仅借鉴设计思路
与边界规则，不直接移植代码；升级行动项逐项记入"重新实现"清单。
