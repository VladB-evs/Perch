//
//  TodoItem.swift
//  Perch
//
//  A single to-do list entry.
//

import Foundation

/// A single task in the to-do list.
///
/// The type is `Codable` so the whole list can be serialized to disk,
/// `Identifiable` so SwiftUI can track rows efficiently, and `Hashable`
/// for value-based diffing. The `id` is stable across launches, which
/// keeps a task's identity intact once it has been persisted.
struct TodoItem: Identifiable, Codable, Hashable {

    /// Stable unique identifier, preserved across app launches.
    let id: UUID

    /// The user-facing task description.
    var title: String

    /// Creation timestamp, used to keep the list in a stable order.
    let createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
    }
}
