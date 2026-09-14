# DeskDaily for Windows · 技术验证

v4.0 Windows 版的第一步：技术选型评估 + 最小可运行壳（WPF / .NET 8）。

## 框架选型评估（三选一）

| 方案 | 毛玻璃卡片 | 托盘常驻 | Toast 通知 | 开机自启 | 结论 |
|---|---|---|---|---|---|
| **WPF (.NET 8)** | DWM API / 第三方库，成熟 | `NotifyIcon`（WinForms 互操作）成熟 | CommunityToolkit ToolkitNotifications 成熟 | 注册表 `Run` 键，极简 | ✅ **选定**：四项均有成熟方案，生态最大、CI 最稳 |
| WinUI 3 | Mica 原生支持 | 需 Windows App SDK 1.6+ | 原生成熟 | MSIX 打包或 workaround | 成本最高：打包链复杂、社团 CI 维护负担大 |
| Avalonia | 需第三方实验库 | 需额外适配 | 需额外适配 | 需自行实现 | 跨平台收益在本项目无场景（只做 Windows），原生体验打折 |

**决策：WPF + .NET 8。** 理由：全部目标能力（毛玻璃、托盘、Toast、自启）都有文档完善的一等方案；不需要打包成 MSIX 即可运行；`windows-latest` CI 开箱即用。

## 当前状态（最小可运行壳）

`DeskDaily.Windows.csproj` 是一个零第三方依赖的 WPF 应用：启动后显示 DeskDaily 品牌窗口。它验证了 .NET 8 + WPF 在本仓库的 Windows CI 构建链路。

运行方式（Windows 机器，需 .NET 8 SDK）：

```powershell
cd windows/DeskDaily.Windows
dotnet run
```

或从 GitHub Actions 的「Build Windows (Tech Preview)」工作流下载构建产物 Artifact。

## 后续里程碑（见 ../docs/ROADMAP.md v4.0 节）

1. 移植核心逻辑：RepeatRule / OccurrenceKit / AppDataValidator / StatsCore → C#（用 `Tests/main.swift` 用例做回归夹具）
2. 数据互通：直接读写 `data.json`（schemaVersion=2 契约），与 Mac 版互导无损
3. 功能对等第一批：任务清单 / 勾选打卡 / 多计划表 / 重复规则 / 时段提醒 / 模板
4. 托盘常驻 + Toast 提醒 + 开机自启（WPF 对应方案见上表）
