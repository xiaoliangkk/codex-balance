# Codex Balance

在 macOS Codex 客户端左下角、用户名旁显示当前会话及每周剩余额度。

紧凑状态在最左侧窄栏纵向显示 `5h`、`7d` 的剩余额度及重置倒计时，并显示当前对话的上下文进度条；单击后可查看额度、上下文 Token 数和完整重置时间，再次单击收起。

## 特点

- 与 Codex 侧栏背景自然融合，无胶囊底色
- 自动跟随 Codex 窗口，仅在 Codex 位于前台时显示
- 优先读取 CodexBar 本地额度快照，并以 Codex 会话日志作为后备
- 从当前 Codex 会话日志读取上下文窗口占用，达到 70% 显示黄色、85% 显示红色
- 本地只读，不读取或输出 OAuth Token、Cookie 和账号标识
- 使用 LaunchAgent 自动启动

## 环境要求

- macOS
- Codex 客户端
- Xcode Command Line Tools（用于调用 `swiftc` 编译）

## 安装

```bash
git clone https://github.com/xiaoliangkk/codex-balance.git
cd codex-balance
./scripts/install.sh
```

安装完成后，打开或切换到 Codex 客户端即可看到余额。若暂时没有额度数据，请先在 Codex 中完成一次对话，然后重新检查。

## 检查运行状态

```bash
./scripts/status.sh
```

正常情况下会显示 LaunchAgent 状态、进程 PID，以及包含以下字段的实时 JSON：

```json
{
  "context": {
    "usedTokens": 111000,
    "windowTokens": 258400,
    "usedPercent": 43
  },
  "session": {
    "usedPercent": 57,
    "remainingPercent": 43,
    "resetsAt": "2026-09-01T06:04:13Z"
  },
  "weekly": {
    "usedPercent": 12,
    "remainingPercent": 88,
    "resetsAt": "2026-09-07T10:37:55Z"
  }
}
```

## 更新

```bash
git pull
./scripts/install.sh
```

## 卸载

```bash
./scripts/uninstall.sh
```

卸载脚本只移除余额浮层和对应的 LaunchAgent，不会清除 Codex、CodexBar 或登录数据。

## 说明

本项目是非官方的本地辅助工具，与 OpenAI 无隶属或背书关系。
