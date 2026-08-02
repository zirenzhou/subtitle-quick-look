# Subtitle Quick Look

[English](README.md)

一个轻量的 macOS Quick Look 扩展，让 Finder 可以用空格键预览 `.vtt`、`.lrc` 和 `.srt` 文件，并按需调用 Apple 原生翻译。

默认仍然是原生风格的纯文本预览。需要翻译时，点击角落里的翻译按钮；底部只会出现一个紧凑浮层，用于关闭翻译、选择“自动检测 → 目标语言”和保存译文。

## Homebrew 安装

```bash
brew tap zirenzhou/subtitle-quick-look https://github.com/zirenzhou/subtitle-quick-look.git
brew trust --formula zirenzhou/subtitle-quick-look/subtitle-quick-look
brew install zirenzhou/subtitle-quick-look/subtitle-quick-look
```

Homebrew 6 要求首次安装第三方 Tap 时显式信任。这里的 `--formula` 只信任当前 Formula；如果你的 Homebrew 版本没有 `brew trust`，跳过第二条命令即可。

安装后，在 Finder 中选择 `.vtt`、`.lrc` 或 `.srt` 文件并按空格键。

从旧版本升级到最新版本：

```bash
brew update
brew upgrade subtitle-quick-look
subtitle-quick-look register
```

## 扩展管理

```bash
subtitle-quick-look status       # 查看注册状态
subtitle-quick-look register     # 重新注册并刷新 Quick Look
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
- 记忆翻译开关和语言选择
- 通过 macOS 系统“另存为”面板保存译文，并默认添加目标语言后缀
- 支持 UTF-8、UTF-16/32、GB18030 和 Latin-1
- 支持 Apple Silicon 与 Intel Mac
- 没有独立窗口、Dock 图标、常驻进程或自建网络服务
- 解析和 Apple 翻译均在本机完成
- 超过 8 MiB 的文件会截断并显示提示，同时禁用另存为

现代 macOS 要求 Quick Look Preview Extension 位于 App bundle 内。项目中的宿主只是不可见的技术容器，启动后会立即退出；用户不需要打开或管理它。

## 从源码构建

需要 macOS 15 或更高版本及 Xcode 16 或更高版本：

```bash
./scripts/build-release.sh
```

## License

[MIT](LICENSE)
