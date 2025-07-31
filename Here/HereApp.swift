//
//  HereApp.swift
//  Here
//
//  Created by Aaron Lee on 7/30/25.
//

import SwiftUI

@main
struct HereApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
