# compaction deterministic floor — 升级路线图（审计基线）

> 来源：DIMA 工单 2026111100120544211（OpenClaw 巡检 2026-11-11）。
> 本文件记录 OpenClaw #197105 / #197179 的"deterministic floor"语义、Napaxi 现状基线对照、
> 以及后续精修 CR 的升级行动项。本 CR **不引入任何生产改动**，仅确立 audit baseline +
> 回归测试 + 路线图文档。

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
- **11-11 deterministic floor（拒/成两路径）**。

本 CR 只落基线 + 路线图，不动生产路径，与上述序列的"补/审"层一致。

## 6. 不在范围（workitem 已确认非缺口）

- **#196868 tool_describe default 不发 output schema**：Napaxi 工具定义静态嵌 prompt
  （`crates/core/src/tools/file/descriptors.rs` 等 const 描述），无动态 tool_describe /
  Tool-Search 按需拉取，不撞 #196868 同形问题。设计参照：若未来引入按需 tool describe，
  须默认只发 description + input schema，output schema 显式 opt-in。仅备忘，不立项。
- **#197230 reindex shadow admission 退役**：Napaxi memory 非 in-place FTS reindex 路径，
  无 SQLite 文件 lifetime admission / POSIX-lock-bound descriptor retention 概念，不构成
  现状缺口。设计参照：若 daemon 化引入 shadow/template/临时 DB 文件，须在删文件前显式
  退役 admission 避免残 inode——与 sandbox template 跨 restart 复用同族资源卫生。仅备忘。

## 7. 许可证

OpenClaw MIT vs Napaxi GPL-3.0-or-later（见 `THIRD-PARTY-LICENSES.md`）。仅借鉴设计思路
与边界规则，不直接移植代码；升级行动项逐项记入"重新实现"清单。
