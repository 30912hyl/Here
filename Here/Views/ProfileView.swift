//
//  ProfileView.swift
//  Here
//
//  Created by yuchen on 1/27/26.
//
import SwiftUI

struct ProfileView: View {
    var body: some View {
        NavigationStack {
            List {
                Text("Profile (anonymous)")
                Text("Archive (later)")
                Text("Safety / report (later)")
            }
            .navigationTitle("Profile")
        }
    }
}

#Preview {
    ProfileView()
}
