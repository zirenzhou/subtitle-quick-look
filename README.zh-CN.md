# Subtitle Quick Look

[English](README.md)

一个极简的 macOS Quick Look 扩展，让 Finder 可以用空格键以纯文本方式预览 `.vtt` 字幕和 `.lrc` 歌词文件。

## Homebrew 安装

```bash
brew tap zirenzhou/subtitle-quick-look https://github.com/zirenzhou/subtitle-quick-look.git
brew trust --formula zirenzhou/subtitle-quick-look/subtitle-quick-look
brew install zirenzhou/subtitle-quick-look/subtitle-quick-look
```

Homebrew 6 要求首次安装第三方 Tap 时显式信任。这里的 `--formula` 只信任当前 Formula；如果你的 Homebrew 版本没有 `brew trust`，跳过第二条命令即可。

安装后，在 Finder 中选择 `.vtt` 或 `.lrc` 文件并按空格键。

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

- 支持 UTF-8、UTF-16/32、GB18030 和 Latin-1
- 支持 Apple Silicon 与 Intel Mac
- 没有窗口、Dock 图标、常驻进程或网络访问
- 文件完全在本机预览
- 超过 8 MiB 的文件会截断并显示提示

现代 macOS 要求 Quick Look Preview Extension 位于 App bundle 内。项目中的宿主只是不可见的技术容器，启动后会立即退出；用户不需要打开或管理它。

## 从源码构建

需要 macOS 13 或更高版本及 Xcode 15 或更高版本：

```bash
./scripts/build-release.sh
```

## License

[MIT](LICENSE)
