# MyGestures

MyGestures 是一个面向 Apple Silicon Mac 的轻量级鼠标手势工具。它的目标很简单：按住鼠标右键画出手势，然后执行你绑定的快捷键，用来快速完成浏览器前进/后退、新建标签页、关闭标签页、窗口管理等常用操作。

这个项目最初是为了替代不再提供 Apple Silicon 原生版本的鼠标手势工具，只保留个人高频使用的核心功能。

## 特性

- Apple Silicon 原生构建，仅面向 macOS 26 及以上版本。
- 打开 App 后默认开始监听手势。
- 只使用鼠标右键作为触发键。
- 普通右键单击会正常弹出系统右键菜单。
- 按住右键拖动会进入手势模式，不弹出右键菜单。
- 支持自定义手势名称、轨迹样本和快捷键。
- 支持“任意曲线”式手势识别，同一个手势可以录入多个样本来提高容错。
- 支持撤销上一个轨迹样本、清空当前手势样本。
- 支持手势超时作废，避免误画或长时间按住右键时误执行动作。
- 支持可选的手势轨迹视觉反馈。
- 支持选择手势作用目标：
  - 鼠标指针下方的应用程序和窗口。
  - 当前活动的应用程序和窗口。
- 支持开机自动启动。
- 支持隐藏菜单栏图标，不显示 Dock 图标。
- 支持导入、导出手势配置备份。
- Event Tap 运行在独立高优先级线程上，减少主线程繁忙造成的手势延迟。

## 默认手势

| 手势 | 默认快捷键 | 用途 |
| --- | --- | --- |
| 向左 | `⌘[` | 后退 |
| 向右 | `⌘]` | 前进 |
| 向上 | `⌘T` | 新建标签页 |
| 向下 | `⌘W` | 关闭标签页 |

默认配置只是起点。你可以在设置窗口里删除、修改或重新录制这些手势。

## 权限

首次运行需要在 macOS 系统设置里授权：

```text
系统设置 -> 隐私与安全性 -> 辅助功能
系统设置 -> 隐私与安全性 -> 输入监控
```

如果右键手势没有反应，优先检查“辅助功能”权限。如果重新构建或移动了 App 路径，macOS 可能会把它当成一个新的 App，需要重新授权。

## 构建

项目使用 Swift Package Manager 和一个简单的打包脚本。

```bash
scripts/build-app.sh
```

构建产物：

```text
build/MyGestures.app
```

运行：

```bash
open build/MyGestures.app
```

长期自用时，建议把构建好的 App 放到固定位置，例如：

```text
/Applications/MyGestures.app
```

然后针对这个固定路径完成辅助功能授权和开机启动设置。

## 配置备份

设置窗口里提供：

- `导出配置`
- `导入配置`

导出的 JSON 文件包含：

- 手势名称。
- 手势轨迹样本。
- 快捷键绑定。
- 手势识别相关设置。
- 菜单栏图标和轨迹显示等 App 内偏好。

备份文件不包含 macOS 系统权限授权，也不包含开机自动启动状态。这些属于当前机器的系统设置，重装系统后需要手动重新开启。

## 项目结构

```text
Package.swift
Resources/
  Info.plist
  MyGestures.icns
Sources/MouseGestureLite/
  AppDelegate.swift
  EventTapManager.swift
  GestureRecognizer.swift
  GestureCaptureView.swift
  GestureOverlayController.swift
  GestureTargetController.swift
  LoginItemManager.swift
  Models.swift
  PermissionManager.swift
  SettingsWindowController.swift
  ShortcutRecorderView.swift
  ShortcutSynthesizer.swift
  main.swift
scripts/
  build-app.sh
```

核心模块：

- `EventTapManager`：监听并处理右键按下、拖动、松开事件。
- `GestureRecognizer`：根据录入样本识别手势。
- `ShortcutSynthesizer`：发送绑定的快捷键。
- `SettingsWindowController`：管理设置窗口、手势编辑、导入导出。
- `GestureTargetController`：决定快捷键作用于当前活动窗口还是鼠标下方窗口。

## 注意事项

- 这是一个个人使用优先的小工具，不追求完整替代大型商业鼠标手势软件。
- 当前只支持右键触发，不支持中键、左键、滚轮边缘等触发方式。
- 当前只发送快捷键，不内置复杂动作系统。
- App 使用本机 ad-hoc 签名即可自用；公开分发时需要按 Apple 的分发要求重新签名、公证。

## 紧急停止

如果测试中需要立刻退出：

```bash
pkill -x MyGestures
```

## License

当前仓库还没有选择开源许可证。正式公开前建议添加一个明确的 `LICENSE` 文件，例如 MIT、Apache-2.0 或 GPL 系列许可证。
