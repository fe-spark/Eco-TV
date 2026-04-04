# EcoTV

一款基于 Flutter 的视频播放应用，追求轻量、流畅与易部署。

[![Dart](https://img.shields.io/badge/Dart-3.10.4-blue?logo=dart&logoColor=white)](https://dart.dev)
[![Flutter](https://img.shields.io/badge/Flutter-3.38.5-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![FVM](https://img.shields.io/badge/FVM-Enabled-orange?logo=google&logoColor=white)](https://fvm.app)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## 功能特性

- Flutter 跨平台：支持 Android 和 iOS
- 自定义数据源接入：可配合 [EcoHub](https://github.com/fe-spark/EcoHub) 使用
- 播放器手势支持：亮度、音量、快进快退、倍速等
- 投屏支持：iOS AirPlay / Android DLNA

## 版本与环境要求

- Flutter: `3.38.5`（项目通过 `.fvmrc` 固定）
- Dart: 随 Flutter `3.38.5`
- Android: Android SDK（本机可用）
- iOS（仅 macOS）: Xcode + Command Line Tools + CocoaPods

## 快速开始

### 1) 安装并使用 FVM（推荐）

```bash
brew install fvm
fvm install
fvm use
```

建议后续统一使用：

```bash
fvm flutter ...
fvm dart ...
```

如果有以下提示：

`Legacy environment variables detected: FVM_HOME`

请将环境变量迁移为 `FVM_CACHE_PATH`（例如在 `~/.zshrc`）：

```bash
# 旧配置（删除）
# export FVM_HOME=...

# 新配置
export FVM_CACHE_PATH="$HOME/fvm"
```

### 2) 拉取依赖与生成代码

```bash
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
```

## 本地必须修改项

### Android: `android/local.properties`

`android/settings.gradle.kts` 会强依赖 `local.properties` 中的 `flutter.sdk`，未配置会报错。

创建或修改 `android/local.properties`：

```properties
# 改成你的 Android SDK 实际路径
sdk.dir=/Users/your-name/Library/Android/sdk

# 推荐使用项目内 FVM 软链接
flutter.sdk=../.fvm/flutter_sdk
```

说明：

- `android/local.properties` 已被 `.gitignore` 忽略，不会提交
- 若不使用 FVM，可将 `flutter.sdk` 改为本机 Flutter 绝对路径

### iOS: CocoaPods（macOS 必需）

若缺失 CocoaPods，运行 iOS 会报：`CocoaPods not installed`。

```bash
xcode-select --install
brew install cocoapods
pod --version
pod setup
```

项目内执行：

```bash
fvm flutter pub get
cd ios && pod install --repo-update
cd ..
```

## 运行项目

```bash
fvm flutter run
```

## 构建

### Android

```bash
fvm flutter build apk --release
```

### iOS（Unsigned）

```bash
fvm flutter build ios --release --no-codesign
```

## 常见问题

### 1) `flutter.sdk not set in local.properties`

检查并补全 `android/local.properties` 中的 `flutter.sdk`。

### 2) `CocoaPods not installed or not in valid state`

先安装 CocoaPods，再执行：

```bash
cd ios && pod install --repo-update
```

### 3) 依赖版本有 newer incompatible 提示

这是版本约束提示，不一定是错误。可用以下命令查看详情：

```bash
fvm flutter pub outdated
```

## 数据源说明

本项目不存储任何视频数据，仅提供播放器能力。

- 默认服务: https://eco.fe-spark.cn
- API: `https://eco.fe-spark.cn/api`
- 稳定自建建议: [EcoHub](https://github.com/fe-spark/EcoHub)

## 免责声明

1. 项目仅用于学习交流，禁止用于商业用途
2. 数据来自公开网络接口，开发者不提供版权担保
3. 如涉及权益问题，请联系维护者处理
