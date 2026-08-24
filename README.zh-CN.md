# Subtitle Quick Look

[English](README.md) · [更新记录](CHANGELOG.md)

**一个轻量的 macOS Quick Look 字幕与歌词预览扩展，同时提供 Apple 原生翻译和字幕格式转换。支持 VTT、SRT、LRC、ASS 与 SSA。**

在 Finder 中选择字幕或歌词文件并按空格键，即可直接预览。需要时可以调用 macOS 原生翻译、批量翻译或转换字幕格式；无需 AI API、API Key、账号、常驻后台服务，也不会把字幕上传到第三方翻译接口。

## 核心特点

- **扩展 macOS 字幕与歌词预览：** 支持 WebVTT (`.vtt`)、SubRip (`.srt`)、LRC 歌词 (`.lrc`) 以及 ASS/SSA (`.ass`、`.ssa`)，并为 Finder 工作流提供共享的纯文本 (`.txt`) 解析能力。
- **Apple 原生翻译：** 自动识别来源语言、记忆目标语言，并支持简体中文与繁体中文本地转换。
- **字幕格式转换与批量处理：** 保留时间轴和字幕结构，可另存为其他格式，也可通过 Finder 服务批量处理多个文件。
- **轻量且注重隐私：** 不需要 AI API、API Key 或登录，没有 Dock 图标、自建网络服务和常驻后台进程。

## 快速开始

1. 使用下方 Homebrew 命令安装。
2. 在 Finder 中选择支持的文件并按空格键。
3. 需要翻译时点击角落按钮；需要批量操作时打开“Finder → 服务”。

## Homebrew 安装

```bash
brew tap zirenzhou/subtitle-quick-look https://github.com/zirenzhou/subtitle-quick-look.git
brew trust --formula zirenzhou/subtitle-quick-look/subtitle-quick-look
brew install zirenzhou/subtitle-quick-look/subtitle-quick-look
```

Homebrew 6 要求首次安装第三方 Tap 时显式信任。这里的 `--formula` 只信任当前 Formula；如果你的 Homebrew 版本没有 `brew trust`，跳过第二条命令即可。

目前使用的是第三方 Tap。由于安装产物是包含 Quick Look 扩展的原生 macOS App bundle，未来进入 Homebrew 官方仓库时应提交到 `homebrew/cask`，而不是 `homebrew/core`。签名、公证、预编译发行包以及官方收录门槛详见 [Homebrew 官方收录路线](docs/HOMEBREW.md)。

安装后，在 Finder 中选择支持的字幕文件并按空格键。安装和升级都会自动完成注册，通常不需要额外执行命令。

从旧版本升级到最新版本：

```bash
brew update
brew upgrade subtitle-quick-look
```

如果安装或升级后 macOS 没有立即刷新 Quick Look 或 Finder 服务，请执行 Homebrew 安装提示中给出的兜底命令：

```bash
subtitle-quick-look register
```

## Finder 服务

在 Finder 中选择一份或多份字幕，然后打开“Finder → 服务”：

- **转换字幕…**：用紧凑下拉框统一选择输出格式，在原文件旁生成新文件，不覆盖源文件。这里只改变字幕格式，不改变语言。
- **翻译文件…**：选择来源语言与目标语言；默认按语言后缀另存副本，只有勾选“替换原文件”时才以原子写入覆盖所选文件。

服务菜单和弹窗会跟随设备语言，当前支持简体中文、繁体中文、英文、日文和韩文；语言选择使用该语言自己的写法，并与 Quick Look 共用偏好。服务宿主只会在执行操作时启动，完成后自动退出。

目前入口位于“服务”，是因为 v1.2 使用 macOS `NSServices`：它天然支持 Finder 多选文件，也适合由 Homebrew 轻量注册。“快速操作”是另一种独立扩展类型，有单独的沙盒、签名、激活与启用流程；要显示在“快速操作”分组，需要另外嵌入 Action Extension，并不是把同一个菜单项换个位置。

## 扩展管理

安装时还会启用一个轻量的注册自愈任务：用户登录后以及每 15 分钟检查一次；只有发现注册缺失或旧版本冲突时才会修复。每次检查后任务立即退出，不会成为常驻后台进程。

```bash
subtitle-quick-look status       # 查看注册状态
subtitle-quick-look register     # 重新注册并刷新 Quick Look
subtitle-quick-look ensure       # 仅在注册异常时自动修复
subtitle-quick-look install-autostart # 重新启用登录注册
subtitle-quick-look unregister   # 注销扩展
```

卸载：

```bash
subtitle-quick-look unregister
brew uninstall subtitle-quick-look
brew untap zirenzhou/subtitle-quick-look
```

若 Finder 仍显示旧缓存，可执行：

```bash
subtitle-quick-look register
killall Finder
```

也可以前往“系统设置 → 通用 → 登录项与扩展 → Quick Look”，确认 **Subtitle Quick Look Preview** 已启用。

## 功能与隐私

- Apple 原生翻译，来源语言默认自动识别，目标语言默认跟随系统
- 设备第一语言的文件不会自动翻译；用户主动点击时改用单独记忆的第二翻译目标
- 源语言与目标语言一致时自动关闭翻译，并短暂提示“无需翻译”
- 翻译栏会适配较窄的 Quick Look 窗口，始终保留“另存为”入口
- 常用区最多展示 6 种系统及最近使用的语言；合并英语、繁体中文等地区重复项，语言名使用该语言自己的写法，其余折叠到“更多”
- 只翻译字幕正文，保存时保留时间轴和字幕格式
- “另存为”默认保持原始格式，也可以转换为 WebVTT、SRT、LRC 或 ASS/SSA
- Finder 服务支持多选批量转换和批量翻译
- 繁体中文与简体中文之间使用 macOS 本地系统转换，补足 Apple Translation 未开放的直接语言对
- 记忆翻译开关和语言选择
- 通过 macOS 系统“另存为”面板保存译文，并默认添加目标语言后缀
- Finder 服务可读取和翻译纯文本 `.txt`，包括 Shift-JIS 等旧编码
- 支持 UTF-8、UTF-16/32、Shift-JIS、EUC-JP、GB18030、Windows-1252 和 Latin-1
- 支持 Apple Silicon 与 Intel Mac
- 没有独立窗口、Dock 图标、常驻进程或自建网络服务
- 解析和 Apple 翻译均在本机完成
- 超过 8 MiB 的文件会截断并显示提示，同时禁用另存为

现代 macOS 要求 Quick Look Preview Extension 和 Services 位于 App bundle 内。项目中的宿主只是不可见的技术容器，仅在处理 Finder 服务时短暂运行并自动退出；用户不需要打开或管理它。

macOS 将 `public.plain-text` 固定交给系统文本预览器。第三方 Preview Extension 可以声明支持 `.txt`，但当前系统不保证将空格预览请求路由给它；因此 Shift-JIS 等旧编码 TXT 的可靠入口目前是 Finder 的“翻译文件”服务，而不是覆盖系统 TXT 预览器。

Finder 的“翻译文件”服务默认保留原文件，并用目标语言后缀另存副本；只有用户明确勾选“替换原文件”时才会覆盖。

## iOS 说明

字幕解析与转换核心仅依赖 Foundation，已经可以复用于未来的 iOS Action/Share Extension。Homebrew 无法安装或签名 iOS 扩展，因此 iOS 文件/分享菜单操作需要后续通过单独签名的 iOS 配套 App 发布，不包含在当前 macOS Homebrew 包中。

## 从源码构建

需要 macOS 15 或更高版本及 Xcode 16 或更高版本：

```bash
./scripts/build-release.sh
```

## License

[MIT](LICENSE)
