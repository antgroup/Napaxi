# tests/device 用例格式规范

> 来源：附录 §3 不在仓内，本规范按工单 Description §1 的执行器语义反推；与 `tools/scripts/u2_runner.py` 行为对齐。
> Workitem: 2026112600120981306 · Run: aix r-1a216054664-0-d3df51a0

本骨架是 DIMA 2026112600120981306 落地的内环自测闸口用例骨架，由 `u2_runner.py` 驱动，替代 `u2_smoke.py` 的硬编码冒烟脚本。

---

## 1. 文件布局

```
tests/device/
├── schema.md            # 本文件
├── quarantine.yaml      # 隔离清单：列出 id 在执行时跳过并标 quarantined
├── cases/
│   ├── L0/
│   │   └── smoke_chat_launch.yaml
│   └── L1/
│       ├── chat_new_session.yaml
│       ├── chat_multiturn.yaml
│       └── chat_switch_engine.yaml
└── (keys.yaml)          # 预留位，详见 §9
```

- 用例路径：`tests/device/cases/<suite>/<case_id>.yaml`，其中 `suite ∈ {L0, L1}`。
- 隔离清单：`tests/device/quarantine.yaml`。
- `keys.yaml`：**不新建**于本骨架，复用 PR#150 已合入的 `examples/flutter/tests/device/keys.yaml`（见 §9）。

---

## 2. Case YAML 顶层字段

| 字段 | 必填 | 类型 | 说明 |
|---|---|---|---|
| `id` | ✔ | string | 用例唯一标识；与文件名 `<id>.yaml` 一致 |
| `suite` | ✔ | `L0` \| `L1` | 测试套；与文件所在目录一致 |
| `title` | ✔ | string | 用例标题（人类可读，便于报告展示） |
| `timeout` | ✔ | int | 单用例总超时秒数；超时即 `failure_class=env` 终止。**应 ≥ Σ 各步 timeout 之和**（否则 case 级 watchdog 会提前打断 step） |
| `steps` | ✔ | list[step] | 有序步骤列表，按顺序执行 |

例：

```yaml
id: smoke_chat_launch
suite: L0
title: 聊天主链路冒烟（12 步等价 u2_smoke.py）
timeout: 120
steps:
  - launch: { pkg: com.napa.app.test }
  - tap:    { selector: { text: ["稍后", "Later"] }, timeout: 3, optional: true }
  ...
```

---

## 3. Step 原语表

每个 step 是一个单键 dict，键名即 action，值为该 action 的参数对象。

| 原语 | 必填字段 | 可选字段 | 行为 |
|---|---|---|---|
| `launch`   | — | `pkg` (默认 `com.napa.app.test`), `timeout` (秒, 默认 60) | `app_stop`+`app_start` 然后 60s 前台守卫；+10s 后 `am start` 兜底（端口 u2_smoke.py L82-107）。**无 clearState**。 |
| `tap`      | `selector` | `timeout` (默认 15), `optional` (bool, 默认 false) | 选择器解析后 `el.click()`。`optional: true` 且元素在 timeout 内未出现 → 记一行日志并跳过本步，不抛错 |
| `set_text` | `selector`, `text` | `timeout` (默认 15), `optional` (bool, 默认 false) | 三级回退：focused.set_text → `//EditText`.set_text → `d.send_keys`（端口 u2_smoke.py L140-155）。`optional: true` 且元素未出现 → 跳过整步（不写文字、不抛错） |
| `assert_visible` | `selector` | `timeout` (默认 30), `optional` (bool, 默认 false) | 等待至元素可见，超时 → `failure_class=product`。`optional: true` 且超时未见 → 记日志并跳过，**不**翻红（与 product fail 区分） |
| `assert_absent` | `selector` | `timeout` (默认 10) | 等待至元素确认缺席；`timeout` 秒内仍出现则 product 失败。`optional` 在 absent 上无方向意义（仍`见即 fail`），4 用例未在 absent 上使用 |
| `wait`     | — | `selector`, `timeout` (默认 30), `optional` (bool, 默认 false) | 只等待不 assert；若无 `selector` 则纯 `sleep(timeout)`。`optional: true` 且 `selector` 在 timeout 内仍未见 → 记日志并跳过（非失败） |
| `back`     | — | — | `d.press("back")` |
| `press_key`| — | `keycode` (默认 111) | `d.shell("input keyevent <k>")`，111=KEYCODE_ESCAPE（hideKeyboard） |
| `screenshot`| — | `name` | 落盘到 `<out_dir>/cases/<id>.<label>.png`；失败自动调用 product/env 失败路径 |

`--list-cases` 干解析不连设备，不会触发任何 step 真跑。

---

## 4. 选择器对象 schema

```yaml
selector:
  key: chat_composer                 # 1️⃣ 优先：查 keys.yaml → descriptionMatches ^<dk>(\n.*)?$
  # 或
  text: ["稍后", "Later"]            # 2️⃣ 双语数组，逐项试 d(text=v) → d(description=v) → d.xpath('//*[@hint=v]')
  description: "dk.engine.popup.item.codex"
  textContains: "Codex"              # 子串匹配，容忍 \n<label> 后缀
  descriptionContains: "dk.engine.popup.item.codex"
  # 或
  xpath: "//android.widget.EditText"  # 3️⃣ 最后兜底
```

**优先级**：

1. `key` → `keys.yaml` 查 `dk` → `d(descriptionMatches=^<dk-escaped>(\n.*)?$)`（兼容 content-desc `dk.<key>\n<label>` 格式）；`descriptionMatches` 不支持时回退 `d(descriptionContains=dk)`，再回退 `d(description=dk)` exact；key 不在 keys.yaml → `failure_class=case`
2. `textContains` → `d(textContains=v)` 子串匹配（u2 API，容忍 `\n<label>` 后缀），`descriptionContains` 同义对 description
3. `text` 或 `description`（可单独或同时给；均为 string 或双语数组）：按出现顺序逐 variant 逐 keyword 试 `d(text=v)`/`d(description=v)`，再试 `d.xpath('//*[@hint=v]')`（端口 u2_smoke.py `_sel`）
4. `xpath` → `d.xpath(...)`

同一步里只应给一种；同时给 `key` 时优先 `key`；`textContains`/`descriptionContains` 与 `text`/`description` 互斥（同一步勿混用）。

---

## 5. `{RUN_ID}` 变量替换

- `--run-id` 默认取 `DEVPOOL_JOB_ID` 的末 8 位（短于 8 则整串），或 `local`。
- 在 `text` / `description` / 期望值字面量中，runner 执行前会做 `str.replace("{RUN_ID}", run_id)`。
- 例：`text: "MULTITURN_Q1_{RUN_ID}"` → `MULTITURN_Q1_ab12cd34`。
- `key` 与 `xpath` 不做 `{RUN_ID}` 替换（key 是固定池；xpath 由作者自管）。

---

## 6. per-case JSON 输出 schema

每用例落盘到 `<out_dir>/cases/<id>.json`：

```json
{
  "id": "smoke_chat_launch",
  "suite": "L0",
  "title": "...",
  "verdict": "passed",
  "duration": 12.3,
  "error": null,
  "failure_class": null,
  "quarantined": false,
  "screenshot": null,
  "hierarchy": null
}
```

失败时：

```json
{
  "verdict": "failed",
  "failure_class": "product",
  "error": "assert_visible selector(...) not found within 30s",
  "screenshot": "cases/smoke_chat_launch.png",
  "hierarchy": "cases/smoke_chat_launch.hierarchy.xml"
}
```

---

## 7. summary.json schema

```json
{
  "run_id": "ab12cd34",
  "suite": "all",
  "cases": [ <per-case JSON>, ... ],
  "verdict": "passed|failed|blocked",
  "exit_code": 0|1,
  "keys_yaml": "<resolved path>",
  "cases_dir": "<resolved cases dir>"
}
```

- 全部 `verdict=passed` → `verdict=passed`, `exit_code=0`
- 任一 `failed` → `verdict=failed`, `exit_code=1`
- 全部 quarantined（无 passed/failed） → `verdict=blocked`, `exit_code=1`

同时打印一行 `SUMMARY {...}` JSON 到 stdout，供 `layer3_device_regression.sh` 捕获嵌入 `android.json.cases`。

---

## 8. `failure_class` 判定表

| class | 何时触发 |
|---|---|
| `product` | 步骤 `assert_visible`/`tap`/`set_text` 等元素断言或可见性失败；`assert_absent` 仍存在 |
| `case` | YAML 语法/选择器无法解析（unknown key、step 无 action、selector 字段类型错误等） |
| `env` | 连接超时、前台守卫超时、`per-case timeout` watchdog、usb/u2 异常 |
| (不翻红) | `optional: true` 步骤的元素在 timeout 内未出现 → runner 记一行 `optional step skipped` 日志并跳过该步；不计 failure_class，case 级 verdict 不因此翻红 |

失败路径会自动 `d.screenshot()` + `d.dump_hierarchy()` 落盘到 `<out_dir>/cases/<id>.<ext>`。

---

## 9. keys.yaml 引用说明（裁断 1）

- PR#150（DIMA 2026112400120926796）已合入 `examples/flutter/tests/device/keys.yaml`，含 9 个 `dk.*` key + 2 个 popup 模板键（`dk.engine.popup.item.<engine.id>` / `dk.agent.popup.item.<agent.id>`）。
- 本骨架**不新建** `tests/device/keys.yaml`。
- `u2_runner.py` 通过 `default_keys_yaml()` 搜索顺序解析：
  1. `tests/device/keys.yaml`（未来规范位，预留）
  2. `examples/flutter/tests/device/keys.yaml`（当前已合入位）
  - 首个命中即用。
- 已登记的 `logical_name` 清单见该文件（`chat_composer`, `chat_send_button`, `session_list_button`, `chat_agent_entry`, `chat_engine_entry`, `chat_message_bubble_user`, `chat_message_bubble_assistant`, `session_item`, `session_new_button`）。
- 未来若上提到 `tests/device/keys.yaml`，runner 已优先该路径，case 文件无需改动。

---

## 10. L0/L1 分层语义

- **L0**：冒烟。覆盖 `u2_smoke.py` 12 步等价流程，验证 app 启动 + 主链路可见 + composer 输入。`smoke_chat_launch.yaml` 是 1 号用例。
- **L1**：核心旅程。多步、跨界面、状态迁移。
  - `chat_new_session`：打开会话历史 → 新建 → 进入空会话
  - `chat_multiturn`：发两条消息，确认两条用户气泡 + 至少一条助手响应
  - `chat_switch_engine`：打开 engine 选择器 → 切到非默认项 → 确认 composer 仍可输入
- L1 用例当前为**最小语义骨架**（步骤定义见附稿 §11 原文校准，TODO 在各 case 头部）。运行时允许按真实界面校准选择器，但步骤语义不变（工单原文）。
- 切换引擎 case 暂用 `description: "dk.engine.popup.item.codex"` 占位，真机校准具体 engine.id（见 `chat_switch_engine.yaml` TODO）。

---

## 红线

- `launch` 仅 `app_stop`+`app_start`，**无 `adb uninstall`/`pm clear`/`flutter clean`/清数据**。
- 失败截图/hierarchy 落 `<out_dir>/cases/`，不打包不上传。
- 隔离清单 `quarantine.yaml` 仅 `u2_runner.py` 读取；`layer3` 的 maestro 分支不读它。
