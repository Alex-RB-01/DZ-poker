# 腾讯云 CODING 持续集成构建 APK（国内，比 GitHub Actions 快）

## 前置
1. 打开 https://coding.net → 用微信/腾讯云账号登录
2. 新建项目 → 来源选「导入 GitHub 仓库」→ 填 `https://github.com/Alex-RB-01/DZ-poker` → 确认导入
   （代码已自动拉过来，不用重新上传）

## 新建构建计划
1. 项目内点「持续集成」→「创建构建计划」
2. 代码源选刚才导入的仓库；构建环境选 **Ubuntu**（或「自定义 Docker 镜像」选 `ubuntu:22.04`）
3. 流程编辑：删掉默认步骤，依次添加以下「执行脚本」步骤（每块粘一段）

### 步骤 1：安装 JDK17 + Flutter
```bash
sudo apt-get update -qq
sudo apt-get install -y openjdk-17-jdk curl unzip git python3
git clone https://github.com/flutter/flutter.git -b stable --depth 1 /opt/flutter
export PATH="$PATH:/opt/flutter/bin"
flutter config --no-analytics
flutter --version
```

### 步骤 2：生成 Android 平台目录
```bash
export PATH="$PATH:/opt/flutter/bin"
cd "$WORKSPACE"
flutter create --platforms=android .
```

### 步骤 3：注入蓝牙/邻近权限
```bash
export PATH="$PATH:/opt/flutter/bin"
cd "$WORKSPACE"
python3 - <<'PY'
p = 'android/app/src/main/AndroidManifest.xml'
s = open(p, encoding='utf-8').read()
if 'android.permission.BLUETOOTH_CONNECT' in s:
    print('权限已存在，跳过')
else:
    perms = '''
    <uses-permission android:name="android.permission.BLUETOOTH"/>
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN"/>
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation"/>
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
    <uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE"/>
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
    <uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES" android:usesPermissionFlags="neverForLocation"/>
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
    <uses-permission android:name="android.permission.CHANGE_WIFI_STATE"/>
    <uses-permission android:name="android.permission.INTERNET"/>'''
    s = s.replace('</manifest>', perms + '\n</manifest>', 1)
    open(p, 'w', encoding='utf-8').write(s)
    print('已注入权限')
PY
```

### 步骤 4：取依赖 + 构建
```bash
export PATH="$PATH:/opt/flutter/bin"
cd "$WORKSPACE"
flutter pub get
flutter build apk --release
```

### 步骤 5：收集产物（在「收集构建产物」步骤填路径）
```
build/app/outputs/flutter-apk/app-release.apk
```

4. 保存 →「立即构建」
5. 跑完在「构建产物」里下载 `app-release.apk`

> 说明：CODING 免费额度对个人够用；首次构建同样要下 Flutter，但国内源快，通常 8–15 分钟。
> 若步骤 1 的 `git clone flutter` 慢，可换成国内镜像：
> `git clone https://gitee.com/mirrors/Flutter.git -b stable --depth 1 /opt/flutter`
