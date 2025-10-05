//
//  CategoryView.swift
//  Here
//
//  Created by Aaron Lee on 8/22/25.
//

import SwiftUI

struct CategoryView: View {
    @Binding var isCallActive: Bool
    @State private var selectedCategory: String? = nil
    @State private var showingWaitingRoom = false
    
    let categories = [
        CategoryItem(title: "Positive", color: Color.white, icon: "face.smiling"),
        CategoryItem(title: "Negative", color: Color.white, icon: "face.dashed"),
        CategoryItem(title: "Chilling", color: Color.white, icon: "cloud.fill")
    ]
    
    var body: some View {
        ZStack {
            // Pink background
            Color(red: 243/255, green: 206/255, blue: 196/255)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Title
                VStack(spacing: 8) {
                    Text("How are you feeling right now?")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    
                    Text("✨Let's find your mood twin!")
                        .font(.callout)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .padding(.top, 30)
                
                Spacer()
                
                // Category list (vertical)
                VStack(spacing: 20) {
                    ForEach(categories, id: \.title) { category in
                        CategoryButton(
                            category: category,
                            isSelected: selectedCategory == category.title
                        ) {
                            selectCategory(category.title)
                        }
                    }
                }
                .padding(.horizontal, 30)
                
                Spacer()
                
                // Footer text
                Text("All categories will connect you with someone new")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showingWaitingRoom) {
            if let category = selectedCategory {
                WaitingRoomView(
                    selectedCategory: category,
                    isCallActive: $isCallActive,
                    showingWaitingRoom: $showingWaitingRoom
                )
            }
        }
        //.toolbar(.hidden, for: .tabBar) // Hide tab bar on categories screen
    }
    
    private func selectCategory(_ category: String) {
        selectedCategory = category
        
        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        // Small delay for visual feedback, then start call
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            showingWaitingRoom = true
        }
    }
}

struct CategoryItem {
    let title: String
    let color: Color
    let icon: String
}

struct CategoryButton: View {
    let category: CategoryItem
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 20) {
                // Icon
                Image(systemName: category.icon)
                    .font(.system(size: 35, weight: .medium))
                    .foregroundColor(.black.opacity(0.7))
                    .frame(width: 50)
                
                // Title
                Text(category.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.black.opacity(0.8))
                
                Spacer()
            }
            .padding(.horizontal, 25)
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.9),
                                Color.white.opacity(0.7),
                                Color.white.opacity(0.85)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(isSelected ? Color.black.opacity(0.3) : Color.clear, lineWidth: 3)
                    )
                    .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
            )
            .scaleEffect(isSelected ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    CategoryView(isCallActive: .constant(false))
}
