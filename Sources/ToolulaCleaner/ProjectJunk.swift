import Foundation

/// 开发项目里能重新生成的文件夹: 依赖包 (node_modules、.venv…) 和编译产物 (target、build…).
/// 只有旁边确实有对应的项目文件 (package.json、Cargo.toml…) 才算, 不会误把你自己叫 build 的文件夹当成垃圾.
enum ProjectJunk {
    struct Rule: Sendable {
        let name: String
        /// 上一层 (项目文件夹) 里有其中之一才算
        var markers: [String] = []
        /// 文件夹里面有其中之一才算 (Python 虚拟环境)
        var inner: [String] = []
        let label: String
    }

    static var rules: [Rule] { [
        Rule(name: "node_modules", markers: ["package.json"], label: L("Node 依赖包")),
        Rule(name: ".next", markers: ["package.json"], label: L("Next.js 编译缓存")),
        Rule(name: ".nuxt", markers: ["package.json"], label: L("Nuxt 编译缓存")),
        Rule(name: ".venv", inner: ["pyvenv.cfg"], label: L("Python 虚拟环境")),
        Rule(name: "venv", inner: ["pyvenv.cfg"], label: L("Python 虚拟环境")),
        Rule(name: "target", markers: ["Cargo.toml", "pom.xml"], label: L("Rust / Maven 编译产物")),
        Rule(name: ".build", markers: ["Package.swift"], label: L("Swift 编译产物")),
        Rule(name: "Pods", markers: ["Podfile"], label: L("CocoaPods 依赖包")),
        Rule(name: "build", markers: ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts", "pubspec.yaml"],
             label: L("Gradle / Flutter 编译产物")),
        Rule(name: ".gradle", markers: ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"],
             label: L("Gradle 项目缓存")),
        Rule(name: ".dart_tool", markers: ["pubspec.yaml"], label: L("Dart 工具缓存")),
    ] }

    /// 规则里的名字 (多线程里用, 不能每次都现算)
    static let names: Set<String> = ["node_modules", ".next", ".nuxt", ".venv", "venv", "target", ".build", "Pods",
                                     "build", ".gradle", ".dart_tool"]

    /// 多少天没改过的项目算「旧项目」(默认勾选)
    static let staleDays = 30

    /// parent/name 是不是一个可以删的项目文件夹, 是的话返回对应的规则
    static func match(name: String, parent: String) -> Rule? {
        guard names.contains(name) else { return nil }
        let fm = FileManager.default
        for r in rules where r.name == name {
            if r.markers.contains(where: { fm.fileExists(atPath: parent + "/" + $0) }) { return r }
            if r.inner.contains(where: { fm.fileExists(atPath: parent + "/" + name + "/" + $0) }) { return r }
        }
        return nil
    }

    static func scan() -> ScanOutput {
        let found = Locked<[(String, String)]>([])   // (文件夹, 所在的项目)
        var opts = FastWalker.Options()
        opts.skipDir = { name, _, parent in
            if names.contains(name) {
                if match(name: name, parent: parent) != nil { found.mutate { $0.append((parent + "/" + name, parent)) } }
                return true   // 找到了就不再往里走 (node_modules 里面还有成千上万个文件夹)
            }
            if name.hasPrefix(".") { return true }   // .git 等隐藏文件夹
            return Scanner.isPackage(name)
        }
        // 只要找文件夹, 不需要算大小; 算大小在下面一次性做
        _ = FastWalker.sizes(Scanner.personalRoots().map(\.path), options: opts)

        let now = Date()
        var cands: [Scanner.Candidate] = []
        for (path, project) in found.value {
            let url = URL(fileURLWithPath: path)
            let name = url.lastPathComponent
            guard let rule = match(name: name, parent: project) else { continue }
            let days = Int(now.timeIntervalSince(lastChange(project)) / 86400)
            let stale = days >= staleDays
            cands.append(Scanner.Candidate(
                url: url,
                name: "\((project as NSString).lastPathComponent) · \(rule.label)",
                selected: stale,
                detail: L("%@ 天没改过 · %@", "\(days)", "\(Scanner.short(url))"),
                note: stale ? nil : L("最近在用")))
        }
        return ScanOutput(items: Scanner.items(cands))
    }

    /// 项目最后一次改动: 项目文件夹第一层里 (不算依赖和编译产物) 最新的修改时间, 包括 .git
    static func lastChange(_ project: String) -> Date {
        let fm = FileManager.default
        var latest = (try? fm.attributesOfItem(atPath: project)[.modificationDate] as? Date) ?? .distantPast
        for n in (try? fm.contentsOfDirectory(atPath: project)) ?? [] where !names.contains(n) && n != ".DS_Store" {
            var paths = [project + "/" + n]
            if n == ".git" { paths += [project + "/.git/index", project + "/.git/HEAD"] }
            for p in paths {
                var st = stat()
                guard lstat(p, &st) == 0 else { continue }
                let d = Date(timeIntervalSince1970: Double(st.st_mtimespec.tv_sec))
                if d > latest { latest = d }
            }
        }
        return latest
    }

    /// 删除前的检查: 在个人文件夹里 (不在资源库 / Toolula 里), 名字和项目文件都对得上
    static func allowed(_ p: String, home: String) -> Bool {
        guard p.hasPrefix(home + "/"), !p.hasPrefix(home + "/Library/"), !p.hasPrefix(home + "/Toolula/"),
              p.split(separator: "/").count > home.split(separator: "/").count + 1 else { return false }
        let rel = p.dropFirst(home.count + 1)
        if rel.hasPrefix(".") { return false }   // 隐藏的第一层文件夹 (例如 ~/.npm) 不算
        let url = URL(fileURLWithPath: p)
        return match(name: url.lastPathComponent, parent: url.deletingLastPathComponent().path) != nil
    }
}

/// 多个线程一起往里写的小容器
final class Locked<T>: @unchecked Sendable {
    private var v: T
    private let lock = NSLock()
    init(_ v: T) { self.v = v }
    var value: T { lock.lock(); defer { lock.unlock() }; return v }
    func mutate(_ f: (inout T) -> Void) { lock.lock(); f(&v); lock.unlock() }
}
