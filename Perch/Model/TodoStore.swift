//
//  TodoStore.swift
//  Perch
//
//  Owns the to-do list and persists it to local storage.
//

import Foundation
import Observation
import os

/// The single source of truth for the to-do list.
///
/// Tasks are stored as a JSON file inside the app's Application Support
/// directory. Under the App Sandbox this resolves to a private location
/// inside the app's container, so no special entitlement is required and
/// nothing ever leaves the machine — storage is entirely local.
///
/// Every mutation writes through to disk immediately (atomically), so the
/// list survives quitting the app and restarting the computer.
///
/// The store is `@MainActor`-isolated because it backs the UI. The on-disk
/// payload is tiny, so the synchronous file I/O performed here is fast and
/// keeps the design simple and predictable.
@Observable
@MainActor
final class TodoStore {

    /// The current list of tasks, ordered oldest-first.
    ///
    /// Externally read-only: callers mutate the list through the methods
    /// below so that every change is persisted.
    private(set) var items: [TodoItem] = []

    /// Absolute location of the JSON store on disk.
    private let storeURL: URL

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Perch",
        category: "TodoStore"
    )

    // MARK: - Lifecycle

    init() {
        // Configure coders for stable, human-readable on-disk output.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        // Resolve …/Application Support/<bundle id>/todos.json
        let fileManager = FileManager.default
        let baseDirectory = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory

        let folderName = Bundle.main.bundleIdentifier ?? "Perch"
        let appDirectory = baseDirectory.appendingPathComponent(folderName, isDirectory: true)
        self.storeURL = appDirectory.appendingPathComponent("todos.json", isDirectory: false)

        // Make sure the directory exists before the first save.
        try? fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)

        load()
    }

    // MARK: - Mutations

    /// Appends a new task. Blank or whitespace-only titles are ignored.
    func add(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        items.append(TodoItem(title: trimmed))
        save()
    }

    /// Updates the title of an existing task (used for inline editing).
    ///
    /// Persists on every change. The payload is tiny, so the cost of saving
    /// per keystroke is negligible and it guarantees edits are never lost.
    func updateTitle(_ newTitle: String, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }

        items[index].title = newTitle
        save()
    }

    /// Removes the task with the given id.
    func delete(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    // MARK: - Persistence

    /// Loads the saved tasks from disk, tolerating a missing or corrupt file.
    private func load() {
        let data: Data
        do {
            data = try Data(contentsOf: storeURL)
        } catch {
            // Most commonly the file simply doesn't exist yet (first launch).
            // That's expected, so start with an empty list.
            return
        }

        do {
            items = try decoder.decode([TodoItem].self, from: data)
        } catch {
            // The file exists but couldn't be read. Rather than crash, start
            // fresh; the next save will overwrite the unreadable file.
            logger.error("Failed to decode saved tasks; starting empty. \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Writes the current list to disk atomically.
    private func save() {
        do {
            let data = try encoder.encode(items)
            try data.write(to: storeURL, options: [.atomic])
        } catch {
            // Non-fatal: the in-memory list stays usable for this session.
            logger.error("Failed to save tasks: \(error.localizedDescription, privacy: .public)")
        }
    }
}
