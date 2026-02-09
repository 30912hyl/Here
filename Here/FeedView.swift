import SwiftUI

struct FeedView: View {
    private let posts = Array(1...10)

    var body: some View {
        NavigationStack {
            TabView {
                ForEach(posts, id: \.self) { i in
                    SinglePostView(index: i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never)) // no dots
            .navigationTitle("Posts")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct SinglePostView: View {
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer(minLength: 0)

            Text("Post #\(index)")
                .font(.title2)
                .bold()

            Text("This is an anonymous post. ❤️ for likes, and later a button to start a private chat.")
                .font(.body)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Private chat") {
                    // later: open/create a conversation
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                VStack(spacing: 6) {
                    Image(systemName: "heart")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("12")
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

#Preview {
    FeedView()
}
