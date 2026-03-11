# VoidLink tvOS 侧载与构建（Linux-only 路线）

这份文档面向“只有 Apple TV（无 Mac / 无其他 Apple 设备）”的场景：  
在 Linux 上用 GitHub Actions（macOS Runner）构建 **unsigned** 的 tvOS `.ipa`，然后通过 `atvloadly`（PlumeImpactor）在局域网内给 Apple TV 侧载并自动续签。

## 关键结论（先说清楚）

* **不能**在纯 Linux 上本地运行 `xcodebuild` 来编译 tvOS app（需要 Xcode/tvOS SDK，只能在 macOS 环境使用）。
* GitHub Actions 能构建，是因为它提供了 **macOS Runner + Xcode**。
* 你不需要在 CI 里做签名：可以先产出 **unsigned IPA**，再交给 `atvloadly` 用 Apple ID 进行签名与安装。

## 1. GitHub Actions 构建 tvOS IPA

本仓库已经提供 workflow：[.github/workflows/build.yml](../.github/workflows/build.yml)

它会产出一个 artifact：

* `VoidLink-tvOS.ipa`（tvOS）

### 推荐用法（你自己的 fork）

1. 把仓库 fork 到你自己的 GitHub 账号（这样你才能推代码、触发 Actions、拿产物）。
2. 进入你 fork 仓库的 Actions 页面，手动触发 `Build VoidLink tvOS IPA`（`workflow_dispatch`）。
3. 构建完成后，在 artifacts 里下载 `VoidLink-tvOS.ipa`。

### 备注

* tvOS 构建使用的是 `VoidLinkTV` target（`-scheme VoidLinkTV`，SDK 为 `appletvos`）。
* workflow 默认会在 `Integration` 分支 push 时自动跑；如果你不想每次 push 都跑，可以只保留 `workflow_dispatch` 触发方式。

## 2. 用 atvloadly 在 Apple TV 上侧载

`atvloadly` 是一个 Linux/OpenWrt 上的 web 服务，用 Apple ID 给 IPA 签名、安装到 Apple TV，并自动刷新避免过期。

### 2.1 前置条件

* 你的 Apple TV 和运行 atvloadly 的机器（NAS/服务器）在同一个局域网
* Apple TV 进入配对模式：`设置 -> 遥控器与设备 -> 遥控器App与设备`
* 你准备一个“专用 Apple ID”（推荐不要用常用账号），能接收 2FA 验证码

### 2.2 侧载流程（概览）

1. 打开 atvloadly 管理页面
2. 发现并配对 Apple TV
3. 添加 Apple ID
4. 上传 `VoidLink-tvOS.ipa` 并点击安装

### 2.3 免费账号限制（非常重要）

* 免费 Apple ID：最多同时激活 **3 个**侧载 app（超过会导致之前的 app 不可用）
* atvloadly 支持同时使用多个 Apple ID（可以用“多账号”策略规避 3-app 限制）

这些限制与细节请以 atvloadly 自身文档为准（它会随着苹果策略变化而变化）。

## 3. 常见问题与排障

### 3.0 电视支持 Dolby Vision / Dolby Atmos，但 VoidLink 实际能输出什么？

基于当前源码实现，VoidLink 更接近“游戏串流客户端”的能力边界：

* **视频：支持 HDR10（不是 Dolby Vision 直出）**  
  代码里 HDR 能力检测走的是 `AVPlayerHDRModeHDR10`，且解码链路会生成 HDR 的 mastering display / content light level metadata（典型 HDR10 元数据）。  
  对 Dolby Vision（动态元数据）没有看到对应的封装或输出实现。

* **音频：输出的是解码后的 PCM（可配置 stereo / 5.1 / 7.1），不是 Dolby Atmos bitstream**  
  音频从 Moonlight/Opus 解码成 float PCM，再由 `AVAudioEngine` / SDL 输出。这个路径不携带 Dolby Atmos 所需的 E-AC3 JOC / TrueHD 等 bitstream 元信息。  

* **你当前“电视光纤到回音壁”的链路通常拿不到 Atmos**  
  光纤（SPDIF）一般不支持 Atmos（即使电视和回音壁标称支持 Atmos）。很多电视也无法通过光纤透传多声道 PCM，可能会被下混到立体声或重编码为 DD5.1。  

换句话说：在你的硬件上，VoidLink 最现实的收益是 **HDR10（或被系统转换后的 HDR/DV 输出）** 与 **尽量保证稳定的音频延迟/同步**；Atmos 不是这条串流链路的重点。

### 3.1 IPA 装上去闪退

常见原因：

* IPA 需要某些付费开发者权限（CloudKit 等），免费账号签不出来
* bundle id 被 atvloadly 重写后触发了 app 内部的某些校验逻辑

VoidLink 作为串流客户端通常不应依赖 CloudKit；如果仍闪退，优先从 tvOS target 的链接库/可用 API 角度排查。

### 3.2 tvOS UI 风格（tvOS 26）

只要 UI 尽量用系统组件（UIKit/SwiftUI + Focus Engine），在 **tvOS 26.3** 上运行时会自然呈现更“新”的系统观感。  
不存在“强制切换到 tvOS26 风格”的开关。

## 4. Darling 是否有帮助？

结论：对“构建 tvOS IPA”这条主路径 **基本没帮助**。

* Darling 主要是 macOS 用户态运行时/兼容层
* tvOS/iOS 的构建链路依赖 Xcode、Apple 平台 SDK 与签名工具链
* 在 Linux 上用 Darling 跑完整的 `xcodebuild` + tvOS SDK + codesign，目前不现实且不可作为稳定方案
