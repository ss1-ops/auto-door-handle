//
//  OpenSesameApp.swift
//  OpenSesame
//
//  Created by Sam on 4/21/26.
//

import SwiftUI

@main
struct OpenSesameApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
