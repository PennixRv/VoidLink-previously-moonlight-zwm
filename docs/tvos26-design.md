# VoidLink tvOS 26 版本 UI 与交互设计方案（Draft）

> 目标：在 **不依赖触摸/键鼠** 的前提下，让 VoidLink 在 **tvOS 26.x（Apple TV Remote + Focus Engine）** 上达到“能用且好用”的最佳实践：  
> 功能：稳定发现/配对/启动串流；  
> 性能：低延迟、硬解优先、UI 不阻塞；  
> 外观：符合 tvOS 的焦点、动效、材质与导航语义（并尽量贴近 tvOS 26 的系统风格）。

本文件聚焦 **tvOS**。iOS 继续保留在仓库里，但 **tvOS target 不应再编译/链接 iOS-only 的实现文件**（“干净构建”）。

---

## 0. 现状与差距（从“能构建”到“最佳体验”）

### 已经具备（当前 Integration 分支）

- GitHub Actions 可以产出 `VoidLink-tvOS.ipa`（tvOS-only workflow）。
- tvOS 上基础串流链路可跑通（用户已验证可用）。
- 关键输入已覆盖最小可用：触控板 `pan` 映射鼠标移动、`select` 映射左键、长按 `select` 支持拖拽；串流内 `Menu/PlayPause` 有断开/退出逻辑（待收敛）。
- 视频解码路径使用 VideoToolbox（HEVC/H.264/AV1 按硬件支持探测），并按显示能力探测 HDR10（`AVPlayer.availableHDRModes`）。

### 主要差距（按优先级）

Must（影响日常可用性）

- 主界面焦点与操作语义仍偏 “iOS 迁移版”：Host 卡片内部多个按钮，焦点导航成本很高，且不符合 tvOS “卡片为主、动作次级”的信息架构。
- “Menu/PlayPause 的按键语义”需要统一：当前串流内 `Menu=右键` 与 tvOS 的系统“返回/退出”语义有冲突风险（需要你确认最终映射）。
- tvOS target 仍编译大量 iOS-only 源文件（Settings/SceneDelegate/NativeTouch/Pencil/OSC 编辑器等），维护成本高，且容易引入 tvOS-only 构建回归。

Should（提升体验与一致性）

- Host/App 列表布局应改为 tvOS 友好的网格：DiffableDataSource + CompositionalLayout，并带标准 focus 动效（scale + shadow + parallax）。
- 上下文动作（Wake/Pair/Delete/Stream Desktop 等）应从“卡片内按钮”迁移为“长按/更多菜单”。
- 串流内应提供 tvOS 友好的 Overlay（HUD/快捷键/退出确认/统计）而不是依赖 iOS Toolbox/OSC 编辑器。

Could（锦上添花）

- “Liquid Glass”模式（`GenericUtils.liquidGlassEnabled`）下的材质/阴影/圆角策略细化。
- “最近使用的主机/应用”与“继续上次串流”入口。
- 更完整的低延迟音频参数与多声道提示。

---

## 1. tvOS 交互模型（必须遵循的底层规则）

### 1.1 Focus Engine

tvOS UI 的核心不是“触摸点”，而是 **Focus（焦点）**：

- “可交互”元素必须能成为焦点：`canBecomeFocused = true`（或使用默认可聚焦控件）。
- 焦点移动应是可预期的：避免一个卡片里堆 4 个按钮导致焦点陷阱。
- 页面切换后要把焦点落到正确区域：`preferredFocusEnvironments / setNeedsFocusUpdate / updateFocusIfNeeded`。
- 对于跨区域跳转（例如：顶部工具栏 ↔ 网格内容），用 `UIFocusGuide` 明确引导。

参考：

- `ATV-Bilibili-demo/BilibiliLive/Component/View/BLMotionCollectionViewCell.swift`：焦点 scale/shadow/parallax 的基类实现。
- `ATV-Bilibili-demo/BilibiliLive/Component/View/UpSpaceTitleSupplementaryView.swift`：`UIFocusGuide` 跨区引导示例。

### 1.2 Remote presses（按键语义）

推荐把遥控器按键当成“模式切换/上下文操作”，而不是“鼠标键盘替代”：

- `Select`：主动作（Primary Action）。
- `Menu`：返回上一级或退出（系统语义强）。需要谨慎拦截，尤其是在非全屏播放/串流场景。
- `Play/Pause`：适合作为“次级动作”或“快捷动作”（例如刷新、呼出 overlay、右键等）。
- 长按：上下文动作（类似“更多”）。

参考：

- `ATV-Bilibili-demo/BilibiliLive/Component/View/BLButton.swift`：`pressesEnded(.select)` 触发 `.primaryActionTriggered` 的模式。
- `ATV-Bilibili-demo/BilibiliLive/Module/Tabbar/BLTabBarViewController.swift`：`playPause` 用作“刷新”。
- `AngelLive/TV/AngelLiveTVOS/Other/ContentView.swift`：SwiftUI 的 `.onPlayPauseCommand`。

### 1.3 手势（触控板）

串流内可以把触控板手势映射为鼠标/滚轮，但在“主界面”要优先保证 focus 导航：

- 主界面：尽量不要依赖 pan 来滚动，而是让 `UICollectionView` 的 focus 滚动自动生效。
- 串流内：`UIPanGestureRecognizer` → 鼠标移动是合理的；再通过按键切换“鼠标滚轮模式/右键模式”能显著提升可用性。

---

## 2. VoidLink tvOS 信息架构（页面树与导航）

目标是把“主界面”做成 tvOS 友好的卡片化结构，串流作为全屏沉浸态：

### 2.1 页面树（建议）

- Hosts（主页面）
- Apps（某个 Host 下的应用页）
- Streaming（全屏串流）
- Settings（tvOS 设置入口，不做 iOS 那套侧滑 settings VC）
- About / Help（少量说明，主要放在 docs）

现有代码映射：

- Hosts/App：`MainFrameViewController` + `HostCollectionViewController` + `UIAppView`
- Streaming：`StreamFrameViewController` + `StreamView` + `StreamManager`

### 2.2 导航规则

- Hosts → Apps：Select 进入（不建议直接开串流，避免误触）。
- Apps → Streaming：Select 启动串流。
- Menu：返回上一级（Apps→Hosts，Streaming→Apps/Hosts，视你确认）。

---

## 3. 遥控器映射（建议方案，需要你确认）

这里是最关键的“tvOS vs iOS”差异点，我建议先确定映射再写代码，否则会反复推倒。

> ✅ 已确认（2026-03-11）：
> - 串流内：`Play/Pause = 右键`，`Menu = 返回/呼出 Overlay`
> - Hosts 页：`Select` 进入 Apps 列表
> - 视觉第一版“克制一些”，后续逐步增强动效与质感

### 3.1 主界面（Hosts/Apps）

- Select：主动作（进入/启动）。
- 长按 Select：打开“动作菜单”（Wake/Pair/Delete/Stream Desktop/Show Details）。
- Play/Pause：刷新（重新 discovery / 重新拉 applist）或打开“Quick Actions”。
- Menu：返回上一级（遵循系统直觉）。

### 3.2 串流内（Streaming）

现状：`Menu=右键`，`双击Menu=退出`，`Play/Pause=断开`。

最终建议（更贴合 tvOS 系统语义，且已确认）：

- 触控板 Pan：鼠标移动（已实现）。
- Select Click：左键（已实现）。
- Long-press Select：左键按住拖拽（已实现）。
- Play/Pause：右键（Right Click）。
- Menu：呼出“串流 Overlay”（或在 Overlay 打开时关闭 Overlay）。Overlay 内提供 Disconnect/Send Keys/Stats 等能力。

---

## 4. 视觉与组件（对标 ATV-Bilibili-demo，适配 tvOS 26）

### 4.1 视觉原则

- 尽量“跟随系统”：优先用 `TVUIKit`、系统 SF Symbols、系统材质（blur/material），让 tvOS 26 风格自然继承。
- Focus 动效必须统一：同一套 scale/shadow/parallax 参数贯穿 Host 卡片、App 卡片、按钮。
- 减少纯黑大平面：使用轻微渐变、噪声、或者模糊层提升“电视观感”。

项目内已有开关：

- `GenericUtils.liquidGlassEnabled`：当 `#available(iOS 26.0, tvOS 26.0, *)` 且未要求兼容模式时启用。  
  建议把它当成“新视觉模式开关”，用于调整圆角、材质、阴影强度与间距。

### 4.2 核心可复用组件（建议实现）

- `TVFocusableCard`（或基类 cell）
  - 行为：`didUpdateFocus` 时 scale + translate + shadow + motion effects。
  - 参考：`BLMotionCollectionViewCell.swift` / `BLButton.swift`。

- `TVPrimaryButton`
  - 行为：`pressesEnded(.select)` → `.primaryActionTriggered`，并在 focus 时切换图标/文字颜色。
  - 参考：`BLButton.swift`。

- `TVActionMenu`（轻量 overlay）
  - 行为：长按 Select 打开；Select 执行动作；Menu 关闭。
  - 风格：半透明材质 + 大按钮 + 聚焦动效。
  - 参考：AngelLive `ultraThinMaterial` 视觉方向（SwiftUI），UIKit 可用 `UIVisualEffectView` 近似。

---

## 5. 功能设计（tvOS-only 取舍）

### 5.1 Host 卡片（建议字段）

- Host 名称
- 在线状态（在线/离线/未知）
- 配对状态（已配对/未配对）
- 最近使用时间（可选）
- 主动作（Select）：进入 Apps
- 长按动作菜单：
  - Wake-on-LAN
  - Pair / Unpair（如支持）
  - Edit（手动 IP、删除）
  - Stream Desktop（快捷开桌面）

### 5.2 App 网格

- 网格布局建议 CompositionalLayout，支持不同密度（1080p/4K）。
- App 卡片：
  - boxart（已有 `UIAppView` 缓存逻辑，可复用）
  - focus 时放大 + parallax（可用 `adjustsImageWhenAncestorFocused` + 自定义 shadow）
- 长按：
  - Hide/Unhide
  - Quit App（如果 host 支持）
  - Stream Desktop

### 5.3 串流 Overlay（关键）

串流是“沉浸态”，但 tvOS 没键盘鼠标，Overlay 必须承担“补足输入”的职责：

- Disconnect / Back
- Toggle Stats（码率/丢包/延迟/解码帧率）
- Send Keys（Esc/Tab/Alt+Tab/Ctrl/Win 等常用键组合）
- Mouse Mode（可选）
  - Normal：pan=移动鼠标
  - Scroll：pan=滚轮（按住某键切换）
- Audio/Video Quick Settings（只读或少量可调）

---

## 6. 性能与媒体能力（面向你当前硬件）

### 6.1 视频

现有代码已做：

- VideoToolbox 硬解探测（HEVC/H.264/AV1）
- HDR10 探测（`AVPlayer.availableHDRModes`）

建议策略（tvOS 端）

- 以 HEVC 为默认优先（如果服务端支持），HDR 场景优先 Main10。
- YUV444 仅在明确需要时启用（对带宽/解码/渲染都更重）。
- UI 线程绝对不能做重活：boxart 解码、网络请求、日志拼接要异步。

### 6.2 音频

- VoidLink 通过 `AVAudioSession.maximumOutputNumberOfChannels` 做 2/5.1/7.1 探测，这个方向正确。
- 你的实际链路是 Apple TV → HDMI → TV → 光纤 → Soundbar：  
  光纤通常无法承载 Atmos；多声道是否保留取决于 TV 的透传/转码策略。  
  因此“能稳定输出 5.1 PCM/AC3”比追求 Atmos 更现实。

---

## 7. tvOS-only “干净构建”实施计划（分阶段）

### Phase 1：只做 Target 清理（不改行为）

目标：`VoidLinkTV` target 的 **Sources TV** 不再编译这些明显 iOS-only 文件：

- `SettingsViewController.m`
- `SWRevealViewController.m`
- `SceneDelegate.m`（以及重复的 build file 引用）
- `NativeTouchHandler.m` / `NativeTouchPointer.m` / `PureNativeTouchHandler.m`
- `PencilHandler.swift`
- `TouchPadGestureHandler.swift`
- `OrientationHelper.swift`
- tvOS 不会走到的 Toolbox/OSC 编辑器 UI：
  - `ToolboxViewController.swift`
  - `LayoutOnScreenControlsViewController.m`
  - `OSCProfilesTableViewController.m`
  - `ProfileTableViewCell.m`
  - `WidgetPanelStackView.m`
  - `MenuSectionView.m`
  - `ToolBarContainerView.m`

验收：

- GitHub Actions `Build VoidLink tvOS IPA` 仍成功产出 `VoidLink-tvOS.ipa`

### Phase 2：重做 Hosts/App 的 tvOS UI（聚焦 + 动效）

目标：把 Host 卡片从“卡片内多按钮”迁移为“单卡片 + 长按菜单”，并统一 focus 动效。

### Phase 3：串流 Overlay + 遥控器映射收敛

目标：明确 `Menu/PlayPause` 行为，并提供 Overlay 入口。

### Phase 4：性能与媒体调优

目标：稳定 4K60（视设备/网络/服务端而定），避免 UI 掉帧，提升 HDR/多声道表现的可预期性。

---

## 8. 已确认事项（2026-03-11）

- 串流内：`Play/Pause = 右键`，`Menu = 返回/呼出 Overlay`
- Hosts 页：`Select` 进入 Apps 列表
- 视觉第一版“克制一些”，后续逐步增强动效与质感
