# Codex Balance

在 macOS Codex 客户端左下角、用户名旁显示每周剩余额度。

紧凑状态以 `weekly 92%` 的形式融入侧栏；单击后可查看已用比例和额度重置时间，再次单击收起。

## 特点

- 与 Codex 侧栏背景自然融合，无胶囊底色
- 自动跟随 Codex 窗口，仅在 Codex 位于前台时显示
- 优先读取 CodexBar 本地额度快照，并以 Codex 会话日志作为后备
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
  "weekly": true,
  "usedPercent": 8,
  "remainingPercent": 92,
  "resetsAt": "2026-07-29T00:25:14Z"
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
