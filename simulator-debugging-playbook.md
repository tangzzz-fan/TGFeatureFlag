# Simulator Debugging Playbook

## 目标

本文档沉淀当前仓库里用于排查 **iOS Simulator 首屏白屏 / SwiftUI 构建异常 / AttributeGraph cycle** 的一套可复用方法，重点覆盖：

- **调试注入函数如何定义**
- **如何通过命令行构建、安装、启动 Example**
- **如何从模拟器抓取截图、系统日志、应用调试日志**
- **如何做 SwiftUI 视图树二分定位**

当前示例基于 `Example/TGFeatureFlagDemo`。

---

## 1. 调试注入的设计原则

### 1.1 为什么不用 `print`

当前调试方式优先使用 **HTTP 上报到本地 debug server**，而不是 `print`：

- `print` 容易被 Xcode 控制台噪音淹没
- 首屏异常时，部分生命周期日志不一定稳定可见
- HTTP 日志可落盘到 `.dbg/trae-debug-log-<session>.ndjson`，便于前后对比

### 1.2 当前使用的两个核心函数

定义位置：`Example/TGFeatureFlagDemo/TGFeatureFlagDemo/TGFeatureFlagDemoApp.swift`

```swift
@MainActor
func _dbgReport(
    _ hypothesisId: String,
    _ location: String,
    _ message: String,
    data: [String: String] = [:]
) {
    guard let url = URL(string: "http://127.0.0.1:7777/event") else { return }
    let payload: [String: Any] = [
        "sessionId": "example-white-screen",
        "runId": "post-fix",
        "hypothesisId": hypothesisId,
        "location": location,
        "msg": "[DEBUG] \(message)",
        "data": data,
        "ts": Int(Date().timeIntervalSince1970 * 1000)
    ]
    guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = body
    URLSession.shared.dataTask(with: request).resume()
}

@discardableResult
func _dbgBodyProbe(
    _ hypothesisId: String,
    _ location: String,
    _ message: String,
    data: [String: String] = [:]
) -> Int {
    Task { @MainActor in
        _dbgReport(hypothesisId, location, message, data: data)
    }
    return 0
}
```

### 1.3 两者的分工

- **`_dbgReport`**：用于 `init`、`.task`、事件回调、按钮点击、provider 回调等时机
- **`_dbgBodyProbe`**：用于 `body` 求值时机探针，解决 “`body` 被卡住但 `.task` 根本没执行” 的问题

### 1.4 为什么 `body` 里要用 `_dbgBodyProbe`

SwiftUI 在首屏异常时，常见情况是：

- `App.init` 已执行
- `WindowGroup` 已建立
- 但某个 `body` 求值阶段出现 Observation / AttributeGraph 循环
- 结果 `.onAppear`、`.task` 根本来不及执行

所以当前约定在 `body` 顶部写：

```swift
var body: some View {
    let _ = _dbgBodyProbe("B", "ContentView.swift:7", "ContentView body evaluated")

    HomeView()
}
```

这是为了确认：**该 View 的 `body` 是否真正进入求值。**

---

## 2. Debug Server 的启动方式

### 2.1 启动命令

```bash
python3 /Users/bigapple/.trae/builtin_skills/TRAE-debugger/tools/debug-server/python/debug-server.py \
  --session example-white-screen \
  --outdir .dbg \
  --clean \
  --idle 1200
```

### 2.2 产物说明

启动后会生成：

- `.dbg/example-white-screen.env`
- `.dbg/trae-debug-log-example-white-screen.ndjson`

其中 `.env` 文件会记录：

```env
DEBUG_SERVER_URL=http://127.0.0.1:7777/event
DEBUG_SESSION_ID=example-white-screen
```

### 2.3 常用清理命令

清空当前 session 的日志：

```bash
curl -s -X DELETE http://127.0.0.1:7777/logs
```

查看最近日志：

```bash
tail -n 80 .dbg/trae-debug-log-example-white-screen.ndjson
```

---

## 3. 当前仓库里实际使用的模拟器命令链路

### 3.1 查看模拟器设备

```bash
xcrun simctl list devices | rg "Booted|iPhone 16|TGFeatureFlagDemo"
```

当前排查时使用过的设备 ID：

```text
EF7E1C12-433F-4DD3-A6FA-017D75E12F52
```

### 3.2 构建 Example

```bash
xcodebuild \
  -project Example/TGFeatureFlagDemo/TGFeatureFlagDemo.xcodeproj \
  -scheme TGFeatureFlagDemo \
  -destination 'platform=iOS Simulator,id=EF7E1C12-433F-4DD3-A6FA-017D75E12F52' \
  -derivedDataPath /tmp/TGFeatureFlagDemoDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

### 3.3 终止旧进程

```bash
xcrun simctl terminate EF7E1C12-433F-4DD3-A6FA-017D75E12F52 com.tango.TGFeatureFlagDemo
```

### 3.4 安装 App

```bash
xcrun simctl install \
  EF7E1C12-433F-4DD3-A6FA-017D75E12F52 \
  /tmp/TGFeatureFlagDemoDerivedData/Build/Products/Debug-iphonesimulator/TGFeatureFlagDemo.app
```

### 3.5 启动 App

```bash
xcrun simctl launch EF7E1C12-433F-4DD3-A6FA-017D75E12F52 com.tango.TGFeatureFlagDemo
```

返回值通常会包含应用 PID，例如：

```text
com.tango.TGFeatureFlagDemo: 77502
```

### 3.6 截图取证

```bash
xcrun simctl io EF7E1C12-433F-4DD3-A6FA-017D75E12F52 screenshot .dbg/homeview-direct.png
```

这一步非常关键，用来确认：

- 真的是白屏，不是误判
- 是否已经进入目标页面
- 二分缩小后的页面是否变化

---

## 4. 如何从命令行获取模拟器内容数据

这里的“内容数据”建议分成三类看。

### 4.1 应用自定义调试日志

来源：`_dbgReport` / `_dbgBodyProbe`

查看方式：

```bash
tail -n 80 .dbg/trae-debug-log-example-white-screen.ndjson
```

适合回答的问题：

- `App.init` 有没有执行
- `App.body` 有没有执行
- `ContentView.body` 有没有执行
- 某个 `.task` / `.onAppear` 有没有触发

### 4.2 系统日志

来源：模拟器内的 unified logging

查看方式：

```bash
xcrun simctl spawn EF7E1C12-433F-4DD3-A6FA-017D75E12F52 \
  log show --style compact --last 2m \
  --predicate 'process == "TGFeatureFlagDemo" OR eventMessage CONTAINS "AttributeGraph"'
```

适合回答的问题：

- 是否出现 `AttributeGraph` / `cycle detected`
- 进程是否发生重启
- 是否有 launch hang、主线程 I/O、系统级警告

### 4.3 图片证据

来源：`simctl io screenshot`

查看方式：

```bash
open .dbg/homeview-direct.png
```

在 Trae 内部也可直接查看本地图片，以便确认视觉结果。

---

## 5. SwiftUI 首屏问题的二分定位方法

### 5.1 基本思路

对根视图做 **最小替换**，逐级确认问题落点：

1. `WindowGroup` 直接替换成极简 `ProbeRootView`
2. 如果正常，恢复 `ContentView`
3. 将 `ContentView` 从完整 `TabView` 缩成单个 tab
4. 再缩成直接 `HomeView()`
5. 在每一级的 `body` 顶部加 `_dbgBodyProbe`

### 5.2 当前项目里实际做过的缩减路径

已经走过的路径：

1. 完整 `ContentView`
2. 只保留一个 Home tab 的 `TabView`
3. `ContentView` 直接返回 `HomeView()`

这套路径的意义是判断问题到底在：

- `WindowGroup` / 环境注入
- `TabView`
- 还是 `HomeView` 首帧构建

### 5.3 判断规则

如果出现下面的证据组合：

- **截图是白屏**
- **`App init` 有日志**
- **`ContentView body` 没日志**

说明卡点在 `App` 根内容建立到首个 SwiftUI 节点求值之间。

如果出现：

- **`ContentView body` 有日志**
- **`HomeView body` 没日志**

说明问题在 `ContentView` 返回的子树内部。

如果出现：

- **`HomeView body` 有日志**
- **`.task` 没日志**

说明视图已开始求值，但在真正出现在屏幕前已卡住。

---

## 6. 当前项目里建议的注入点

### 6.1 App 入口

放在 `TGFeatureFlagDemoApp`：

- `init()`
- `var body: some Scene`
- `WindowGroup { ... }.task`

### 6.2 首屏视图

放在：

- `ContentView.body`
- `HomeView.body`
- 可疑子 View 的 `body`

### 6.3 特殊观察对象

对于下列对象要特别谨慎：

- `@Observable` 对象
- `@Environment(SomeObservable.self)` 注入对象
- `Binding(get:set:)` 中同时读服务、写服务的代码
- `value(for:)` / `isEnabled(_:)` 内部还会触发副作用的服务

---

## 7. 一套完整的复现命令顺序

建议按下面顺序执行：

```bash
# 1) 启动 debug server
python3 /Users/bigapple/.trae/builtin_skills/TRAE-debugger/tools/debug-server/python/debug-server.py \
  --session example-white-screen \
  --outdir .dbg \
  --clean \
  --idle 1200

# 2) 清空已有日志
curl -s -X DELETE http://127.0.0.1:7777/logs

# 3) 编译
xcodebuild \
  -project Example/TGFeatureFlagDemo/TGFeatureFlagDemo.xcodeproj \
  -scheme TGFeatureFlagDemo \
  -destination 'platform=iOS Simulator,id=EF7E1C12-433F-4DD3-A6FA-017D75E12F52' \
  -derivedDataPath /tmp/TGFeatureFlagDemoDerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

# 4) 终止旧进程
xcrun simctl terminate EF7E1C12-433F-4DD3-A6FA-017D75E12F52 com.tango.TGFeatureFlagDemo

# 5) 安装
xcrun simctl install \
  EF7E1C12-433F-4DD3-A6FA-017D75E12F52 \
  /tmp/TGFeatureFlagDemoDerivedData/Build/Products/Debug-iphonesimulator/TGFeatureFlagDemo.app

# 6) 启动
xcrun simctl launch EF7E1C12-433F-4DD3-A6FA-017D75E12F52 com.tango.TGFeatureFlagDemo

# 7) 看自定义调试日志
tail -n 80 .dbg/trae-debug-log-example-white-screen.ndjson

# 8) 看系统日志
xcrun simctl spawn EF7E1C12-433F-4DD3-A6FA-017D75E12F52 \
  log show --style compact --last 2m \
  --predicate 'process == "TGFeatureFlagDemo" OR eventMessage CONTAINS "AttributeGraph"'

# 9) 截图
xcrun simctl io EF7E1C12-433F-4DD3-A6FA-017D75E12F52 screenshot .dbg/latest.png
```

---

## 8. 这套方法适合排查什么问题

### 适合

- **SwiftUI 首屏白屏**
- **`AttributeGraph` cycle**
- **Observation 相关的循环依赖**
- **某个页面进入前卡死**
- **环境注入后根视图不渲染**

### 不适合

- 完全依赖真实网络、推送、蓝牙、摄像头的场景
- 必须通过 Xcode Instruments 才能定位的性能问题
- 需要线程栈 / 内存图 / Time Profiler 的复杂卡顿

---

## 9. 注意事项

- **`_dbgBodyProbe` 只用于调试期，不应长期保留**
- `location` 建议写死到文件和行号，便于日志反查
- 每次复现前最好先 `DELETE /logs`，避免新旧日志混在一起
- 如果只看截图不看日志，容易误判
- 如果只看 `log show` 不看自定义上报，无法确认业务视图具体走到哪一级
- `CODE_SIGNING_ALLOWED=NO` 对 simulator 构建更稳定，能绕开不必要的签名输入阶段

---

## 10. 建议的后续演进

可以把当前手工调试方式再封装成脚本，例如：

- `scripts/debug_example_build.sh`
- `scripts/debug_example_launch.sh`
- `scripts/debug_example_collect.sh`

这样可以把“构建 / 安装 / 启动 / 拉日志 / 截图”做成固定流程，减少人为操作误差。
