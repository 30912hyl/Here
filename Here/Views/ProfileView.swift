import SwiftUI

// MARK: - Shared Gold Palette

private let profileGoldColors: [Color] = [
    Color(hex: "#F8EFD6"),
    Color(hex: "#F2DFAF"),
    Color(hex: "#E8C97A")
]
private let profileGoldAccent   = Color(hex: "#E6C35C")
private let profileBrownText    = Color(hex: "#5C3A1E")
private let profileMutedGold    = Color(hex: "#D8C898")
private let profileGoldGradient = LinearGradient(
    colors: profileGoldColors,
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)
private let warmBackground = Color(hex: "#FAF8F4")

// MARK: - ProfileView

struct ProfileView: View {
    @ObservedObject var app: AppState

    var body: some View {
        NavigationStack {
            ZStack {
                warmBackground.ignoresSafeArea()
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 24) {
                        GreetingSection()
                        AccountCard()
                        ProfileMenuCard(app: app)
                        ProfileBottomActions()
                    }
                    .padding(.top, 36)
                    .padding(.bottom, 110)
                }
            }
        }
    }
}

// MARK: - Greeting

private struct GreetingSection: View {
    var body: some View {
        Text("here you are,")
            .font(.system(size: 32, weight: .light))
            .foregroundColor(profileBrownText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
    }
}

// MARK: - Account Card (phone + ID)

private struct AccountCard: View {
    @EnvironmentObject private var auth: AuthService
    @State private var showPhoneSignIn = false

    /// "+1 ••• ••• 8291" — enough to recognise your own number, nothing more
    private var maskedPhone: String? {
        guard let number = auth.phoneNumber else { return nil }
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
        VStack(spacing: 0) {
            // Phone number row
            HStack(spacing: 14) {
                Image(systemName: "phone")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(profileGoldGradient)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text("LINKED NUMBER")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(1.5)
                        .foregroundColor(profileMutedGold)
                    if let maskedPhone {
                        Text(maskedPhone)
                            .font(.system(size: 15, weight: .regular, design: .monospaced))
                            .foregroundColor(profileBrownText)
                    } else {
                        Text("Not linked yet")
                            .font(.system(size: 15, weight: .light))
                            .foregroundColor(profileBrownText.opacity(0.6))
                    }
                }

                Spacer()

                if !auth.isPhoneVerified {
                    Button("Link") { showPhoneSignIn = true }
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(profileGoldAccent)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)

            Rectangle()
                .fill(profileGoldAccent.opacity(0.15))
                .frame(height: 0.5)
                .padding(.leading, 60)

            // Member since row
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(profileGoldGradient)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text("HERE SINCE")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(1.5)
                        .foregroundColor(profileMutedGold)
                    Text(memberSinceText)
                        .font(.system(size: 15, weight: .regular, design: .monospaced))
                        .foregroundColor(profileBrownText)
                }

                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
                .shadow(color: profileGoldAccent.opacity(0.1), radius: 12, y: 4)
        )
        .padding(.horizontal, 24)
        .sheet(isPresented: $showPhoneSignIn) {
            PhoneSignInSheet(reason: "Link a phone number to post, chat, and keep your history across devices. It's never shown to anyone.")
        }
    }
}

// MARK: - Profile Menu Card

private struct ProfileMenuCard: View {
    @ObservedObject var app: AppState
    @State private var notificationsOn = true
    @State private var postsHidden = false

    var body: some View {
        VStack(spacing: 0) {
            NavigationLink(destination: MyPostsView(app: app)) {
                ProfileMenuRow(icon: "book.closed", label: "My Posts") {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .light))
                        .foregroundColor(profileMutedGold)
                }
            }
            .buttonStyle(.plain)

            ProfileMenuDivider()

            ProfileMenuRow(
                icon: "moon",
                label: "Hide My Posts",
                subtitle: "your posts won't appear in the shared feed"
            ) {
                Toggle("", isOn: $postsHidden)
                    .tint(profileGoldAccent)
                    .labelsHidden()
                    .scaleEffect(0.85)
            }

            ProfileMenuDivider()

            ProfileMenuRow(icon: "bell.badge", label: "Notifications") {
                Toggle("", isOn: $notificationsOn)
                    .tint(profileGoldAccent)
                    .labelsHidden()
                    .scaleEffect(0.85)
            }

            ProfileMenuDivider()

            ProfileMenuRow(icon: "heart.text.square", label: "Refer a Friend") {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .light))
                    .foregroundColor(profileMutedGold)
            }

            ProfileMenuDivider()

            NavigationLink(destination: BlockedUsersView(app: app)) {
                ProfileMenuRow(icon: "shield.lefthalf.filled", label: "Safety & Reporting") {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .light))
                        .foregroundColor(profileMutedGold)
                }
            }
            .buttonStyle(.plain)

            ProfileMenuDivider()

            ProfileMenuRow(icon: "questionmark.circle", label: "Help & Feedback") {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .light))
                    .foregroundColor(profileMutedGold)
            }

            ProfileMenuDivider()

            ProfileMenuRow(icon: "doc.text", label: "About & Legal") {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .light))
                    .foregroundColor(profileMutedGold)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
                .shadow(color: profileGoldAccent.opacity(0.1), radius: 12, y: 4)
        )
        .padding(.horizontal, 24)
    }
}

private struct ProfileMenuRow<Trailing: View>: View {
    let icon: String
    let label: String
    var subtitle: String? = nil
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(profileGoldGradient)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(profileBrownText)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .light))
                        .foregroundColor(profileMutedGold)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            trailing()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }
}

private struct ProfileMenuDivider: View {
    var body: some View {
        Rectangle()
            .fill(profileGoldAccent.opacity(0.15))
            .frame(height: 0.5)
            .padding(.leading, 60)
    }
}

// MARK: - Bottom Actions (Sign Out + Delete Account)

private struct ProfileBottomActions: View {
    @EnvironmentObject private var auth: AuthService
    @State private var showPhoneSignIn = false
    @State private var confirmSignOut = false
    @State private var confirmDelete = false
    @State private var deleteNeedsReverify = false
    @State private var deleteFailed = false

    var body: some View {
        VStack(spacing: 16) {
            if auth.isPhoneVerified {
                Button { confirmSignOut = true } label: {
                    Text("Sign Out")
                        .font(.system(size: 14, weight: .light))
                        .tracking(0.3)
                        .foregroundColor(profileGoldAccent.opacity(0.8))
                }
                .buttonStyle(.plain)
            } else {
                Button { showPhoneSignIn = true } label: {
                    Text("Sign in with phone")
                        .font(.system(size: 14, weight: .light))
                        .tracking(0.3)
                        .foregroundColor(profileGoldAccent.opacity(0.8))
                }
                .buttonStyle(.plain)
            }

            Button { confirmDelete = true } label: {
                Text("Delete Account")
                    .font(.system(size: 12, weight: .light))
                    .tracking(0.2)
                    .foregroundColor(profileBrownText.opacity(0.25))
            }
            .buttonStyle(.plain)
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
        .alert("Sign out?", isPresented: $confirmSignOut) {
            Button("Sign Out", role: .destructive) { Task { await auth.signOut() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You can keep reading. Sign in with the same phone number any time to get your posts and chats back.")
        }
        .alert("Delete your account?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { Task { await deleteAccount() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently removes your account. Your posts and chats will no longer be tied to you. This can't be undone.")
        }
        .alert("Couldn't delete the account", isPresented: $deleteFailed) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please try again in a moment.")
        }
    }

    private func deleteAccount() async {
        do {
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
    @State private var showArchived = false

    /// Active = still visible in the feed; Archived = past its 48h
    private var activePosts: [Post] { app.myPosts.filter { $0.expiresAt > Date() } }
    private var archivedPosts: [Post] { app.myPosts.filter { $0.expiresAt <= Date() } }
    private var currentPosts: [Post] { showArchived ? archivedPosts : activePosts }

    var body: some View {
        ZStack {
            warmBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    MyPostsTab(label: "Active", selected: !showArchived) { showArchived = false }
                    MyPostsTab(label: "Archived", selected: showArchived) { showArchived = true }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 4)

                Rectangle()
                    .fill(profileGoldAccent.opacity(0.15))
                    .frame(height: 0.5)

                if currentPosts.isEmpty {
                    Spacer()
                    Text(showArchived ? "Nothing archived yet." : "No posts yet.")
                        .font(.system(size: 15, weight: .light))
                        .foregroundColor(profileMutedGold)
                    Spacer()
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(currentPosts) { post in
                                MyPostCard(post: post, isArchived: showArchived)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 40)
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
            VStack(spacing: 10) {
                Text(label)
                    .font(.system(size: 15, weight: selected ? .medium : .regular))
                    .foregroundColor(selected ? profileBrownText : profileMutedGold)

                Rectangle()
                    .fill(selected ? profileGoldAccent : Color.clear)
                    .frame(height: 1.5)
                    .cornerRadius(1)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.15), value: selected)
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
                            .font(.system(size: 11, weight: .light))
                            .foregroundColor(profileMutedGold)
                    }
                    Text(post.title.isEmpty ? post.bodyText : post.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(isArchived ? profileBrownText.opacity(0.4) : profileBrownText)
                        .lineLimit(2)
                }

                if !post.tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(post.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(isArchived ? profileMutedGold.opacity(0.6) : profileGoldAccent)
                        }
                    }
                }
            }

            Spacer()

            Text(timeText)
                .font(.system(size: 12, weight: .light))
                .foregroundColor(profileMutedGold.opacity(0.7))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(isArchived ? 0.6 : 1))
                .shadow(color: profileGoldAccent.opacity(0.07), radius: 6, y: 2)
        )
    }
}

// MARK: - Blocked users

struct BlockedUsersView: View {
    @ObservedObject var app: AppState

    private var blocked: [String] { app.blockedUIDs.sorted() }

    var body: some View {
        ZStack {
            warmBackground.ignoresSafeArea()
            if blocked.isEmpty {
                VStack(spacing: 10) {
                    Text("No one blocked.")
                        .font(.system(size: 15, weight: .light))
                        .foregroundColor(profileMutedGold)
                    Text("Block someone from a post's ⋯ menu or a conversation's Help menu.")
                        .font(.system(size: 13, weight: .light))
                        .foregroundColor(profileMutedGold.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(blocked, id: \.self) { other in
                            let nickname = app.knownNickname(for: other)
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(nickname ?? "Someone from the feed")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(profileBrownText)
                                    Text(nickname == nil ? "Blocked from a post" : "Blocked from a conversation")
                                        .font(.system(size: 12, weight: .light))
                                        .foregroundColor(profileMutedGold)
                                }
                                Spacer()
                                Button("Unblock") {
                                    Task { await app.unblockUser(other) }
                                }
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(profileGoldAccent)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white)
                                    .shadow(color: profileGoldAccent.opacity(0.07), radius: 6, y: 2)
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle("Blocked Users")
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
