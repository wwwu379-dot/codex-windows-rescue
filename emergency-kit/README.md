# Codex Windows 急救包

当 Codex 桌面版无限重连、完全无法回答，CLI 也不能安装或运行救援插件，甚至这台电脑暂时连不上外网时，使用这个独立急救包。

它不依赖 Codex 桌面版、CLI、插件仓库或外网。三个文件放在同一个文件夹里即可离线运行：

- `README.md`
- `Run-CodexEmergencyAudit.cmd`
- `Start-CodexEmergencyAudit.ps1`

## 怎么用

1. 双击 `Run-CodexEmergencyAudit.cmd`。
2. 等黑色窗口显示 `Audit complete`，再按任意键关闭。
3. 打开 Windows 当前真实桌面上的 `Codex-Emergency-Reports` 文件夹。
4. 先打开最新的 `Codex-Emergency-Report-日期时间.md`。它是本地可读摘要，即使当前不能访问外网也能查看。
5. 如果这台电脑仍不能联网，可用手机、U 盘或局域网把 Markdown 报告转到另一台能访问网页版 ChatGPT 的设备，再让它逐项解释。
6. `Codex-Emergency-Snapshot-日期时间.json` 更详细，请不要公开发布；只在可信支持人员明确需要时提供。

急救包不会停止进程、删除文件、修改注册表或环境变量、卸载应用，也不会发起任何网络请求。它只创建两份经过脱敏的诊断报告。

## 0.3.0 新增检查

- 优先比较 Windows 系统代理、进程/用户代理变量与本地实际监听端口。
- 识别“配置仍指向旧端口”“多个地方使用了不同端口”等端口漂移信号。
- 明确提醒检查魔法工具的随机混合端口；不会擅自读取或修改魔法工具配置。
- 把无限重连拆成端口错位、HTTPS 正常但 WebSocket 失败、客户端状态竞争、版本不匹配等不同问题，不再一上来就建议 TUN、全局模式、DNS 或重装。
- 只检查 `.codex\.env` 是否存在，不读取内容，也不假设当前 Codex 一定会自动加载它。

## Chrome 与会话检查

- 区分 Chrome 本机桥缺失、桥有效但运行后端失败、插件缓存锁定和任务策略限制。
- 提示什么时候使用已登录的 `@Chrome`，什么时候使用内置 `@Browser`。
- 盘点会话正文旁边的任务索引和状态文件，但不读取、复制或合并这些文件。
- 找到或复制 `sessions`、`archived_sessions` 只代表聊天正文获救，不保证桌面侧边栏自动恢复。

## 如果出现 “downloaded repository is incomplete”

这说明使用的是 2026-07-24 之前的旧急救包。旧版错误地依赖仓库里的 `plugins` 文件夹，单独复制 `emergency-kit` 会失败。

请重新下载 GitHub 最新版本。新版急救包已经完全自包含。

## 为什么只诊断、不自动修

同样的“重新连接”可能来自完全不同的层：端口变化、WebSocket 代理继承、应用状态同步、远程环境或客户端版本。急救包先在离线条件下收集证据，再让用户一次只改一个明确项目。

看到 `proxy-endpoint-not-listening` 或 `mixed-endpoint-configuration` 时，第一步应比较 Windows 系统代理端口和魔法工具当前真实监听端口。若随机端口让它们错位，统一到同一个固定端口并验证；不要同时改 TUN、DNS、缓存和系统代理。

启动器绕过执行策略只对这一次 PowerShell 进程生效。脚本是普通文本，可以在运行前自行检查。
