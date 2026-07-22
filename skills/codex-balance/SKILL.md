---
name: codex-balance
description: 安装、启动、停止或诊断 Codex 客户端左下角姓名旁的每周余额浮层。用户提到 Codex 余额、额度浮层、左下角余额或 codex-balance 时使用。
---

# Codex Balance

这是一个 macOS 本地只读浮层。它优先读取 CodexBar 的本地额度快照，并以 Codex 会话日志中的 `rate_limits` 作为后备；不会读取或输出 OAuth token、Cookie 或账号标识。

## 操作

从插件根目录执行：

```bash
./scripts/install.sh
./scripts/status.sh
./scripts/uninstall.sh
```

- 安装或更新后必须执行 `status.sh`，确认 LaunchAgent、进程和实时额度三项均正常。
- 诊断时先运行 `status.sh`；不要清空 Codex 会话、CodexBar 数据或登录状态。
- `uninstall.sh` 只卸载浮层及其 LaunchAgent，不移除 Codex 插件本体。
- 浮层仅在 Codex 位于前台时显示；紧凑状态无底色、描边和阴影，按 `weekly 1%` 格式融入侧栏。单击可展开详情，再次单击收起。

## 验收

实时数据检查：

```bash
"$HOME/Library/Application Support/Codex Balance/Codex Balance.app/Contents/MacOS/Codex Balance" --print
```

预期输出包含 `weekly`、`usedPercent`、`remainingPercent` 和 `resetsAt`。若当前没有额度数据，先在 Codex 中完成一次对话，再复查。
