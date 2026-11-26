import Foundation
import XCTest
@testable import ToolulaCleaner

/// 高速遍历: 大小要和 stat 算出来的一模一样
final class FastWalkerTests: FakeHomeTestCase {

    func testSizeMatchesStatForNestedTree() throws {
        for i in 0..<40 { try file("tree/a/b\(i % 4)/c/file\(i).bin", bytes: 1000 * (i + 1)) }
        try file("tree/top.bin", bytes: 123_456)
        let root = home.appendingPathComponent("tree")
        XCTAssertEqual(FastWalker.size(root.path), statSize(root))
        XCTAssertGreaterThan(FastWalker.size(root.path), 800_000)
    }

    func testManyRootsAtOnce() throws {
        var roots: [URL] = []
        for r in 0..<12 {
            for i in 0..<5 { try file("roots/r\(r)/d\(i)/f.bin", bytes: 4096 * (r + 1)) }
            roots.append(home.appendingPathComponent("roots/r\(r)"))
        }
        let sizes = FastWalker.sizes(roots.map(\.path))
        XCTAssertEqual(sizes, roots.map(statSize))
    }

    func testHardLinkCountedOnce() throws {
        let a = try file("hl/a.bin", bytes: 500_000)
        try fm.linkItem(at: a, to: home.appendingPathComponent("hl/sub/b.bin").creatingParent())
        let root = home.appendingPathComponent("hl")
        let size = FastWalker.size(root.path)
        XCTAssertEqual(size, statSize(root))
        XCTAssertLessThan(size, 900_000, "硬链接不能算两次")
    }

    func testSymlinkIsNotFollowed() throws {
        let big = try file("outside/big.bin", bytes: 2_000_000)
        try dir("withlink")
        try fm.createSymbolicLink(at: home.appendingPathComponent("withlink/link"), withDestinationURL: big)
        XCTAssertLessThan(FastWalker.size(home.appendingPathComponent("withlink").path), 100_000)
        // 根本身是链接时也不跟随
        XCTAssertLessThan(FastWalker.size(home.appendingPathComponent("withlink/link").path), 100_000)
    }

    func testSingleFileAndMissingPath() throws {
        let f = try file("single.bin", bytes: 70_000)
        XCTAssertEqual(FastWalker.size(f.path), statSize(f))
        XCTAssertEqual(FastWalker.size(home.appendingPathComponent("nope").path), 0)
    }

    func testSkipRulesAndLargeFileCallback() throws {
        try file("scan/visible/big.bin", bytes: 3_000_000)
        try file("scan/.hidden/big.bin", bytes: 3_000_000)
        try file("scan/Photos.photoslibrary/inner.bin", bytes: 3_000_000)
        try file("scan/small.bin", bytes: 10)
        let found = Locked<[String]>([])
        var o = FastWalker.Options()
        o.skipHidden = true
        o.skipDir = { name, _, _ in name.hasSuffix(".photoslibrary") }
        o.fileThreshold = 1_000_000
        o.onFile = { _, path, _ in found.mutate { $0.append(path) } }
        _ = FastWalker.sizes([home.appendingPathComponent("scan").path], options: o)
        XCTAssertEqual(found.value.map { ($0 as NSString).lastPathComponent }, ["big.bin"])
        XCTAssertTrue(found.value[0].contains("/visible/"))
    }
}

extension URL {
    func creatingParent() throws -> URL {
        try FileManager.default.createDirectory(at: deletingLastPathComponent(), withIntermediateDirectories: true)
        return self
    }
}
