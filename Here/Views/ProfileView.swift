import SwiftUI

// 个人页。结构是她原来的,一样没动:
//   here you are,
//   一张卡片:LINKED NUMBER / HERE SINCE
//   一张卡片:My Posts / Safety & Reporting / Help & Feedback / About & Legal
//   Sign Out(或 Sign in with phone)/ Delete Account
//
// 2026-11-25 改的只是"穿的衣服",让它和已经定下来的几页(聊天页、Chats 列表、发帖页)是一家的:
// 1. 背景:纸 + 顶上一片白光(PaperBackground),原来是一块平的纸色。
// 2. 字:圆体(Theme.ui),不再用细体。问候语和发帖页的 "dear stranger bestie," 同一个写法。
// 3. 颜色:原来到处是浅金色的小字和细体(对比度 1.5–2:1,读不出来)。现在按已定的规则:
//    金色只给品牌、光、回应帖子;要读的、要点的都是棕色。最淡的字是 ink3(4.48:1)。
// 4. Delete Account 原来是 25% 透明度的 12pt 小字,几乎看不见。苹果要求 app 里的删号入口容易找到,
//    现在是正常可读的棕色字,可点的高度 44pt。
// 5. 卡片:白底 + 一圈极淡的线,和聊天页的 "STARTED FROM" 卡片同一个做法;原来是白底 + 金色的影子。
// 6. 手机号和日期不再用等宽字体(那是代码的字体)。
// 提到别人的地方一律 she / her(她 2026-11-22 定的)。
//
// 2026-11-25 13:44 她在手机上看了上面这一版:"现在这一版完全没有一个重心,所有的颜色都是一样的,反而不好看了";
// "最左边的这六个小图标是不是可以改成金色";"我们希望用户看到的是哪些信息,就用棕色写出来,不那么重要的换成金色,
// 还可以有浅棕色,有一个视觉上的差"。我第 3 条做过头了:把所有东西都变成了棕色,层次没了。
// 所以这一页现在分三层(她重开了"这一页的图标可以是金色"):
//   深棕(ink):   她来这一页要看、要点的 —— 手机号、日期、四个入口的名字、Link。
//   金色:        不用读的 —— 左边的小图标。
//   浅棕:        说明和次要的 —— 小标题(LINKED NUMBER)、箭头、Sign Out、Delete Account。
// 要读的字没有一处用金色:金色的字在白底上只有约 1.7:1,读不出来(她原来那一版的问题就在这里)。
// 同一个做法的参照:iPhone 自带的"设置":图标带颜色,名字是最深的字,补充信息和箭头是浅灰。

/// 只在测试版里用:面板里"示例"开着的时候,个人页显示一个"已经绑了手机、发过帖、拉黑过人"的样子,
/// 好让她在自己手机上看到每一种状态。平时是 nil,显示真的数据。里面的东西不会发出去。
struct ProfilePreview {
    struct Blocked: Identifiable {
        let id: String
        let nickname: String?
    }
    let phone: String
    let posts: [Post]
    let blocked: [Blocked]
}

// MARK: - ProfileView

struct ProfileView: View {
    @ObservedObject var app: AppState
    var preview: ProfilePreview? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 22) {
                        GreetingSection()
                        AccountCard(preview: preview)
                        ProfileMenuCard(app: app, preview: preview)
                        ProfileBottomActions(app: app, preview: preview)
                    }
                    .padding(.top, 30)
                    .padding(.bottom, 110)
                }
            }
        }
        .tint(Theme.ink)
    }
}

// MARK: - Sign Out 和 Delete Account 放在哪(她定的)
//
// **Sign Out:手机号那一行的右边,只是一行字,没有圈。她 2026-11-25 15:04 在手机上定的
// ("我喜欢 B,可以 B,但是不要那个圈")。不要再动,除非她说要重开。**
// **Delete Account:入口那张卡片的正下方,一行小字。**(同一条消息:"delete 太靠下了"。)
//
// 怎么走到这里的(都是她 2026-11-25 说的):
// 1. 两行浅棕的字上下挨着(Sign Out / Delete Account)——她同意要把两件事分开,但不满意。
// 2. Sign Out 一整条白卡片 + 下面一行小字——"我还是不满意现在这个设计"。
// 3. 给了她三种 Sign Out 的位置,Delete Account 都沉在页面最底(底栏上面):
//    A 卡片下面一个小描边按钮;B 手机号那一行右边的小描边按钮;C 入口卡片的最后一行(我推荐的)。
//    她选了 B,去掉描边;Delete Account 沉在最底她嫌"太靠下了"。A、C 和沉底的代码都删了。
// 为什么分开:退出能回来,删号回不来,两件轻重差这么多的事不该长得一样、还挨在一起。

// **这两行字都是金色(和左边小图标同一个金,Theme.brandGold),她 2026-11-25 定的。不要再动,除非她说要重开。**
// - Sign Out:16:05 "signout 保持金色"。15pt medium。
// - Delete Account:16:13 "其实我更喜欢 A 的,更美观"。A = 入口卡片下面的一行金色字,比原来大(15pt medium;
//   原来 13pt,我说过小字用金色太淡,和苹果"删号入口要容易找到"打架,她说"那把 delete 的加大一些")。
//   她看过、没要的 B:放进入口卡片做最后一行(带垃圾桶图标)。代码已经删了。
// 金色在白底上约 2:1,达不到正文 4.5:1 的通行标准;她看过、知道,选的是好看。

/// 小的描边按钮:Link、Sign in with phone、Unblock、热线的 Call / Text。
private struct ProfilePill: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.ui(15, .semibold))
                .foregroundColor(Theme.ink)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(Capsule().fill(Color.white.opacity(0.6)))
                .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
                // 看上去 36pt 高,可点的地方上下各多 4pt,凑够 44pt
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressFade())
    }
}

// MARK: - Pieces shared by this page and the three behind it

private struct ProfileCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.9)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
            .padding(.horizontal, 20)
    }
}

/// 卡片里的小标题:LINKED NUMBER、HERE SINCE。和聊天页的 "STARTED FROM" 同一个写法。
private struct ProfileCaption: View {
    let text: String
    var body: some View {
        Text(text)
            // 浅棕、不加粗:它只是说明下面那一行是什么,不该和下面那一行抢
            .font(Theme.ui(11, .medium))
            .tracking(1.2)
            .foregroundColor(Theme.ink3)
    }
}

/// 卡片左边的小图标:金色的线条图标。旁边都有字,图标不用读,所以可以是金色。
///
/// **她 2026-11-25 14:02 在手机上定的("B")。不要再动,除非她说要重开。**
/// 给她看过两种:A 实心的金色图标(和 "here" 小人同一个金色,我推荐的那个),B 线条的金色图标(品牌金,
/// 最接近她原来那一版)。她选了 B。A 的代码已经删了。
/// 我还做过第三种、没有给她:一个哑光金的小圆片,里面是棕色图标。六个圆片排成一列太抢,重心跑到了图标上。
private struct ProfileIcon: View {
    let name: String
    var body: some View {
        Image(systemName: name)
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(Theme.brandGold)
            .frame(width: 28)
            .accessibilityHidden(true)
    }
}

/// 行尾的小箭头:浅棕。只是告诉她"这一行能点进去",不用读。
private struct ProfileRowArrow: View {
    let name: String
    var size: CGFloat = 13
    var body: some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .semibold))
            .foregroundColor(Theme.tabOff)
            .accessibilityHidden(true)
    }
}

private struct ProfileMenuDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1)
            .padding(.leading, 58)
    }
}

// MARK: - Greeting

private struct GreetingSection: View {
    var body: some View {
        Text("here you are,")
            // app 自己的口吻,和发帖页的 "dear stranger bestie," 同一个字体、同一个颜色
            .font(Theme.brand(27))
            .foregroundStyle(Theme.ink2)
            .padding(.vertical, -7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
    }
}

// MARK: - Account Card (phone + since)

private struct AccountCard: View {
    @EnvironmentObject private var auth: AuthService
    let preview: ProfilePreview?
    @State private var showPhoneSignIn = false
    @State private var confirmSignOut = false

    private var phoneNumber: String? { preview?.phone ?? auth.phoneNumber }
    private var isLinked: Bool { phoneNumber != nil }

    /// "+1 ••• ••• 8291" — enough to recognise your own number, nothing more
    private var maskedPhone: String? {
        guard let number = phoneNumber else { return nil }
        let digits = number.filter(\.isNumber)
        guard digits.count >= 4 else { return number }
        let last4 = digits.suffix(4)
        let country = digits.count > 10 ? "+" + digits.prefix(digits.count - 10) + " " : ""
        return country + "••• ••• " + last4
    }

    private var memberSinceText: String {
        guard let date = auth.memberSince else { return "—" }
        return date.formatted(.dateTime.month(.abbreviated).year())
    }

    var body: some View {
        ProfileCard {
            HStack(spacing: 12) {
                ProfileIcon(name: "phone")

                VStack(alignment: .leading, spacing: 3) {
                    ProfileCaption(text: "LINKED NUMBER")
                    if let maskedPhone {
                        Text(maskedPhone)
                            .font(Theme.ui(16, .medium))
                            .monospacedDigit()
                            .foregroundColor(Theme.ink)
                    } else {
                        Text("Not linked yet")
                            .font(Theme.ui(16))
                            .foregroundColor(Theme.ink2)
                    }
                }

                Spacer(minLength: 8)

                if !isLinked {
                    ProfilePill(title: "Link") { showPhoneSignIn = true }
                } else {
                    // 绑了手机号以后,这个位置是 Sign Out:动作跟着它管的东西(这个号码)。
                    // 只是一行字,没有圈,金色(都是她定的)。
                    Button {
                        guard preview == nil else { return }   // 示例里点了不做任何事
                        confirmSignOut = true
                    } label: {
                        Text("Sign Out")
                            .font(Theme.ui(15, .medium))
                            .foregroundColor(Theme.brandGold)
                            .padding(.leading, 12)
                            // 字的右边和下面那张卡片的箭头对齐
                            .padding(.trailing, 2)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressFade())
                }
            }
            .padding(.leading, 18)
            .padding(.trailing, 16)
            .padding(.vertical, 14)

            ProfileMenuDivider()

            HStack(spacing: 12) {
                ProfileIcon(name: "sparkles")

                VStack(alignment: .leading, spacing: 3) {
                    ProfileCaption(text: "HERE SINCE")
                    Text(memberSinceText)
                        .font(Theme.ui(16, .medium))
                        .foregroundColor(Theme.ink)
                }

                Spacer(minLength: 8)
            }
            .padding(.leading, 18)
            .padding(.trailing, 16)
            .padding(.vertical, 18)
        }
        .sheet(isPresented: $showPhoneSignIn) {
            PhoneSignInSheet(reason: "Link a phone number to post, chat, and keep your history across devices. It's never shown to anyone.")
        }
        .alert("Sign out?", isPresented: $confirmSignOut) {
            Button("Sign Out", role: .destructive) { Task { await auth.signOut() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You can keep reading. Sign in with the same phone number any time to get your posts and chats back.")
        }
    }
}

// MARK: - Profile Menu Card

private struct ProfileMenuCard: View {
    @ObservedObject var app: AppState
    let preview: ProfilePreview?

    private var chevron: some View { ProfileRowArrow(name: "chevron.right") }

    var body: some View {
        ProfileCard {
            NavigationLink(destination: MyPostsView(app: app, preview: preview)) {
                ProfileMenuRow(icon: "book.closed", label: "My Posts") { chevron }
            }
            .buttonStyle(PressFade())

            ProfileMenuDivider()

            NavigationLink(destination: SafetyView(app: app, preview: preview)) {
                ProfileMenuRow(icon: "shield.lefthalf.filled", label: "Safety & Reporting") { chevron }
            }
            .buttonStyle(PressFade())

            ProfileMenuDivider()

            Link(destination: AppLinks.support) {
                ProfileMenuRow(icon: "questionmark.circle", label: "Help & Feedback") { chevron }
            }
            .buttonStyle(PressFade())

            ProfileMenuDivider()

            NavigationLink(destination: AboutLegalView()) {
                ProfileMenuRow(icon: "doc.text", label: "About & Legal") { chevron }
            }
            .buttonStyle(PressFade())
        }
    }
}

private struct ProfileMenuRow<Trailing: View>: View {
    let icon: String
    let label: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            ProfileIcon(name: icon)

            Text(label)
                .font(Theme.ui(16))
                .foregroundColor(Theme.ink)

            Spacer(minLength: 8)

            trailing()
        }
        .padding(.leading, 18)
        .padding(.trailing, 18)
        // 一行 52pt 高:比 44pt 的下限宽裕
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

// MARK: - About & Legal

/// Public pages hosted on Firebase Hosting (the `site/` folder in the repo).
/// App Store Connect points at the same URLs.
enum AppLinks {
    static let site = URL(string: "https://here-a6817.web.app")!
    static let privacy = site.appendingPathComponent("privacy.html")
    static let terms = site.appendingPathComponent("terms.html")
    static let support = site.appendingPathComponent("support.html")
}

struct AboutLegalView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 22) {
                    ProfileCard {
                        legalRow("Privacy Policy", icon: "hand.raised", url: AppLinks.privacy)
                        ProfileMenuDivider()
                        legalRow("Terms & Community Guidelines", icon: "doc.text", url: AppLinks.terms)
                        ProfileMenuDivider()
                        legalRow("Help & Support", icon: "questionmark.circle", url: AppLinks.support)
                    }

                    VStack(spacing: 4) {
                        Text("Here")
                            .font(Theme.brand(20))
                            .foregroundStyle(Theme.ink2)
                            .padding(.vertical, -5)
                        Text(version)
                            .font(Theme.ui(13))
                            .foregroundColor(Theme.ink3)
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("About & Legal")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func legalRow(_ label: String, icon: String, url: URL) -> some View {
        Link(destination: url) {
            ProfileMenuRow(icon: icon, label: label) {
                ProfileRowArrow(name: "arrow.up.right", size: 12)
            }
        }
        .buttonStyle(PressFade())
    }
}

// MARK: - Bottom Actions (Sign Out + Delete Account)

private struct ProfileBottomActions: View {
    @ObservedObject var app: AppState
    let preview: ProfilePreview?
    @EnvironmentObject private var auth: AuthService
    @State private var showPhoneSignIn = false
    @State private var confirmDelete = false
    @State private var deleteNeedsReverify = false
    @State private var deleteFailed = false

    private var isLinked: Bool { preview != nil || auth.isPhoneVerified }

    var body: some View {
        VStack(spacing: 0) {
            if !isLinked {
                // 没绑手机号:这是这一页最该点的东西,所以是深色的按钮。
                // (绑了以后这里什么都没有:Sign Out 在手机号那一行。)
                ProfilePill(title: "Sign in with phone") { showPhoneSignIn = true }
                    .padding(.bottom, 4)
            }

            // Delete Account:入口那张卡片的正下方(她嫌沉在页面最底"太靠下了"),一行金色的字。
            // 金色淡,所以字比原来大(15pt、加粗一档),可点的高度 44pt,不用翻就看得见
            // (苹果要求删号入口容易找到)。它最早是 25% 透明度的 12pt 小字,几乎看不见。
            // 不用红色:她定的颜色里没有红(2026-11-19:"绝对不要红 / 粉")。
            Button {
                guard preview == nil else { return }   // 示例里点了不做任何事
                confirmDelete = true
            } label: {
                Text("Delete Account")
                    .font(Theme.ui(15, .medium))
                    .foregroundColor(Theme.brandGold)
                    .padding(.horizontal, 24)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressFade())
        }
        .sheet(isPresented: $showPhoneSignIn) {
            PhoneSignInSheet(
                reason: deleteNeedsReverify
                    ? "For your safety, confirm your number once more before deleting the account."
                    : "Sign in to post, chat, and keep your history across devices.",
                onVerified: {
                    guard deleteNeedsReverify else { return }
                    deleteNeedsReverify = false
                    Task { await deleteAccount() }
                }
            )
        }
        .alert("Delete your account?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { Task { await deleteAccount() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently deletes your account, phone number, posts and photos. Messages you already sent stay with her until that conversation ends. This can't be undone.")
        }
        .alert("Couldn't delete the account", isPresented: $deleteFailed) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please try again in a moment.")
        }
    }

    private func deleteAccount() async {
        do {
            // Content first: once the auth user is gone we no longer have
            // permission to delete anything that belonged to it
            await app.deleteMyContent()
            try await auth.deleteAccount()
        } catch AuthService.DeleteAccountError.needsRecentLogin {
            deleteNeedsReverify = true
            showPhoneSignIn = true
        } catch {
            deleteFailed = true
        }
    }
}

// MARK: - My Posts View

struct MyPostsView: View {
    @ObservedObject var app: AppState
    var preview: ProfilePreview? = nil
    @State private var showArchived = false

    private var myPosts: [Post] { preview?.posts ?? app.myPosts }
    /// Active = still visible in the feed; Archived = past its 48h
    private var activePosts: [Post] { myPosts.filter { $0.expiresAt > Date() } }
    private var archivedPosts: [Post] { myPosts.filter { $0.expiresAt <= Date() } }
    private var currentPosts: [Post] { showArchived ? archivedPosts : activePosts }

    var body: some View {
        ZStack {
            PaperBackground()

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    MyPostsTab(label: "Active", selected: !showArchived) { showArchived = false }
                    MyPostsTab(label: "Archived", selected: showArchived) { showArchived = true }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)

                Rectangle()
                    .fill(Theme.hairline)
                    .frame(height: 1)

                if currentPosts.isEmpty {
                    Spacer()
                    Text(showArchived ? "Nothing archived yet." : "No posts yet.")
                        .font(Theme.ui(15))
                        .foregroundColor(Theme.ink3)
                    Spacer()
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(currentPosts) { post in
                                MyPostCard(post: post, isArchived: showArchived)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 110)
                    }
                }
            }
        }
        .navigationTitle("My Posts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MyPostsTab: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(label)
                    .font(Theme.ui(15, selected ? .semibold : .regular))
                    .foregroundColor(selected ? Theme.ink : Theme.ink3)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)

                // 选中的那一格底下一道棕色的线(选中的标签也是棕线,不是金线)
                Capsule()
                    .fill(selected ? Theme.line : Color.clear)
                    .frame(height: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.15), value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct MyPostCard: View {
    let post: Post
    let isArchived: Bool

    private var timeText: String {
        if isArchived {
            return post.createdAt.formatted(.dateTime.month(.abbreviated).day())
        }
        return post.createdAt.formatted(.relative(presentation: .named))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    if post.isPrivate {
                        Image(systemName: "lock")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(Theme.ink3)
                            .accessibilityLabel("Just for me")
                    }
                    Text(verbatim: post.title.isEmpty ? post.bodyText : post.title)
                        .font(Theme.ui(16, .semibold))
                        .foregroundColor(isArchived ? Theme.ink3 : Theme.ink)
                        .lineLimit(2)
                }

                if !post.tags.isEmpty {
                    // 标签就是表情本身,不在前面加 "#"(帖子页上也没有)
                    Text(verbatim: post.tags.joined(separator: " "))
                        .font(.system(size: 14))
                        .opacity(isArchived ? 0.6 : 1)
                }
            }

            Spacer(minLength: 8)

            Text(timeText)
                .font(Theme.ui(12, .medium))
                .foregroundColor(Theme.ink3)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(isArchived ? 0.55 : 0.9)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

// MARK: - Safety & Reporting

/// "Safety & Reporting" 点进来的这一页。原来点进来直接就是拉黑名单,名字说得比里面的东西多。
/// 她 2026-11-25 14:22:"safety 是要加这些内容的,我的 app 现在只在美国上线。"
/// 三块:现在就需要帮助(美国的三条热线)/ 怎么举报和拉黑、之后会怎样 / 拉黑名单的入口。
///
/// **这一页的英文都是我起的草稿,她还没有点头。**
/// 写的每一句都对过实际情况:
/// - 热线的号码和发短信的词,2026-11-25 对过各自的官网(988lifeline.org、thehotline.org、rainn.org)。
///   上线前再对一遍;以后去别的国家上线,这一块要按国家换。
/// - "24 小时内看完":Terms 里写的是 "We review reports and act on them within 24 hours"。
/// - "好几个人举报就先下架":后台的 autoHideReports(默认 3 个不同的人)。
/// - "对方不会知道":举报弹层和 support 页上都是这么写的,拉黑也确实不通知对方。
/// 写法:帖子里会有很重的话,过滤器是故意不拦的(ContentFilter),所以这里要有一个去处;
/// 只说"可以找谁",不描述任何细节。
struct SafetyView: View {
    @ObservedObject var app: AppState
    var preview: ProfilePreview? = nil
    @Environment(\.openURL) private var openURL

    private struct HelpLine: Identifiable {
        let id: String
        let name: String
        let detail: String
        let call: String
        let text: String
        var textBody: String? = nil

        var callURL: URL? { URL(string: "tel:\(call)") }
        var textURL: URL? {
            if let textBody { return URL(string: "sms:\(text)&body=\(textBody)") }
            return URL(string: "sms:\(text)")
        }
    }

    private let lines: [HelpLine] = [
        HelpLine(id: "988", name: "Suicide & Crisis Lifeline", detail: "Call or text 988", call: "988", text: "988"),
        HelpLine(id: "dv", name: "Domestic Violence Hotline", detail: "1-800-799-7233, or text START to 88788",
                 call: "18007997233", text: "88788", textBody: "START"),
        HelpLine(id: "rainn", name: "Sexual Assault Hotline", detail: "1-800-656-4673, or text HOPE to 64673",
                 call: "18006564673", text: "64673", textBody: "HOPE")
    ]

    private var blockedCount: Int { preview?.blocked.count ?? app.blockedUIDs.count }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("IF YOU NEED HELP NOW")
                    bodyText("Here can't respond in an emergency, and posts aren't watched in real time. These lines can help right away. They're free, confidential, and open 24/7.")

                    ProfileCard {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                            if index > 0 {
                                Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 18)
                            }
                            helpRow(line)
                        }
                    }
                    .padding(.top, 4)

                    bodyText("In immediate danger, call 911.")
                        .padding(.top, 2)

                    sectionTitle("REPORT OR BLOCK")
                        .padding(.top, 22)

                    ProfileCard {
                        howRow(icon: "ellipsis", text: "On a post: tap ⋯, then Report Post or Block her.")
                        ProfileMenuDivider()
                        howRow(icon: "shield", text: "In a conversation: tap the shield at the top, then Report & End or Block & End.")
                    }
                    .padding(.top, 4)

                    bodyText("Reports are anonymous, and she is never told who reported or blocked her. We review every report within 24 hours. A post that several women report is hidden right away.")
                        .padding(.top, 2)

                    ProfileCard {
                        NavigationLink(destination: BlockedUsersView(app: app, preview: preview)) {
                            ProfileMenuRow(icon: "hand.raised", label: "Blocked") {
                                HStack(spacing: 8) {
                                    if blockedCount > 0 {
                                        Text("\(blockedCount)")
                                            .font(Theme.ui(15))
                                            .foregroundColor(Theme.ink3)
                                    }
                                    ProfileRowArrow(name: "chevron.right")
                                }
                            }
                        }
                        .buttonStyle(PressFade())
                    }
                    .padding(.top, 22)
                }
                .padding(.top, 16)
                .padding(.bottom, 110)
            }
        }
        .navigationTitle("Safety & Reporting")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sectionTitle(_ text: String) -> some View {
        ProfileCaption(text: text)
            .padding(.horizontal, 28)
            .accessibilityAddTraits(.isHeader)
    }

    private func bodyText(_ text: String) -> some View {
        Text(text)
            .font(Theme.ui(14))
            .foregroundColor(Theme.ink2)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 28)
    }

    private func helpRow(_ line: HelpLine) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(line.name)
                    .font(Theme.ui(16, .medium))
                    .foregroundColor(Theme.ink)
                Text(line.detail)
                    .font(Theme.ui(13))
                    .foregroundColor(Theme.ink3)
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            ProfilePill(title: "Call") { if let url = line.callURL { openURL(url) } }
                .accessibilityLabel("Call \(line.name)")
            ProfilePill(title: "Text") { if let url = line.textURL { openURL(url) } }
                .accessibilityLabel("Text \(line.name)")
        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
    }

    private func howRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ProfileIcon(name: icon)
                .padding(.top, 1)
            Text(text)
                .font(Theme.ui(15))
                .foregroundColor(Theme.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

// MARK: - Blocked users

struct BlockedUsersView: View {
    @ObservedObject var app: AppState
    var preview: ProfilePreview? = nil

    private var blocked: [ProfilePreview.Blocked] {
        if let preview { return preview.blocked }
        return app.blockedUIDs.sorted().map { ProfilePreview.Blocked(id: $0, nickname: app.knownNickname(for: $0)) }
    }

    var body: some View {
        ZStack {
            PaperBackground()
            if blocked.isEmpty {
                VStack(spacing: 8) {
                    Text("No one blocked.")
                        .font(Theme.ui(16, .semibold))
                        .foregroundColor(Theme.ink2)
                    Text("You can block her from a post's ⋯ menu or from the shield in a conversation.")
                        .font(Theme.ui(14))
                        .foregroundColor(Theme.ink3)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 44)
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(blocked) { other in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(verbatim: other.nickname ?? "A woman from the feed")
                                        .font(Theme.ui(16, .semibold))
                                        .foregroundColor(Theme.ink)
                                    Text(other.nickname == nil ? "Blocked from a post" : "Blocked from a conversation")
                                        .font(Theme.ui(13))
                                        .foregroundColor(Theme.ink3)
                                }
                                Spacer(minLength: 8)
                                ProfilePill(title: "Unblock") {
                                    guard preview == nil else { return }   // 示例里点了不做任何事
                                    Task { await app.unblockUser(other.id) }
                                }
                            }
                            .padding(.leading, 18)
                            .padding(.trailing, 14)
                            .padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.9)))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 110)
                }
            }
        }
        .navigationTitle("Blocked")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Previews

#Preview("Profile") {
    ProfileView(app: AppState(authService: AuthService()))
        .environmentObject(AuthService())
}

#Preview("My Posts") {
    NavigationStack {
        MyPostsView(app: AppState(authService: AuthService()))
    }
}
