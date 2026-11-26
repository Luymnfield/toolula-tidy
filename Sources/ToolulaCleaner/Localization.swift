import AppKit
import Foundation

/// 界面文字翻译. 中文原文就是翻译表里的键 (Localization/translations.json → 各语言的 Localizable.strings).
/// 带数字/名字的句子用 %@ 占位: L("已选 %@ 项", "\(n)"). 译文里可以用 %1$@ %2$@ 调整顺序.
/// 系统语言不在支持列表里时, 自动用英文.
func L(_ key: String, _ args: String...) -> String {
    let format = AppLanguage.bundle.localizedString(forKey: key, value: key, table: nil)
    guard !args.isEmpty else { return format }
    return String(format: format, arguments: args.map { $0 as NSString })
}

/// 界面语言: 跟随系统, 或用户在设置里选的语言 (马上生效, 不用重启)
enum AppLanguage {
    static let storageKey = "appLanguage"
    static let system = "system"

    /// 支持的语言, 名字用各自的语言写 (看不懂当前语言的人也能找到自己的)
    static let supported: [(code: String, name: String)] = [
        ("zh-Hans", "简体中文"), ("zh-Hant", "繁體中文"), ("en", "English"), ("ja", "日本語"), ("ko", "한국어"),
        ("de", "Deutsch"), ("fr", "Français"), ("es", "Español"), ("pt", "Português"), ("ru", "Русский"),
    ]

    /// 用户的选择: "system" 或语言代码
    static var choice: String { UserDefaults.standard.string(forKey: storageKey) ?? system }

    /// 实际使用的语言代码
    static var resolved: String {
        if choice != system { return choice }
        // 「系统设置 › 通用 › 语言与地区 › 应用程序」里单独给本 App 设的语言优先, 其次是系统的语言列表
        let perApp = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] as? [String]
        let prefs = perApp ?? (CFPreferencesCopyValue("AppleLanguages" as CFString, kCFPreferencesAnyApplication,
                                            kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String]) ?? Locale.preferredLanguages
        return Bundle.preferredLocalizations(from: supported.map(\.code), forPreferences: prefs).first ?? "en"
    }

    private static var cachedBundle: (String, Bundle)?
    /// 当前语言的翻译表
    static var bundle: Bundle {
        let code = resolved
        if let c = cachedBundle, c.0 == code { return c.1 }
        let b = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? Bundle.main
        cachedBundle = (code, b)
        return b
    }

    /// 切换语言. 同时写进本 App 的 AppleLanguages, 让系统提供的部分 (菜单栏、系统弹窗) 下次启动也跟着变
    static func set(_ code: String) {
        if code == system {
            UserDefaults.standard.removeObject(forKey: storageKey)
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set(code, forKey: storageKey)
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        }
        cachedBundle = nil
    }
}
