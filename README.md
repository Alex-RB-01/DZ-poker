# 德州扑克（蓝牙局域网 · 锦标赛盲注 · 含 AI 单机）

一款安卓优先的德州扑克小游戏：
- **单机 AI 对战**：一台手机即可玩，内置启发式 + 蒙特卡洛胜率的 AI 对手。
- **蓝牙/WiFi 局域网联机**：一机当房主跑权威牌局，其余设备通过附近发现接入；**无需互联网**。
- **锦标赛盲注**：小盲/大盲随局数（或时间）递增，可手动调整级别表与递增节奏。
- **淘汰出局**：每人初始固定筹码，筹码输完即出局，最后剩者为冠军。
- **PokerTH 风格牌桌**：椭圆绿桌、环形座位、底部操作栏、右侧式牌局日志。

> 纯虚拟筹码、仅供娱乐，不涉及任何真实货币。

---

## 📦 零基础拿到安装包（云端自动打包，不用自己装 Flutter）

你**不需要**在本机装任何开发工具。代码推到 GitHub 后，GitHub 的电脑会帮你把 App 编译成 APK，你下载安装即可。

1. **注册 GitHub 免费账号**：https://github.com/signup
2. **新建仓库**：右上角 “+” → New repository → 名字随意（如 `poker-app`）→ 选 **Public** → 不要勾选 “Add a README” → Create repository。
3. **上传代码**：进入新仓库，把 `poker_app` 文件夹里的**全部内容**（注意：是内容，不是整个文件夹）拖进网页上传区提交；或用 GitHub Desktop 拖入后 Publish。
   - 确保仓库根目录直接包含 `pubspec.yaml`、`lib/`、`.github/` 这几个。
4. **等自动打包**：进仓库 **Actions** 标签 → 看到 “Build Android APK” 任务在跑（约 5–10 分钟，绿色对勾 = 成功）。
   - 若提示 “Enable workflows” 或 “Workflows aren't enabled”，点一下启用。
   - 若构建因权限失败，到 Settings → Actions → General → Workflow permissions 选 **Read and write**，再手动重跑。
5. **下载安装**：点进那条绿色运行记录 → 底部 **Artifacts** → 下载 `poker-app-release-apk` → 得到 `app-release.apk` → 传到安卓手机 → 允许“未知来源”安装即可开桌。

> 后续每次我改完代码，你只要把新代码重新上传（覆盖），GitHub 会自动重新打包，朋友点更新就行。

---

## 一、环境准备

1. 安装 [Flutter SDK](https://docs.flutter.dev/get-started/install)（3.x，自带 Dart 3.x）。
2. 配置 Android 设备 / 模拟器（**蓝牙联机必须真机**，单机 AI 可用模拟器）。
3. 确认 `flutter doctor` 无致命报错（尤其 Android toolchain）。

## 二、初始化并运行

```bash
cd poker_app
flutter create .        # 生成 android/ ios/ 等平台目录（不会覆盖 lib/ 代码）
flutter pub get         # 拉取依赖（含 flutter_nearby_connections）
flutter run             # 连上真机/模拟器后运行
```

> 若 `flutter create .` 提示 main.dart 已存在，属正常（你的 main.dart 会被保留），直接继续即可。

## 三、Android 权限配置（蓝牙联机必需）

联机依赖 `flutter_nearby_connections`（底层 Android Nearby Connections），需要以下权限。
打开 `android/app/src/main/AndroidManifest.xml`，在 `<manifest>` 根与 `<application>` 内补齐：

```xml
<manifest ...>
  <!-- 蓝牙 / 附近设备（Android 12+） -->
  <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
  <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
  <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
  <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
  <uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
  <!-- 位置：Android 11 及以下 Nearby 定位所需 -->
  <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"
                   android:maxSdkVersion="32" />
  <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"
                   android:maxSdkVersion="32" />
  <!-- WiFi 直连（Api 33+ 热点模式） -->
  <uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES" />
  <!-- 网络（插件内部需要） -->
  <uses-permission android:name="android.permission.INTERNET" />

  <application ...>
    ...
  </application>
</manifest>
```

首次进入联机界面，若系统弹出「附近的设备 / 蓝牙 / 位置」授权，请全部允许。

> iOS 暂未适配（当前仅做安卓）。若日后要上 iOS，还需在 `ios/Runner/Info.plist` 增加
> `NSBonjourServices`、`NSBluetoothAlwaysUsageDescription`、`UIRequiresPersistentWiFi` 等键。

## 四、打包 APK 分享给朋友

```bash
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

把 `app-release.apk` 发到群里，朋友允许「未知来源」安装即可开桌。无需服务器、无需上架。

## 五、玩法

- **首页** → 选「单机对战（AI）」或「创建蓝牙房间」或「加入蓝牙房间」。
- **大厅** → 设昵称、初始筹码、盲注递增方式（按局数/按时间）与节奏、盲注级别表（可逐项改）。
- **牌桌** → 环形座位（自己永远在底部）：底池、公共牌、每人筹码/下注/状态实时可见；
  轮到谁高亮。**操作栏**：弃牌 / 跟注或过牌 / 加注（滑条 + 1/3、1/2、满池、全下快捷键）/ 全下。
  手牌仅本人可见。
- **房主等候房** → 已连入玩家列表 + AI 补位数 + 「开始游戏」。
- 一手结束自动翻牌、展示各家手牌与底池归属，约 4 秒后自动进入下一手。
- 盲注级别可随时在顶栏「时钟」按钮手动升级。

## 六、架构

```
lib/
  engine/game.dart    纯 Dart 德州扑克状态机（发牌/下注/边池/比牌/锦标赛盲注）
  engine/ai.dart      启发式 + 蒙特卡洛胜率估算的 AI 决策
  net/transport.dart  蓝牙/WiFi 直连封装（唯一接触 flutter_nearby_connections 的地方）
  net/session.dart    房主/客户端会话与 JSON 消息协议
  state/controller.dart 绑定 引擎+AI+网络+盲注计时 的总控制器
  ui/                 theme / screens（首页·大厅·加入）/ table_screen（牌桌）
  main.dart           入口
test/engine_test.dart 引擎单元测试（牌型评估、边池、流程、守恒、序列化）
```

**正确性核心**：多人不同筹码 all-in 时，`buildPots` 按投入层级自动拆分主池 + 多个边池，
谁投入谁才有资格赢对应池；含 A-2-3-4-5 轮子顺、平局分池、奇数筹码给靠按钮近者。
这些逻辑均有单元测试覆盖。

## 七、测试

```bash
flutter test
```

覆盖：7 选 5 牌型评估（同花顺/四条/葫芦/同花/顺子/两对/一对/平局、轮子顺）、
边池分层与总额守恒、整手流程与**筹码守恒**、非法动作拒绝、盲注递增、快照序列化往返、淘汰结束。

## 八、已知限制 / 后续 TODO

- 蓝牙联机眼下**未在两台真机上端到端验证**（需双真机 + 授权），网络层已按
  `flutter_nearby_connections` 官方 API 编写，如插件版本差异导致编译报错，只需改 `lib/net/transport.dart`。
- 断线处理为「该玩家自动弃牌」，未做断线重连/状态补发。
- 仅安卓；iOS 需补 Info.plist 与少量平台胶水代码。
- 防作弊未做（朋友间默认互信、房主权威即可），如需可加发牌校验。
- 美术资源为纯代码绘制（无图片资源），更接近 PokerTH 的简洁绿呢风格。

## 九、合规提醒

本作为虚拟筹码娱乐用途。若要公开发布到应用商店，请保持 UI 文案为「娱乐/练习」，
避免出现「充值、现金奖励、赌金」等字样，避免触碰真实赌博合规红线。
