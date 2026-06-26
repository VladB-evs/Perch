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
        let isCompleting = completingIDs.contains(item.id)
        return HStack(spacing: 12) {
            checkbox(isOn: isCompleting) {
                complete(item.id)
            }

            if isCompleting {
                // While checking off: dimmed title with an animated strikethrough.
                CompletingTitle(text: item.title)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("", text: titleBinding(for: item.id))
                    .font(.system(size: 16))
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .task(item.id))
                    .onSubmit { focusedField = nil }
                    .onKeyPress(.delete) {
                        // Backspace on an already-empty task: jump up; the now
                        // focus-less empty row is removed by onChange below.
                        guard taskTitle(item.id).isEmpty else { return .ignored }
                        focusUp(from: item.id)
                        return .handled
                    }
            }
        }
        .rowStyle(highlighted: !isCompleting && focusedField == .task(item.id))
        .transition(.asymmetric(
            insertion: .scale(scale: 0.85).combined(with: .opacity),
            removal: .opacity
        ))
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
                .onKeyPress(.delete) {
                    // Backspace on the empty slot jumps to the last task.
                    guard draftTitle.isEmpty else { return .ignored }
                    focusUp(from: nil)
                    return .handled
                }
        }
        .rowStyle(highlighted: false)
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
                    .scaleEffect(isOn ? 1 : 0.3)   // springs in for a little "pop"
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

    /// Moves focus to the task above the current one — or the last task when
    /// coming from the empty slot — so pressing Delete on an empty row walks up
    /// the list. The emptied row left behind is removed by the focus-change
    /// handler in `body`.
    private func focusUp(from currentTaskID: UUID?) {
        let ids = store.items.map(\.id)
        guard !ids.isEmpty else { focusedField = nil; return }

        guard let currentTaskID, let index = ids.firstIndex(of: currentTaskID) else {
            // Coming from the empty slot → focus the last task.
            focusedField = .task(ids[ids.count - 1])
            return
        }

        if index > 0 {
            focusedField = .task(ids[index - 1])     // the task above
        } else if ids.count > 1 {
            focusedField = .task(ids[1])             // was the top one → take the next
        } else {
            focusedField = nil                       // deleting the only task
        }
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
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
            store.add(title: draftTitle)
        }
        draftTitle = ""
        focusedField = .draft
    }

    /// Marks a task complete: pops the checkbox and draws the strikethrough,
    /// lets it sit a beat, then fades the row out and removes it — which also
    /// deletes it from local storage.
    private func complete(_ id: UUID) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
            _ = completingIDs.insert(id)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.55))
            withAnimation(.easeInOut(duration: 0.35)) {
                store.delete(id: id)
            }
            completingIDs.remove(id)
        }
    }
}

// MARK: - Completing title

/// The task title shown while it is being checked off: dimmed, with a
/// strikethrough that animates across from leading to trailing edge.
private struct CompletingTitle: View {
    let text: String
    @State private var struck = false

    var body: some View {
        Text(text)
            .font(.system(size: 16))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(.secondary)
                    .frame(height: 1.5)
                    .scaleEffect(x: struck ? 1 : 0, anchor: .leading)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.28)) { struck = true }
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
