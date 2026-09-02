# 截图与发布规范

## 目录

所有访客展示图放在：

```text
docs/assets/screenshots/
```

应用图标等通用视觉资产放在 `docs/assets/`，不要放进 `build/`。`build/` 是本地构建目录，已经被 Git 忽略。

## 推荐文件名

```text
overview-main.png
task-creation.png
tomorrow-view.png
ai-planner.png
settings-ai.png
statistics-heatmap.png
weekly-report.png
menubar-quick-actions.png
capsule-collapsed.png
focus-mode.png
notification-actions.png
backup-settings.png
```

全部使用小写英文和连字符，不使用机器名、个人姓名、日期或 `final-final` 等临时命名。

## 图片质量

- UI 和文字优先使用 PNG，不要用 JPEG 压缩文字。
- 主界面建议裁剪到应用窗口或相关桌面区域，宽度约 1600–2400 像素。
- 局部功能图建议宽度约 1200–1600 像素。
- 保留 Retina 清晰度，但单图尽量控制在 1–2 MB。
- 提交前清理 EXIF、GPS、设备信息和其他元数据。
- 每张图在展示文档中写清楚展示内容和对应版本/tag。

## 演示数据

截图必须使用专门的虚构数据，例如：

```text
今日计划
09:00 产品评审
11:00 整理研究资料
14:30 专注开发 50 分钟
18:00 运动
```

不要使用真实姓名、邮箱、客户、会议链接、内部项目名或私人日程。

## 发布前检查

逐张人工检查以下内容：

- API Key、Bearer token、密码、Cookie
- 真实姓名、邮箱、手机号和头像
- 本机用户名、绝对路径和主机名
- 真实通知、日历事件和会议链接
- 菜单栏中的账号、VPN、公司工具或同步状态
- AI 对话里的个人习惯、地址和私密文本
- JSON 备份里的任务、聊天记录和长期记忆

`settings-ai.png` 中 API Key 应使用空值或虚构占位符。不要依赖模糊处理隐藏密钥，最稳妥的是用虚构配置重新截图。

## GitHub 组织方式

截图直接随 Git 提交，README 与 `docs/SHOWCASE.md` 使用相对路径。Release 只放安装包和校验文件；如果需要分享原始高清截图，可另附 `DeskDaily-screenshots-vX.Y.zip`，但不能让 README 依赖 Release 附件才能显示图片。

## 自动渲染导出（当前采用的方式）

界面预览图由**应用自身**在演示数据模式下渲染导出——运行真实界面代码（SwiftUI 视图），使用虚构演示任务与回填的历史数据，离屏输出 2x PNG。这不是手绘 mockup，也不含任何真实个人信息：

```bash
DD_DATA_DIR=/tmp/ddshots DD_DEMO=1 DD_EXPORT_SHOTS=1 \
DD_TIME_SHIFT_MINUTES=640 DD_SHOTS_DIR="$PWD/docs/assets/screenshots" \
build/DeskDaily.app/Contents/MacOS/DeskDaily
```

- `DD_DEMO=1`：全新数据目录载入虚构演示任务
- `DD_EXPORT_SHOTS=1`：渲染 5 张界面图后自动退出
- `DD_TIME_SHIFT_MINUTES=640`：把"现在"平移到下午，让截图呈现进行中状态
- `DD_SHOTS_DIR`：输出目录

注意：如果未来 UI 有明显变化，重新运行上面的命令即可整批更新；不要在导出数据目录里放真实任务或 Key。
