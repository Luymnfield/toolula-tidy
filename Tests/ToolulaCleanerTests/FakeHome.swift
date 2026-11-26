import Foundation
import XCTest
@testable import ToolulaCleaner

/// 每个测试都在一个临时的「假个人文件夹」里进行, 永远不碰真实文件.
/// 测试里移到废纸篓的东西, 测试结束时从废纸篓里删掉.
class FakeHomeTestCase: XCTestCase {
    var home: URL!
    private var realHome: URL!
    /// 测试中移到废纸篓的项目 (结束时清掉)
    var trashed: [URL] = []
    let fm = FileManager.default

    override func setUpWithError() throws {
        realHome = Scanner.home
        let tmp = fm.temporaryDirectory.appendingPathComponent("ToolulaCleanerTests-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        // 用真实路径 (/private/var/...): /var 是链接, 两种写法混用会让同一个文件有两个路径
        let real = realpath(tmp.path, nil)!
        home = URL(fileURLWithPath: String(cString: real), isDirectory: true)
        free(real)
        Scanner.home = home
    }

    override func tearDownWithError() throws {
        Scanner.home = realHome
        try? fm.removeItem(at: home)
        for t in trashed { try? fm.removeItem(at: t) }
    }

    /// 在假个人文件夹里建一个文件 (内容非零, 避免被当成稀疏文件)
    @discardableResult
    func file(_ rel: String, bytes: Int = 1000, modified: Date? = nil) throws -> URL {
        let u = home.appendingPathComponent(rel)
        try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x5A, count: bytes).write(to: u)
        if let modified {
            try fm.setAttributes([.modificationDate: modified], ofItemAtPath: u.path)
            setDateAdded(u, modified)
        }
        return u
    }

    /// 访达里的「添加日期」(下载文件夹按它判断多久没碰过), 用 setattrlist 改
    func setDateAdded(_ url: URL, _ date: Date) {
        var al = attrlist()
        al.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        al.commonattr = 0x1000_0000   // ATTR_CMN_ADDEDTIME
        var ts = timespec(tv_sec: Int(date.timeIntervalSince1970), tv_nsec: 0)
        let r = setattrlist(url.path, &al, &ts, MemoryLayout<timespec>.size, 0)
        XCTAssertEqual(r, 0, "设置添加日期失败")
    }

    @discardableResult
    func dir(_ rel: String) throws -> URL {
        let u = home.appendingPathComponent(rel)
        try fm.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    /// 一个假的 .app (带 Info.plist)
    @discardableResult
    func app(_ rel: String, bundleID: String, executable: String = "Dummy") throws -> URL {
        let u = home.appendingPathComponent(rel)
        try fm.createDirectory(at: u.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        let info: NSDictionary = ["CFBundleIdentifier": bundleID, "CFBundleExecutable": executable, "CFBundleShortVersionString": "1.2"]
        info.write(to: u.appendingPathComponent("Contents/Info.plist"), atomically: true)
        try Data(repeating: 1, count: 50_000).write(to: u.appendingPathComponent("Contents/MacOS/\(executable)"))
        return u
    }

    /// 用 stat 算一个文件夹的实际占用 (和 FastWalker 对照; 硬链接只算一次)
    func statSize(_ url: URL) -> Int64 {
        var seen = Set<UInt64>()
        var total: Int64 = 0
        let e = fm.enumerator(atPath: url.path)
        var paths = [url.path]
        while let p = e?.nextObject() as? String { paths.append(url.path + "/" + p) }
        for p in paths {
            var st = stat()
            guard lstat(p, &st) == 0, (st.st_mode & S_IFMT) != S_IFDIR else { continue }
            if st.st_nlink > 1 && !seen.insert(st.st_ino).inserted { continue }
            total += Int64(st.st_blocks) * 512
        }
        return total
    }

    let ctx = ScanContext(running: [], largeThreshold: 1_000_000, downloadsDays: 90)
}
