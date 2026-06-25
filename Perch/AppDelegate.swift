//
//  AppDelegate.swift
//  Perch
//
//  Owns the menu bar status item and the popover that hosts the checklist.
//

import AppKit
import SwiftUI
import Observation

/// Sets up and manages the menu bar presence.
///
/// The status item shows the number of outstanding tasks as a circled number.
/// A left-click toggles the checklist popover; a right-click (or control-click)
/// shows a small menu containing Quit.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// The single, app-wide task store, shared with the SwiftUI content.
    private let store = TodoStore()

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    /// Last value rendered in the badge, so we skip redundant icon redraws.
    private var lastBadgeCount = -1

    func applicationDidFinishLaunching(_ notification: Notification) {
        configurePopover()
        configureStatusItem()
        updateBadge()
        observeStore()
    }

    // MARK: - Setup

    private func configurePopover() {
        let hosting = NSHostingController(rootView: MenuBarView(store: store))
        // Let the popover size itself to the SwiftUI content so it hugs the
        // list and grows as tasks are added (up to the view's own max height).
        hosting.sizingOptions = .preferredContentSize

        popover.contentViewController = hosting
        popover.behavior = .transient                 // closes when you click away
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            // Receive both mouse-up events so we can tell the clicks apart.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    // MARK: - Badge (task count)

    /// Renders the number of outstanding tasks as a circled number in the menu
    /// bar, mirroring Hotlist's badge. Drawn as a template image so it adapts
    /// to a light or dark menu bar automatically.
    private func updateBadge() {
        guard let button = statusItem?.button else { return }

        let count = store.items.count
        guard count != lastBadgeCount else { return }
        lastBadgeCount = count

        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        if let symbol = NSImage(systemSymbolName: "\(count).circle.fill",
                                accessibilityDescription: "\(count) tasks"),
           let configured = symbol.withSymbolConfiguration(config) {
            configured.isTemplate = true
            button.image = configured
            button.title = ""
        } else {
            // SF Symbols only provides circled numbers up to 50; fall back to text.
            button.image = nil
            button.title = "\(count)"
        }
    }

    /// Re-renders the badge whenever the task list changes.
    ///
    /// `withObservationTracking` fires its `onChange` once, so we re-arm it on
    /// every change. The work hops to the main actor to read the updated state.
    private func observeStore() {
        withObservationTracking {
            _ = store.items
        } onChange: { [self] in
            Task { @MainActor in
                updateBadge()
                observeStore()
            }
        }
    }

    // MARK: - Click handling

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }

        let isSecondaryClick = event.type == .rightMouseUp
            || (event.type == .leftMouseUp && event.modifierFlags.contains(.control))

        if isSecondaryClick {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Bring the app forward and make the popover key so its text
            // fields can immediately accept keyboard input.
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// Shows a small menu (currently just Quit) beneath the status item.
    ///
    /// Temporarily assigning a menu makes the button present it on click;
    /// clearing it afterwards restores the normal left-click action.
    private func showContextMenu() {
        guard let statusItem else { return }

        let menu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit Perch", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Actions

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
