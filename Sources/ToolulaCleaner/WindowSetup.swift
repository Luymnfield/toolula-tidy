import AppKit
import SwiftUI

/// 窗口固定的启动大小 (每次打开都是这个大小, 位置居中)
enum WindowSetup {
    static let size = NSSize(width: 1138, height: 767)

    /// 不让系统记住上次的窗口大小, 每次都用固定大小并居中
    static func apply(to window: NSWindow) {
        window.isRestorable = false
        window.setFrameAutosaveName("")
        var h = size.height
        // 调试: --height 640  检查矮窗口
        if let i = CommandLine.arguments.firstIndex(of: "--height"), i + 1 < CommandLine.arguments.count,
           let v = Double(CommandLine.arguments[i + 1]) { h = v }
        window.setFrame(NSRect(origin: window.frame.origin, size: NSSize(width: size.width, height: h)), display: true)
        window.center()
        // 启动时键盘焦点不落在任何按钮上 (否则右上角设置按钮会有一圈蓝色焦点框)
        window.initialFirstResponder = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { window.makeFirstResponder(nil) }
    }
}

/// 找到 SwiftUI 视图所在的窗口, 只处理一次
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { if let w = v.window { onWindow(w) } }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - 滚动条: 平时隐藏, 滚动时才出现

/// 放在 ScrollView 内容里, 把外面的 NSScrollView 改成「悬浮」滚动条 (不管系统设置是「自动」还是接了鼠标)
private final class OverlayScrollerView: NSView {
    private var observer: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
        // 系统设置变了 (例如插拔鼠标), 系统会把滚动条改回去, 这时再改一次
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: NSScroller.preferredScrollerStyleDidChangeNotification,
                                                              object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.async { self?.apply() }
            }
        }
    }

    func apply() {
        guard let sv = enclosingScrollView else { return }
        sv.scrollerStyle = .overlay
        sv.autohidesScrollers = true
    }

    deinit { if let o = observer { NotificationCenter.default.removeObserver(o) } }
}

private struct OverlayScrollerRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { OverlayScrollerView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { (nsView as? OverlayScrollerView)?.apply() }
    }
}

extension View {
    /// 用在 ScrollView 的内容上: 滚动条平时隐藏, 滚动时出现
    func overlayScrollers() -> some View {
        background(OverlayScrollerRepresentable().frame(width: 0, height: 0))
    }
}
