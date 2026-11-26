// 端到端测试: 真的打开 App、真的点按钮, 在一个临时的「假个人文件夹」里进行 (不碰真实文件).
// 用法: swift scripts/e2e.swift            (先运行 build_app.sh)
// 需要: 运行它的终端有「辅助功能」权限 (系统设置 › 隐私与安全性 › 辅助功能)
import AppKit
import ApplicationServices

let fm = FileManager.default
let appPath = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("build/Toolula Cleaner.app")
var failed = 0
func check(_ ok: Bool, _ what: String) {
    print(ok ? "  ✅ \(what)" : "  ❌ \(what)")
    if !ok { failed += 1 }
}
func step(_ s: String) { print("\n▶ \(s)") }

guard AXIsProcessTrusted() else { print("需要「辅助功能」权限"); exit(1) }

// MARK: 假个人文件夹
let tmpReal: String = { let p = realpath(NSTemporaryDirectory(), nil)!; defer { free(p) }; return String(cString: p) }()
let home = URL(fileURLWithPath: tmpReal).appendingPathComponent("tc-e2e-\(UUID().uuidString.prefix(8))")
func mk(_ rel: String, _ bytes: Int = 50_000) -> URL {
    let u = home.appendingPathComponent(rel)
    try! fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! Data(repeating: 0x42, count: bytes).write(to: u)
    return u
}
let alpha = mk("Library/Caches/com.e2e.alpha/a.bin", 300_000)
let beta = mk("Library/Caches/com.e2e.beta/b.bin", 200_000)
let log = mk("Library/Logs/E2E-Logs/x.log", 20_000)
let dummyApp = home.appendingPathComponent("Applications/E2E Dummy.app")
_ = mk("Applications/E2E Dummy.app/Contents/MacOS/E2EDummy", 80_000)
NSDictionary(dictionary: ["CFBundleIdentifier": "com.e2e.dummy", "CFBundleExecutable": "E2EDummy", "CFBundleShortVersionString": "9.9"])
    .write(to: dummyApp.appendingPathComponent("Contents/Info.plist"), atomically: true)
let pref = mk("Library/Preferences/com.e2e.dummy.plist", 2_000)
let support = mk("Library/Application Support/E2E Dummy/data.db", 40_000)
let trash = fm.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
func inTrash(_ name: String) -> Bool { ((try? fm.contentsOfDirectory(atPath: trash.path)) ?? []).contains { $0.hasPrefix(name) } }
func exists(_ u: URL) -> Bool { fm.fileExists(atPath: u.path) }

// MARK: 打开 App
// 注意: 不能用 -appLanguage 命令行参数, 它会在整个运行期间盖住保存的设置, 菜单里换语言就没效果了
let prefs = UserDefaults(suiteName: "com.toolula.cleaner")!
let savedLanguage = prefs.string(forKey: "appLanguage")
let savedAppleLanguages = prefs.array(forKey: "AppleLanguages")
prefs.set("zh-Hans", forKey: "appLanguage")
prefs.set(["zh-Hans"], forKey: "AppleLanguages")
prefs.synchronize()
let cfg = NSWorkspace.OpenConfiguration()
cfg.createsNewApplicationInstance = true
cfg.arguments = ["--fake-home", home.path]
var app: NSRunningApplication?
let sem = DispatchSemaphore(value: 0)
NSWorkspace.shared.openApplication(at: appPath, configuration: cfg) { a, _ in app = a; sem.signal() }
sem.wait()
guard let app else { print("打不开 App"); exit(1) }
let ax = AXUIElementCreateApplication(app.processIdentifier)
defer { }

// MARK: 辅助功能小工具
func attr(_ e: AXUIElement, _ a: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil
}
func str(_ e: AXUIElement, _ a: String) -> String { (attr(e, a) as? String) ?? "" }
func kids(_ e: AXUIElement) -> [AXUIElement] { (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
func find(_ match: (AXUIElement) -> Bool) -> AXUIElement? {
    var queue = [ax]
    while !queue.isEmpty {
        let e = queue.removeFirst()
        if match(e) { return e }
        queue += kids(e)
    }
    return nil
}
func byID(_ id: String) -> AXUIElement? { find { str($0, "AXIdentifier") == id } }
func button(titled t: String) -> AXUIElement? {
    find { str($0, kAXRoleAttribute) == "AXButton" && (str($0, kAXTitleAttribute) == t || str($0, kAXDescriptionAttribute) == t) }
}
/// 确认框 (sheet) 里的按钮
func dialogButton(_ t: String) -> AXUIElement? {
    guard let sheet = find({ str($0, kAXRoleAttribute) == "AXSheet" }) else { return nil }
    var queue = [sheet]
    while !queue.isEmpty {
        let e = queue.removeFirst()
        if str(e, kAXRoleAttribute) == "AXButton" && (str(e, kAXTitleAttribute) == t || str(e, kAXDescriptionAttribute) == t) { return e }
        queue += kids(e)
    }
    return nil
}
func text(containing t: String) -> AXUIElement? {
    find { e in [kAXValueAttribute, kAXDescriptionAttribute, kAXTitleAttribute].contains { str(e, $0).contains(t) } }
}
func enabled(_ e: AXUIElement) -> Bool { (attr(e, kAXEnabledAttribute) as? Bool) ?? false }
@discardableResult
func wait(_ what: String, timeout: Double = 12, _ cond: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while !cond() {
        if Date() > end { print("  ⏱ 等待超时: \(what)"); return false }
        Thread.sleep(forTimeInterval: 0.15)
    }
    return true
}
func press(_ e: AXUIElement?, _ what: String) {
    guard let e else { check(false, "找到「\(what)」"); return }
    let r = AXUIElementPerformAction(e, kAXPressAction as CFString)
    // 确认框里的按钮按下后, 确认框马上关掉, 系统会回 -25204 / -25205: 其实已经按下了 (后面会检查真实结果)
    if r != .success && ![-25204, -25205].contains(r.rawValue) { check(false, "点击「\(what)」(\(r.rawValue))") }
    Thread.sleep(forTimeInterval: 0.4)
}
func waitButton(_ get: @autoclosure () -> AXUIElement?, _ what: String) -> AXUIElement? {
    var b: AXUIElement?
    wait("「\(what)」可以点") { b = get(); return b.map(enabled) ?? false }
    return b
}

// MARK: 1. 清理 → 撤销
step("清理所选 → 确认 → 撤销")
press(waitButton(byID("home-clean"), "清理所选"), "清理所选")
press(waitButton(dialogButton("清理"), "确认框里的「清理」"), "确认框里的「清理」")
check(wait("缓存移走") { !exists(alpha) && !exists(beta) && !exists(log) }, "两个缓存和日志都移走了")
check(inTrash("com.e2e.alpha") && inTrash("com.e2e.beta"), "它们在废纸篓里")
press(waitButton(byID("toast-undo"), "撤销"), "撤销")
check(wait("放回原处") { exists(alpha) && exists(beta) && exists(log) }, "撤销后全部放回原处")
check(!inTrash("com.e2e.alpha"), "废纸篓里不再有它们")

// MARK: 2. 卸载 → 撤销
step("卸载应用 → 确认 → 撤销")
press(byID("rail-xmark.app"), "左侧栏「卸载」")
press(waitButton(byID("app-com.e2e.dummy"), "测试应用"), "测试应用")
press(waitButton(byID("uninstall-button"), "卸载按钮"), "卸载")
press(waitButton(dialogButton("卸载"), "确认框里的「卸载」"), "确认框里的「卸载」")
check(wait("应用和残留移走") { !exists(dummyApp) && !exists(pref) && !exists(support) }, "应用、偏好设置、应用数据都移走了")
check(inTrash("E2E Dummy.app"), "应用在废纸篓里")
press(waitButton(byID("toast-undo"), "撤销"), "撤销")
check(wait("应用放回") { exists(dummyApp) && exists(pref) && exists(support) }, "撤销后应用和残留都放回了")

// MARK: 3. 失败时能看到原因
step("没能处理的项目 → 查看详情")
let caches = home.appendingPathComponent("Library/Caches")
try! fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: caches.path)
press(byID("rail-home"), "左侧栏 logo")
press(waitButton(byID("home-clean"), "清理所选"), "清理所选")
press(waitButton(dialogButton("清理"), "确认框里的「清理」"), "确认框里的「清理」")
press(waitButton(byID("toast-details"), "查看详情"), "查看详情")
check(wait("失败窗口") { text(containing: "没能处理") != nil && text(containing: "权限") != nil }, "失败窗口列出了原因（权限）")
check(exists(alpha) && exists(beta), "没权限的缓存原样留着")
press(dialogButton("好"), "好")
try! fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: caches.path)

// MARK: 4. 内存页面
step("内存页面")
press(byID("rail-memorychip"), "左侧栏「内存」")
check(wait("内存压力") { text(containing: "内存压力") != nil && text(containing: "占用内存最多的应用") != nil }, "显示内存压力和占用最多的应用")

// MARK: 5. 语言菜单
step("设置 › 语言 → English → 简体中文")
func chooseLanguage(_ name: String) -> Bool {
    guard let gear = find({ str($0, kAXRoleAttribute) == "AXMenuButton" }) else { return false }
    press(gear, "设置菜单")
    guard let lang = find({ str($0, kAXRoleAttribute) == "AXMenuItem" && str($0, kAXTitleAttribute).contains("Language") }) else { return false }
    press(lang, "语言")
    guard let item = find({ str($0, kAXRoleAttribute) == "AXMenuItem" && str($0, kAXTitleAttribute) == name }) else { return false }
    press(item, name)
    return true
}
check(chooseLanguage("English"), "在菜单里选了 English")
check(wait("英文界面") { button(titled: "Memory") != nil }, "界面马上变成英文 (不用重启)")
check(chooseLanguage("简体中文"), "在菜单里选回简体中文")
check(wait("中文界面") { button(titled: "内存") != nil }, "界面变回中文")

// MARK: 收尾
app.terminate()
Thread.sleep(forTimeInterval: 1)
try? fm.removeItem(at: home)
for n in (try? fm.contentsOfDirectory(atPath: trash.path)) ?? [] where n.hasPrefix("com.e2e.") || n.hasPrefix("E2E") {
    try? fm.removeItem(at: trash.appendingPathComponent(n))
}
// 测试用的设置文件整个删掉
let d = Process()
d.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
d.arguments = ["delete", "com.toolula.cleaner.e2e"]
d.standardError = FileHandle.nullDevice
try? d.run(); d.waitUntilExit()
try? fm.removeItem(at: fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences/com.toolula.cleaner.e2e.plist"))
// 还原语言设置
if let savedLanguage { prefs.set(savedLanguage, forKey: "appLanguage") } else { prefs.removeObject(forKey: "appLanguage") }
if let savedAppleLanguages { prefs.set(savedAppleLanguages, forKey: "AppleLanguages") } else { prefs.removeObject(forKey: "AppleLanguages") }
prefs.synchronize()
print(failed == 0 ? "\n✅ 端到端测试全部通过" : "\n❌ \(failed) 项没通过")
exit(failed == 0 ? 0 : 1)
