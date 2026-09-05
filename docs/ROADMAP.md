# DeskDaily 迭代计划

> 本文件是版本迭代的执行清单：按主题划分版本，每完成一项就勾选对应复选框并单独提交。
> 推进方式：每次只做下一项，`./build.sh` 零 error、隔离数据目录验证后提交推送；需要用户资源的事项（如真实截图）标注 🔒，由维护者配合完成。

## 已完成里程碑

- [x] v1.x–v2.2 核心功能：多计划表换肤、时段双提醒、系统级通知调度、重复规则、自然语言添加、内置模板向导、两阶段 AI 规划（对话无 JSON）、长期记忆、统计热力图、番茄钟、菜单栏/热键/迷你胶囊、Keychain、备份校验、CI/Release 流水线
- 历史版本见 [Releases](https://github.com/CDUESTC-OpenAtom-Open-Source-Club/DeskDaily/releases)

## v2.3 传播版 —— 让别人 30 秒看懂它

- [x] README 接入品牌横幅与「界面预览」区（横幅已就位）
- [x] 界面截图 5 张已生成（overview-main / ai-planner / statistics-heatmap / template-catalog / focus-mode）：由应用自身在演示数据模式下自动渲染（`DD_EXPORT_SHOTS=1`），全部为真实界面代码产出
- [x] 首次启动引导卡：三步图解（勾选任务 / 设提醒 / 拖动位置），点「开始使用」后再请求通知权限
- [x] 演示数据模式：`DD_DEMO=1` 全新启动自动载入演示任务；设置 → 数据 →「载入演示数据…」随时可换
- [x] 模板入口提升：计划表栏增加明显的「模板」按钮，新用户能发现内置模板
- [x] 版本号单一来源：设置页读取 Info.plist 版本，消除手动同步

## v2.4 时间版 —— 日程经得起真实一周

- [x] 工程安全网：RepeatRule / TaskItem.validate / AppDataValidator / AIClient 解析净化 / StatsCore 统计口径抽取为纯逻辑（`Tests/run_tests.sh`，49 项断言），CI 在构建前运行测试
- [x] occurrence 日期计算工具（OccurrenceKit：dayKey 偏移、跨日结束 endInfo/fireDate、未来日期枚举、upcomingDays，全部带测试）
- [x] 解锁跨午夜时段：`TaskItem.validate` 放开跨日（时长 ≤600 保证最多溢出次日）；结束提醒按 occurrence 起始日去重（`endRemindedDays` 键=起始日，与旧数据同键兼容）；系统日历通知经 `OccurrenceKit.fireDate` 落到次日正确时刻；任务行显示 `23:00-00:30 次日`，午夜后仍为绿色进行中、越过次日结束才转过期。已用真实时钟平移验证（昨天 23:00+90 → 今天 00:34 触发）
- [ ] 未来 7 天视图：「今天 | 明天」扩展为周条，可查看/添加未来任意一天
- [ ] 跳过单次 occurrence 与任务截止日期
- [ ] 通知调度适配 occurrence 模型（identifier 携带目标日期）

## v2.5 日历版 —— AI 知道你几点有会

- [ ] Info.plist 日历用途说明 + EventKit 授权流程
- [ ] 今日日历事件只读显示（卡片内「日程」分隔区）
- [ ] AI 规划注入日历忙闲上下文，自动避开会议时段
- [ ] 时段冲突检测纳入日历事件
- [ ] 设置页日历开关与隐私说明（只读、不上传）

## v3.0 生态版 —— 进入系统生态

- [ ] 迁移 Xcode 工程（保留 swiftc build.sh 作为兼容路径或正式切换）
- [ ] WidgetKit 通知中心/桌面小组件（只读进度 + 下一件事）
- [ ] App Intents：Siri / 快捷指令添加任务、查询今日安排
- [ ] Universal Binary（Intel Mac 支持）
- [ ] 可选：Sparkle 应用内检查更新

## v4.0 Windows 版 —— 同一份数据，双平台体验

> 在 v2.4–v3.0 迭代完成后启动。目标：Windows 用户能用上功能对等的 DeskDaily，并与 Mac 版互导数据。

### 可行性结论（2026-09 评估）

- **同套代码直接编译出 Windows 版不可行**：现有 UI 基于 SwiftUI/AppKit，通知基于 UserNotifications，密钥基于 macOS Keychain——全部是苹果平台专属；Swift 在 Windows 上虽可运行 Foundation，但没有可用的 UI 框架，生态也不成熟。
- **可行路线是“共享数据 + 移植逻辑 + 原生 UI”**：
  1. **数据格式共享**：`data.json`（schemaVersion=2）作为跨平台契约，两边互导备份无损（现有 `Tests/main.swift` 的校验用例就是契约测试，可直接移植）；
  2. **核心逻辑移植**：RepeatRule / OccurrenceKit / 校验器 / 统计口径均为纯逻辑（无 UI 依赖，v2.4 已抽取），按目标语言逐文件对照移植，共享同一组测试夹具；
  3. **UI 各平台原生**：Windows 侧候选 **C# + WinUI 3（或 WPF/Avalonia）**——毛玻璃卡片、托盘常驻、系统 Toast 通知都有成熟对应物。
- **不建议**：为跨平台用 Flutter/Compose 重写 Mac 版（现有原生体验会倒退），也不建议走 Web 壳（Electron/Tauri）——桌面常驻小卡片的内存与启动速度要求更适合原生。
- **仓库形态**：同一仓库 `windows/` 目录（优于分支——两边长期并行演进，分支会频繁冲突）；GitHub Actions 增加 `windows-latest` 构建作业。

### 任务清单

- [ ] Windows 技术验证：WinUI 3 / WPF / Avalonia 三选一（评估毛玻璃、托盘、Toast、开机自启的实现成本），产出最小可运行壳
- [ ] 移植核心逻辑：RepeatRule / OccurrenceKit / AppDataValidator / StatsCore → C#，用 `Tests/main.swift` 的用例做回归夹具
- [ ] 数据互通：Windows 版直接读写 `data.json`（同一 schemaVersion），导入/导出与 Mac 版互相无损验证
- [ ] 功能对等（第一批）：任务清单、勾选打卡、多计划表、重复规则、时段提醒（Windows Toast + 计划任务）、模板目录
- [ ] 功能对等（第二批）：统计热力图、自然语言快速添加、AI 规划（两阶段确认）、番茄钟
- [ ] Windows CI：`windows-latest` 构建 + 测试 + 打包（MSIX 或便携 zip）
- [ ] README 增加 Windows 安装说明与双平台截图
- [ ] 发布 v4.0：同一 Release 页挂 macOS DMG + Windows 安装包

## 开发范式

1. **主题驱动**：每个版本只讲一个用户故事，不合入无关改动。
2. **小步提交**：一次迭代完成清单中的一项（或拆分的子项），独立 commit + 推送；大改动先在分支验证。
3. **测试先行**：动数据模型（v2.4 起）必须先有纯 Foundation 测试再改实现；UI 改动用 `DD_DATA_DIR` 隔离启动冒烟。
4. **自动发布**：合并/提交到 main 触发 CI 构建；发版打 `v*` 标签自动生成 DMG/ZIP Release。
5. **诚实文档**：README 与 docs 只描述已实现能力；未实现项一律写在本计划的复选框里。

## 设计原则（长期有效）

- 动态效果服务于状态理解：新增淡入、删除淡出、完成庆祝一次；Reduce Motion 降级为静态。
- AI 受控：AI 是可选项，输出候选由用户确认；已完成任务、锁定时段不可被 AI 改写。
- 本地优先：任务、记忆、Key 全部存本机；云端 AI 由用户自行配置并可完全离线（Ollama）。
- 详细模板规格见 [TEMPLATES.md](TEMPLATES.md)，截图规范见 [SCREENSHOTS.md](SCREENSHOTS.md)。
