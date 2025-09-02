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
        CategoryItem(title: "Positive", color: Color.green.opacity(0.8), icon: "face.smiling"),
        CategoryItem(title: "Negative", color: Color.red.opacity(0.8), icon: "face.dashed"),
        CategoryItem(title: "Neutral", color: Color.gray.opacity(0.8), icon: "minus.circle"),
        CategoryItem(title: "Random", color: Color.purple.opacity(0.8), icon: "shuffle")
    ]
    
    var body: some View {
        ZStack {
            // Background gradient matching LiveView
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.15),
                    Color(red: 0.05, green: 0.05, blue: 0.1)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Title
                VStack(spacing: 10) {
                    Text("Choose Your Vibe")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("What kind of conversation are you in the mood for?")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .padding(.top, 40)
                
                Spacer()
                
                // Category grid
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 20),
                    GridItem(.flexible(), spacing: 20)
                ], spacing: 20) {
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
            VStack(spacing: 15) {
                // Icon
                Image(systemName: category.icon)
                    .font(.system(size: 40, weight: .medium))
                    .foregroundColor(.white)
                
                // Title
                Text(category.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(height: 140)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(category.color)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(isSelected ? Color.white : Color.clear, lineWidth: 3)
                    )
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
