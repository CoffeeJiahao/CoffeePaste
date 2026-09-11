# 开发 macOS 应用注意事项

本文适用于普通 App、菜单栏 App、后台工具，以及需要辅助功能、输入监控等权限的 macOS 项目。

## 1. 应用身份必须稳定

macOS 会使用以下信息识别应用：

- `CFBundleIdentifier`
- 签名证书与 Team ID
- Designated Requirement
- 应用安装路径
- 部分场景下的启动来源

发布或长期安装后，不要随意修改 Bundle ID、签名方式或 Team ID。否则系统可能把新构建视为另一个应用，导致以下状态失效：

- 辅助功能权限
- 输入监控权限
- 通知权限
- 登录项
- 菜单栏显示许可
- 钥匙串访问
- Apple Events 自动化权限

检查身份：

```bash
codesign -dv --verbose=4 /Applications/YourApp.app
codesign -d -r- /Applications/YourApp.app
```

## 2. 避免长期使用 ad-hoc 签名

`CODE_SIGN_IDENTITY=-` 是 ad-hoc 签名，适合一次性本地调试，不适合反复覆盖安装需要系统权限的应用。

ad-hoc 签名的 Designated Requirement 通常依赖代码哈希。代码变化后，系统可能认为应用身份发生变化。

推荐：

1. 开发阶段使用稳定的 `Apple Development` 证书。
2. 分发阶段使用 `Developer ID Application` 并完成 notarization。
3. CI 和本机构建使用相同的 Bundle ID、Team ID 和签名策略。

检查可用证书：

```bash
security find-identity -v -p codesigning
```

验证签名：

```bash
codesign --verify --deep --strict --verbose=2 YourApp.app
spctl --assess --type execute --verbose=4 YourApp.app
```

## 3. 不要直接运行 App 包内的二进制

最终验收时不要这样启动：

```bash
./YourApp.app/Contents/MacOS/YourApp
```

特别是在 macOS 26 及更高版本中，直接执行二进制可能让系统把菜单栏项或权限请求归因到 Terminal、IDE 等宿主进程。

推荐通过 Finder、Spotlight、Dock 或 Launch Services 启动：

```bash
open /Applications/YourApp.app
```

对于菜单栏应用的安装脚本，macOS 26 上可优先让 Finder 发起启动：

```bash
osascript - "/Applications/YourApp.app" <<'APPLESCRIPT'
on run argv
    tell application "Finder" to open (POSIX file (item 1 of argv) as alias)
end run
APPLESCRIPT
```

不要把直接执行 `Contents/MacOS/...` 的结果当作最终权限或菜单栏行为的验收依据。

## 4. 菜单栏应用必须正确配置 NSStatusItem

菜单栏应用通常设置：

```xml
<key>LSUIElement</key>
<true/>
```

这意味着应用不会显示 Dock 图标，也不一定存在主窗口。必须确保状态项始终被强引用：

```objc
@property (nonatomic, strong) NSStatusItem *statusItem;
```

创建后设置稳定且唯一的 `autosaveName`：

```objc
self.statusItem = [[NSStatusBar systemStatusBar]
    statusItemWithLength:NSSquareStatusItemLength];
self.statusItem.autosaveName = @"com.example.app.main-status-item";
self.statusItem.visible = YES;
```

注意：

- 不要每次刷新菜单时销毁并重建状态项。
- 不要使用 `Item-0`、`Item-1` 之类匿名身份。
- 同一应用有多个状态项时，每个 `autosaveName` 必须唯一。
- 图标应使用 template image，以兼容深色和浅色菜单栏。
- 状态项和菜单必须在主线程创建、更新。

## 5. macOS 26 的菜单栏允许列表

macOS 26 由 Control Center 统一管理第三方菜单栏项。应用进程正常运行，并不代表图标真正显示。

典型异常：

- `NSStatusItem.isVisible == YES`
- 状态项 button 和 image 均存在
- 进程没有崩溃
- 用户仍看不到菜单栏图标

检查 Control Center 日志：

```bash
log show --last 10m --style compact \
  --predicate 'process == "ControlCenter" AND eventMessage CONTAINS[c] "YourApp"'
```

重点关注：

```text
Moving host to blocked list
Starting to track blocked host
Created ephemaral instance
```

恢复步骤：

1. 打开“系统设置 > 菜单栏”。
2. 在“允许在菜单栏中显示”区域找到应用。
3. 将开关关闭后重新开启。
4. 退出应用。
5. 通过 Finder 或 Spotlight 重新启动。

打开菜单栏设置：

```bash
open 'x-apple.systempreferences:com.apple.ControlCenter-Settings.extension'
```

不要直接修改 Control Center 的受保护 plist。应用不应尝试绕过用户的菜单栏显示选择。

## 6. 不能只依赖 isVisible 判断菜单栏状态

在 macOS 26 上，`isVisible` 可能只表示应用请求显示，而不是 Control Center 已实际渲染。

诊断时还应检查状态项窗口：

```objc
NSWindow *window = self.statusItem.button.window;
NSRect frame = window.frame;
BOOL windowVisible = window.isVisible;
BOOL onscreen = (window.occlusionState & NSWindowOcclusionStateVisible) != 0;
```

多显示器环境下，不能简单用 `frame.origin.x < 0` 判断离屏。显示器可以位于主屏左侧或下方。正确判断方式是检查状态项窗口是否与任意 `NSScreen.frame` 相交。

## 7. 菜单栏应用应处理“再次打开”

因为没有普通窗口，用户重复双击应用时可能认为“没有打开”。可在重新打开时弹出状态菜单：

```objc
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender
                    hasVisibleWindows:(BOOL)hasVisibleWindows {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.statusItem.button performClick:nil];
    });
    return YES;
}
```

这不能代替菜单栏可见性修复，但能避免应用已运行时完全没有反馈。

## 8. TCC 权限不能由应用静默授予

辅助功能、输入监控、屏幕录制、自动化等权限由 TCC 管理。

注意：

- 修改 Bundle ID 或签名身份后，通常需要重新授权。
- 覆盖安装前后应保持相同的 Designated Requirement。
- 不要在安装脚本中修改 TCC 数据库。
- 不要随意执行 `tccutil reset`，它会删除用户现有授权。
- 权限失败时应提供明确入口，让用户进入对应的系统设置页面。

辅助功能设置：

```bash
open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'
```

输入监控设置：

```bash
open 'x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent'
```

## 9. 安装脚本的正确顺序

推荐顺序：

1. 完整构建并验证新产物。
2. 验证签名和 Bundle ID。
3. 请求旧进程退出并等待退出完成。
4. 将新 App 复制到同一文件系统中的临时路径。
5. 原子替换 `/Applications/YourApp.app`。
6. 通过 Finder 或 Launch Services 启动。
7. 确认进程、签名和菜单栏状态。

不要先删除旧应用再开始构建。构建失败会让用户失去可用版本。

不要在旧进程运行时直接覆盖其 App Bundle。

## 10. macOS 自带 Bash 是 3.2

安装脚本不要假设存在新版 Bash 功能。

常见问题：

- `set -u` 下展开空数组可能报 `unbound variable`。
- 不支持关联数组。
- 不支持 `mapfile`。
- 不要依赖 Homebrew Bash 路径。

优先使用显式分支：

```bash
run_privileged() {
    if [[ "$needs_sudo" == true ]]; then
        sudo "$@"
    else
        "$@"
    fi
}
```

至少执行以下检查：

```bash
/bin/bash -n build.sh install.sh
shellcheck build.sh install.sh
```

如果本机没有 `shellcheck`，至少完成 `bash -n` 和一次真实构建。

## 11. 私有 API 的边界

使用未公开的 macOS API 时必须明确：

- 可能随系统版本变化。
- 无法通过 Mac App Store 审核。
- 应在运行时检查符号是否存在。
- 缺少符号时必须安全降级，不能启动即崩溃。
- 发布前必须覆盖当前系统和最低支持系统测试。

优先通过 `dlsym` 解析私有符号，避免系统移除符号时由动态链接器直接终止应用。

## 12. 发布前检查清单

- [ ] Bundle ID 与上一版本一致。
- [ ] Team ID 与签名证书一致。
- [ ] Designated Requirement 稳定。
- [ ] 构建产物包含预期架构。
- [ ] `codesign --verify --deep --strict` 通过。
- [ ] 通过 Finder 启动，不直接执行包内二进制。
- [ ] 菜单栏状态项设置唯一 `autosaveName`。
- [ ] 菜单栏图标在浅色、深色模式下均可见。
- [ ] 单屏和多屏环境均测试。
- [ ] 辅助功能和输入监控权限重新验证。
- [ ] 覆盖安装不会丢失配置。
- [ ] 安装失败时旧版本仍可恢复。
- [ ] 安装脚本通过 macOS `/bin/bash` 语法检查。
- [ ] 检查最近的崩溃报告和 Control Center 日志。

## 13. 常用诊断命令

检查进程：

```bash
pgrep -alf YourApp
```

检查架构：

```bash
file /Applications/YourApp.app/Contents/MacOS/YourApp
```

检查签名：

```bash
codesign --verify --deep --strict --verbose=2 /Applications/YourApp.app
codesign -dv --verbose=4 /Applications/YourApp.app
codesign -d -r- /Applications/YourApp.app
```

检查 Gatekeeper：

```bash
spctl --assess --type execute --verbose=4 /Applications/YourApp.app
```

检查应用日志：

```bash
log show --last 10m --style compact \
  --predicate 'process == "YourApp"'
```

检查崩溃报告：

```bash
find ~/Library/Logs/DiagnosticReports \
  -maxdepth 1 \
  \( -name 'YourApp*.crash' -o -name 'YourApp*.ips' \)
```

## 14. 问题判断顺序

遇到“应用打不开”时，按以下顺序判断：

1. 进程是否存在。
2. 是否有崩溃报告。
3. 签名是否有效。
4. Gatekeeper 是否拦截。
5. 应用是否为 `LSUIElement`，因此没有 Dock 和主窗口。
6. 菜单栏项是否被 Control Center blocked。
7. 状态项窗口是否落在任一有效显示器范围。
8. TCC 权限是否因签名或 Bundle ID 改变而失效。

不要只根据“进程存在”或 `NSStatusItem.isVisible` 就判断应用工作正常。
