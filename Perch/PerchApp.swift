//
//  PerchApp.swift
//  Perch
//
//  Created by Vlad on 6/25/26.
//

import SwiftUI

/// Perch is a menu-bar-only to-do list.
///
/// The menu bar item and its popover are managed by `AppDelegate` using an
/// `NSStatusItem`, which lets us treat a left-click (open the checklist) and a
/// right-click (show the Quit menu) differently — something SwiftUI's
/// `MenuBarExtra` can't express.
@main
struct PerchApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The app has no real window. This empty Settings scene satisfies the
        // `App` protocol without ever showing one, and we remove the Settings
        // menu command so it can never be opened.
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) { }
            }
    }
}
