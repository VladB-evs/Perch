//
//  MenuBarView.swift
//  Perch
//
//  The checklist shown inside the menu bar popover.
//

import SwiftUI

/// A clean, Hotlist-style checklist in dark mode.
///
/// Every task is a rounded square checkbox next to its inline-editable title,
/// and there is always one empty slot at the bottom for adding the next task:
/// type and press Return (focus stays put so you can keep adding). The active
/// row is gently highlighted. Clearing a task's text and leaving its field
/// removes it.
///
/// The panel hugs its content and only scrolls once it grows past `maxHeight`.
/// There is deliberately no chrome — quitting is handled by right-clicking the
/// menu bar icon (see `AppDelegate`).
struct MenuBarView: View {

    /// Identifies which text field currently holds keyboard focus.
    private enum Field: Hashable {
        case task(UUID)
        case draft
    }

    /// Reports the checklist's natural height so the popover can hug its content.
    private struct ContentHeightKey: PreferenceKey {
        nonisolated static var defaultValue: CGFloat { 0 }
        nonisolated static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    /// Shared data store, injected by the app.
    let store: TodoStore

    /// Text for the always-present empty slot.
    @State private var draftTitle = ""

    /// Measured height of the checklist content.
    @State private var contentHeight: CGFloat = 240

    /// Tracks the focused text field.
    @FocusState private var focusedField: Field?

    /// Tasks currently checked and animating out before deletion.
    @State private var completingIDs: Set<UUID> = []

    private let panelWidth: CGFloat = 380
    private let maxHeight: CGFloat = 520

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(store.items) { item in
                    taskRow(item)
                }
                draftRow
            }
            .padding(8)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                }
            )
        }
        .scrollIndicators(.never)
        .frame(width: panelWidth, height: min(max(contentHeight, 1), maxHeight))
        .background(Color.black)
        .preferredColorScheme(.dark)
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
        .onChange(of: focusedField) { previous, _ in
            // Remove a task whose text was cleared once you leave its field.
            if case let .task(id)? = previous, isBlank(taskTitle(id)) {
                store.delete(id: id)
            }
        }
        .onAppear {
            // Land in the empty slot, ready to type, each time it opens.
            DispatchQueue.main.async { focusedField = .draft }
        }
    }

    // MARK: - Rows

    /// One existing task: rounded checkbox + inline-editable title.
    private func taskRow(_ item: TodoItem) -> some View {
        HStack(spacing: 12) {
            checkbox(isOn: completingIDs.contains(item.id)) {
                complete(item.id)
            }

            TextField("", text: titleBinding(for: item.id))
                .font(.system(size: 16))
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .task(item.id))
                .onSubmit { focusedField = nil }
        }
        .rowStyle(highlighted: focusedField == .task(item.id))
        .transition(.opacity)
    }

    /// The always-present empty slot for adding the next task.
    private var draftRow: some View {
        HStack(spacing: 12) {
            checkboxShape(isOn: false)
                .opacity(0.5)

            TextField("", text: $draftTitle)
                .font(.system(size: 16))
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .draft)
                .onSubmit(commitDraft)
        }
        .rowStyle(highlighted: focusedField == .draft)
    }

    // MARK: - Checkbox

    private func checkbox(isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            checkboxShape(isOn: isOn)
        }
        .buttonStyle(.plain)
    }

    /// A rounded-square checkbox styled for a dark background.
    private func checkboxShape(isOn: Bool) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(isOn ? Color.accentColor : Color.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(isOn ? Color.clear : Color.white.opacity(0.22), lineWidth: 1.5)
            )
            .overlay(
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .opacity(isOn ? 1 : 0)
            )
            .frame(width: 26, height: 26)
    }

    // MARK: - Helpers & actions

    private func taskTitle(_ id: UUID) -> String {
        store.items.first(where: { $0.id == id })?.title ?? ""
    }

    private func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func titleBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { taskTitle(id) },
            set: { store.updateTitle($0, for: id) }
        )
    }

    /// Commits the empty slot into a real task and keeps focus there so the
    /// user can keep adding tasks one after another.
    private func commitDraft() {
        store.add(title: draftTitle)
        draftTitle = ""
        focusedField = .draft
    }

    /// Marks a task complete: briefly shows the check, then fades the row out
    /// and removes it from the list — which also deletes it from local storage.
    private func complete(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.15)) {
            _ = completingIDs.insert(id)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.3))
            withAnimation(.easeInOut(duration: 0.3)) {
                store.delete(id: id)
            }
            completingIDs.remove(id)
        }
    }
}

// MARK: - Row layout

private extension View {
    /// Shared padding + active-row highlight for every checklist row.
    func rowStyle(highlighted: Bool) -> some View {
        self
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(highlighted ? Color.white.opacity(0.07) : Color.clear)
            )
    }
}
