# Subtitle Quick Look

[![Build](https://github.com/zirenzhou/subtitle-quick-look/actions/workflows/build.yml/badge.svg)](https://github.com/zirenzhou/subtitle-quick-look/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

一个极简的 macOS Quick Look 扩展，让 Finder 可以用空格键以纯文本方式预览 `.vtt` 和 `.lrc` 字幕/歌词文件。

## 安装

通过 Homebrew 安装：

```bash
brew tap zirenzhou/subtitle-quick-look https://github.com/zirenzhou/subtitle-quick-look.git
brew install subtitle-quick-look
```

安装完成后，在 Finder 中选中 `.vtt` 或 `.lrc` 文件并按空格键即可。

> 仓库名称没有使用 Homebrew 默认的 `homebrew-` 前缀，因此第一次安装需要带上完整 Tap URL。之后可以正常使用 `brew upgrade subtitle-quick-look`。

## 管理扩展

安装时 Formula 会自动注册 Quick Look 扩展。也可以手动执行：

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

如果 Finder 仍显示旧的预览缓存：

```bash
subtitle-quick-look register
killall Finder
```

## 为什么里面仍有一个 `.app`？

macOS 10.15 以后使用 App Extension 提供 Quick Look 预览；扩展必须位于一个 App bundle 中。这里的宿主只是一个不可见的技术容器：

- 没有窗口或设置界面
- 没有 Dock 图标
- 不在后台常驻
- 启动后立即退出
- 不会成为 VTT/LRC 的默认打开方式

用户只需要通过 Homebrew 管理它，不需要打开这个宿主。

## 支持范围

- macOS 13 Ventura 或更高版本
- Apple Silicon 与 Intel Mac
- UTF-8、UTF-16/32、GB18030 和 Latin-1 文本
- 最大预览 8 MiB；更大的文件会显示截断提示

扩展没有网络功能。文件内容只在本机由 Quick Look 读取并转换为 UTF-8 纯文本。

## 从源码构建

需要 Xcode 15 或更高版本：

```bash
./scripts/build-release.sh
```

输出：

- `build/ManualRelease/Subtitle Quick Look.app`
- `dist/Subtitle-Quick-Look.zip`

构建脚本会生成 arm64/x86_64 通用二进制，并采用本机 ad-hoc 签名。Homebrew Formula 在本机从源码构建，因此不依赖 Developer ID 或公证下载包。

## License

[MIT](LICENSE)
