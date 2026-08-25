# DeskDaily · 桌面日程清单

一个原生 SwiftUI 编写的 macOS 桌面小部件：贴在桌面的每日任务清单，到点提醒，跨天自动刷新。纯本地运行，无任何网络请求。

![架构](https://img.shields.io/badge/platform-macOS%2013%2B-arm64) ![语言](https://img.shields.io/badge/lang-SwiftUI-indigo)

## 功能

- **多计划表**：顶部胶囊按钮切换当前执行的计划表（其余为备选）；每张表可自定义主题色（10 色调色板），切换时卡片整体换色；支持新建/重命名/删除
- **重复规则**：任务支持 仅今天 / 每天 / 每周指定几（工作日、周末或自选任意组合），按所选时区的星期自动显示与提醒
- **添加栏一步到位**：添加任务时可直接设 ⏰ 提醒时间和 🔄 重复规则，不必添加后再右键
- **悬浮置顶**（默认）：始终显示在最前的小卡片，点击打勾、滚轮滚动、按住标题区拖动均正常，兼容性最佳
- **贴附桌面**（实验性）：嵌入桌面层、只在回到桌面时可见；部分 Mac 环境下可能收不到点击，遇到请切回悬浮置顶
- **AI 规划助手**：卡片右上角 ✨ 打开对话，告诉 AI 你今天的安排，它追问目标与空闲时段后生成带提醒时间的任务清单，一键替换/追加到今日列表
- **AI 记忆**：对话记录自动保存可续聊；AI 自动从对话中提取你的习惯与偏好（长期记忆），之后每次规划自动参考，越用越懂你（⚙️ 设置 →「AI 记忆」可管理/清空/关闭）
- **每日刷新**：勾选状态按"天"归档，跨过 0 点自动重置，历史保留在数据文件中
- **连续打卡**：重复任务自动统计连续完成天数，坚持 ≥2 天标题旁亮 🔥 角标
- **统计与热力图**：点任务栏右侧「N 项」打开统计页——累计完成 / 本周完成率 / 最长连胜三张卡片 + 最近 26 周完成率热力图，可一键生成 Markdown 周报（可选 AI 点评）、导出今日清单
- **全部完成庆祝**：当天任务全部打勾时进度环脉冲 + 彩色粒子喷发 + 提示音，并展示"今日全部完成"专属祝贺卡
- **AI 睡前复盘**：设置里开启后，到点通知提醒，点「开始复盘」自动打开 AI 对话并发送今日完成情况汇总，让 AI 帮你复盘
- **时区二选一**：`跟随系统`（默认，自动读取电脑时区）/ `北京时间`（固定 Asia/Shanghai UTC+8），"今天"的边界按所选时区计算
- **日程提醒**：任务可设定提醒时间（右键任务 → 设置提醒时间），到点弹系统通知 + 音效；过期 30 分钟以上不补发
- **每天重复 / 仅今天**：添加栏的 🔄 按钮切换新任务类型；已有任务右键也能改
- 进度环实时显示今日完成度；窗口高度随任务数自适应，可拖动、可调宽度
- 支持开机自动启动（设置里开启）

## 使用

已安装于 `~/Applications/DeskDaily.app`，双击即可运行。

- 应用有 **Dock 图标**：点 Dock 图标随时把卡片唤回最前；右键 Dock 图标可退出（或卡片右上角 ⚙️ → 退出）
- **移动位置**：按住标题/空白区域拖动卡片；列表长时用滚轮或双指滑动滚动
- **首次启动**会请求通知权限，请点"允许"，否则只有音效没有横幅
- 默认预置了 5 条示例任务，可自行删除
- 数据文件：`~/Library/Application Support/DeskDaily/data.json`（想备份/迁移，拷走这个文件即可）

### 卸载

```bash
rm -rf ~/Applications/DeskDaily.app
rm -rf ~/Library/Application\ Support/DeskDaily
```

## AI 规划助手

卡片右上角 **✨** 打开对话：告诉 AI 你今天要完成什么，它会简短追问（目标、空闲时段），最后输出结构化任务清单，点「添加到今天」一键导入（含提醒时间）。

配置入口：⚙️ 设置 →「AI 助手」，填任意 OpenAI 兼容接口：

| 提供方 | 接口地址（chat/completions 完整 URL） | 模型示例 |
|---|---|---|
| 智谱 GLM | `https://api.z.ai/api/paas/v4/chat/completions` | `glm-4.6` |
| DeepSeek | `https://api.deepseek.com/chat/completions` | `deepseek-chat` |
| 本地 Ollama | `http://localhost:11434/v1/chat/completions` | `qwen2.5:7b` |

- API Key 只保存在本机 `data.json`，请求只发向你填写的接口地址
- 本地 Ollama 无需 Key（`ollama serve` 后填地址即可），完全离线
- 说明：macOS 不对第三方开放对话式 Siri，因此采用外接 API 方案；本机"零上云"可用 Ollama 替代

## 开发

```bash
./build.sh          # 编译 + 生成图标 + 打包签名 → build/DeskDaily.app
```

无 Xcode 工程，直接用 CommandLineTools 的 `swiftc` 编译。图标由 `Scripts/make_icon.swift` 用 CoreGraphics 纯代码绘制。

### 测试开关（环境变量）

| 变量 | 作用 |
|---|---|
| `DD_TIME_SHIFT_MINUTES=N` | 把"现在"向前平移 N 分钟，用于模拟跨天/到点提醒 |
| `DD_DATA_DIR=/path` | 覆盖数据目录，测试时不污染真实数据 |

例：`DD_DATA_DIR=/tmp/t DD_TIME_SHIFT_MINUTES=1500 build/DeskDaily.app/Contents/MacOS/DeskDaily`

## 更换图标

1. 用下方提示词（或你自己的）在生图模型出一张 1024×1024 图
2. 保存为 PNG 后生成 icns 并替换：

```bash
mkdir /tmp/icon.iconset
for s in 16 32 128 256 512; do
  sips -z $s $s 你的图.png --out /tmp/icon.iconset/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) 你的图.png --out /tmp/icon.iconset/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns /tmp/icon.iconset -o /tmp/AppIcon.icns
cp /tmp/AppIcon.icns ~/Applications/DeskDaily.app/Contents/Resources/AppIcon.icns
```

3. 退出并重新打开应用即可（如 Finder 里没刷新，注销重登一次）。

### 图标 AI 生成提示词

中文（即梦/通义万相等）：

> 扁平现代风格的 macOS 应用图标，圆角正方形画布，柔和的靛蓝到紫罗兰渐变背景，画面中央是一张带柔和投影的白色圆角卡片，卡片上是简洁的待办清单插画：第一行前面是填满渐变色的圆形复选框、内有白色对勾，旁边是深灰色圆角短横线表示文字；第二行是空心圆圈和浅灰色横线；卡片右下角叠放一个白色圆形小闹钟徽章，指针为靛蓝色；整体干净优雅、有轻微光泽，无任何文字，居中构图，1024×1024

英文（Midjourney/DALL·E 等，可加 `--no text`）：

> modern flat macOS app icon, rounded square, soft indigo-to-violet gradient background, a white rounded checklist card floating in the center with soft shadow, first row has a gradient-filled circular checkbox with a bold white checkmark and a dark gray pill-shaped line, second row an empty outlined circle with a lighter gray pill line, small white clock badge with indigo hands overlapping the card's bottom-right corner, clean, elegant, subtle gloss, no text, centered, 1024x1024
