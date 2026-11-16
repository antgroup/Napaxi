# 自动化测试验收 — 运行手册与验收指南

> 面向周一验收：本文档说明各层怎么跑、证据在哪、依赖哪些待合并项。
> 目标机器：Mac mini（~/repos/Napaxi，~/testing/ 下为产物）。

## 分层结构

| 层 | 内容 | 入口 | 结果产物 |
|---|---|---|---|
| ① | flutter analyze + 单测 + 覆盖率地板 + 变更行覆盖率门禁 | `tools/scripts/layer1_gate.sh [head] [base] [threshold]` | `~/testing/results/<ts>/result.json` |
| ② | Maestro UI 冒烟（Android 模拟器 AVD `napaxi_api34`） | `tools/scripts/layer2_maestro_smoke.sh [--skip-build]` | `~/testing/results/<ts>/result.json` + JUnit XML |
| ⑥ | 编排器：①+② 串跑 + 汇总 + ACCEPTANCE 摘要行 | `tools/scripts/run_acceptance.sh [--skip-build] [--head <ref>]` | `~/testing/acceptance/<ts>/acceptance.json` |

层③（真机回归）周一与用户一起走：iPhone 已确认可长期挂载 Mac mini，届时 Android/iOS 双跑。

## 一键验收

```bash
# 合并全部依赖后，在 main 上正式跑（含完整构建，约 20-30 分钟）：
tools/scripts/run_acceptance.sh

# 快速复跑（复用已构建 APK）：
tools/scripts/run_acceptance.sh --skip-build

# 对未合并的修复分支做合并前预演：
tools/scripts/run_acceptance.sh --head origin/<branch> --skip-build
```

末尾输出 `ACCEPTANCE {"verdict":"PASS",...}` 即全绿；该摘要行可直接回传钉钉通知。

## 已验证证据（2026-11-14）

- **全绿干跑**：`~/testing/acceptance/20261114-020030/acceptance.json`
  `{"verdict":"PASS","layer1":"PASS","layer2":"PASS"}`（层①跑在 fix/stale-apk-installer-test 上）
- 层②单跑：`~/testing/results/20261113-235438/`（1/1 Flow Passed，20s）
- 层① main 首跑：`~/testing/results/20261113-181308/`（verdict=FAIL，仅陈旧测试，证明门禁会拦）

## 依赖的待合并项（全绿的前提）

| 项 | 内容 | 交付分支 / PR |
|---|---|---|
| DIMA 2026111300120601582 | 陈旧测试 `apk_installer_test.dart` 期望 map 补两键 | `fix/stale-apk-installer-test`（已预验证转绿） |
| DIMA 2026111300120602809 | #111 未编译 Kotlin 的 5 处修复 | `fix/android-plugin-compile-111` |
| PR #116 | 层①脚本（layer1_gate.sh + changed_line_coverage.py） | `feat/changed-line-coverage-gate` |
| PR #117 | 层②脚本 + Maestro 用例 | `feat/maestro-smoke` |
| PR #120 | 层⑥编排器 | `feat/acceptance-runner` |

编排器在脚本未合入 main 时会自动从 PR 分支引导，因此**验收不阻塞于 PR 合并**，只阻塞于两个 DIMA 修复（否则 main 上层①红、层②无法构建 APK）。

## 环境自愈（已内置，无需手工）

- layer2 脚本每次运行自动写入 `~/.gradle/init.d/napaxi-jvm-align.gradle`
  （强制所有 Kotlin 编译 jvmTarget=1.8，规避 Gradle 变体解析丢类）并确保
  `kotlin.jvm.target.validation.mode=warning`。
- 无设备在线时自动无头启动 AVD `napaxi_api34`。

## 已知坑（排查索引）

- main 上 `flutter build apk` 在 DIMA ...602809 合并前会编译失败 → 层②用 `--skip-build`。
- `umeng_common_sdk` 必须用 lockfile 锁定的 1.3.0（1.3.1 发布包损坏）；
  依赖变动后 `flutter pub get --enforce-lockfile`。
- Maestro 选择器看 `accessibilityText` 不看 `text`；等待用 `extendedWaitUntil`；
  导航断言用 PopupMenuButton（back 确定性关闭），不要用自定义抽屉。
