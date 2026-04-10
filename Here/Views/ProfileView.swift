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
    var body: some View {
        NavigationStack {
            ZStack {
                warmBackground.ignoresSafeArea()
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 24) {
                        GreetingSection()
                        AccountCard()
                        ProfileMenuCard()
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
    @State private var isEditingID = false
    @State private var userID: String = "quiet-moon-4821"
    @State private var editingText = ""

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
                    Text("+1 ••• ••• 8291")
                        .font(.system(size: 15, weight: .regular, design: .monospaced))
                        .foregroundColor(profileBrownText)
                }

                Spacer()

                Button("Change") {}
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(profileGoldAccent)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)

            Rectangle()
                .fill(profileGoldAccent.opacity(0.15))
                .frame(height: 0.5)
                .padding(.leading, 60)

            // ID row
            HStack(spacing: 14) {
                Image(systemName: "person.text.rectangle")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(profileGoldGradient)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text("YOUR UNIQUE ID")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(1.5)
                        .foregroundColor(profileMutedGold)

                    if isEditingID {
                        TextField("", text: $editingText)
                            .font(.system(size: 15, weight: .regular, design: .monospaced))
                            .foregroundColor(profileBrownText)
                            .tint(profileGoldAccent)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .submitLabel(.done)
                            .onSubmit {
                                if !editingText.trimmingCharacters(in: .whitespaces).isEmpty {
                                    userID = editingText.trimmingCharacters(in: .whitespaces)
                                }
                                isEditingID = false
                            }
                    } else {
                        Text(userID)
                            .font(.system(size: 15, weight: .regular, design: .monospaced))
                            .foregroundColor(profileBrownText)
                    }
                }

                Spacer()

                if isEditingID {
                    Button("Save") {
                        if !editingText.trimmingCharacters(in: .whitespaces).isEmpty {
                            userID = editingText.trimmingCharacters(in: .whitespaces)
                        }
                        isEditingID = false
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(profileGoldAccent)
                } else {
                    Button {
                        editingText = userID
                        isEditingID = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(profileMutedGold)
                    }
                    .buttonStyle(.plain)
                }
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
    }
}

// MARK: - Profile Menu Card

private struct ProfileMenuCard: View {
    @State private var notificationsOn = true
    @State private var postsHidden = false

    var body: some View {
        VStack(spacing: 0) {
            NavigationLink(destination: MyPostsView()) {
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

            ProfileMenuRow(icon: "shield.lefthalf.filled", label: "Safety & Reporting") {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .light))
                    .foregroundColor(profileMutedGold)
            }

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
    var body: some View {
        VStack(spacing: 16) {
            Button {} label: {
                Text("Sign Out")
                    .font(.system(size: 14, weight: .light))
                    .tracking(0.3)
                    .foregroundColor(profileGoldAccent.opacity(0.8))
            }
            .buttonStyle(.plain)

            Button {} label: {
                Text("Delete Account")
                    .font(.system(size: 12, weight: .light))
                    .tracking(0.2)
                    .foregroundColor(profileBrownText.opacity(0.25))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - My Posts View

struct MyPostsView: View {
    @State private var showArchived = false

    private let activePosts: [MockProfilePost] = [
        MockProfilePost(title: "Feeling grateful today", tags: ["grateful", "happy"], time: "2h ago"),
        MockProfilePost(title: "Can't sleep again", tags: ["sad", "anxious"], time: "Yesterday"),
    ]

    private let archivedPosts: [MockProfilePost] = [
        MockProfilePost(title: "Something beautiful happened", tags: ["hopeful"], time: "Mar 12"),
        MockProfilePost(title: "First time sharing here", tags: ["nervous"], time: "Feb 28"),
    ]

    fileprivate var currentPosts: [MockProfilePost] { showArchived ? archivedPosts : activePosts }

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
    let post: MockProfilePost
    let isArchived: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(post.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isArchived ? profileBrownText.opacity(0.4) : profileBrownText)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    ForEach(post.tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(isArchived ? profileMutedGold.opacity(0.6) : profileGoldAccent)
                    }
                }
            }

            Spacer()

            Text(post.time)
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

// MARK: - Mock Data

private struct MockProfilePost: Identifiable {
    let id = UUID()
    let title: String
    let tags: [String]
    let time: String
}

// MARK: - Previews

#Preview("Profile") {
    ProfileView()
}

#Preview("My Posts") {
    NavigationStack {
        MyPostsView()
    }
}
