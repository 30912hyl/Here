import Foundation

/// config/app:每台手机都要知道、谁也不能从手机上改的那几样。只在 Firebase 控制台里写。
/// 每一项都可以没有(functions/README.md 的 Settings 一节是同一张表)。
struct AppConfig: Codable, Equatable {
    /// founder 的账号。没有它,就没有和 founder 的对话。
    var founderUID: String?
    /// 用户在那段对话上看到的名字
    var founderNickname: String?
    /// 她先说的话,一条一条的。对话还没创建时由 app 直接显示;创建后服务器会把它写成真的消息。
    var founderWelcome: [String]?
    /// 那段对话多久到期;没有或 0 = 不过期
    var founderThreadHours: Int?
    /// false = 所有人都不能在聊天里发图;没有 = 能发
    var chatPhotos: Bool?
}
