# Codex Windows 急救包

当 Codex 桌面版无限重连、无法回答，CLI 也不能安装或运行救援插件时，使用这个独立急救包。

## 怎么用

1. 从 GitHub 下载最新版本 ZIP 并解压。
2. 找到 `emergency-kit` 文件夹。这个文件夹可以单独复制到桌面或 U 盘，但里面三个文件必须放在一起：
   - `README.md`
   - `Run-CodexEmergencyAudit.cmd`
   - `Start-CodexEmergencyAudit.ps1`
3. 双击 `Run-CodexEmergencyAudit.cmd`。
4. 等黑色窗口显示 `Audit complete`，再按任意键关闭。
5. 打开 Windows 当前真实桌面上的 `Codex-Emergency-Reports` 文件夹。
6. 把最新的 `Codex-Emergency-Report-日期时间.md` 发给可用的网页版 ChatGPT，让它逐项解释。
7. `Codex-Emergency-Snapshot-日期时间.json` 信息更详细，请不要公开发布；只有可信支持人员明确需要时再提供。

急救包不要求 Codex 桌面版或 CLI 能正常回答。它不会停止进程、删除文件、修改注册表或环境变量、卸载应用，也不会自动修复系统；它只创建两份经过脱敏的诊断报告。

## 0.2.0 新增检查

- 区分 Chrome 本机桥缺失、桥有效但运行后台失败、插件缓存锁定和任务策略限制。
- 提示什么时候应该使用已登录的 `@Chrome`，什么时候应该改用内置 `@Browser`。
- 只返回近期日志中的诊断信号名称和数量，不返回原始日志内容。
- 盘点会话正文旁边的任务索引和状态文件，但不读取、不复制、不合并这些文件。
- 明确说明：找到或复制 `sessions`、`archived_sessions` 只代表聊天正文获救，不保证桌面侧边栏会自动恢复。

## 如果出现 “downloaded repository is incomplete”

这说明你使用的是 2026-07-24 之前的旧版急救包。旧版错误地依赖仓库里的 `plugins` 文件夹，单独复制 `emergency-kit` 就会失败。

请重新下载 GitHub 最新版本。新版 `Start-CodexEmergencyAudit.ps1` 已包含必要的只读检查，不再需要旁边的 `plugins` 目录。

## 为什么只诊断、不自动修

脚本无法安全猜测某个代理变量、旧切换工具、第二套 CLI 或 `.codex` 目录是否仍被其他软件使用。急救包先收集证据，再由一个能正常回答的 AI 解释每项风险，并在任何修改前征求确认。

启动器绕过执行策略只对这一次 PowerShell 进程生效。脚本是普通文本，可以在运行前自行检查。
