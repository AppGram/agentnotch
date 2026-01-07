//
//  TodoListView.swift
//  AgentNotch
//
//  Displays Claude Code's current todo list parsed from TodoWrite tool calls
//

import SwiftUI

struct TodoListView: View {
    let todos: [ClaudeTodoItem]
    var maxItems: Int = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(todos.prefix(maxItems))) { todo in
                TodoItemRow(todo: todo)
            }

            if todos.count > maxItems {
                Text("+\(todos.count - maxItems) more...")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.leading, 16)
            }
        }
    }
}

struct TodoItemRow: View {
    let todo: ClaudeTodoItem

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.system(size: 9))
                .foregroundColor(iconColor)
                .frame(width: 12)

            Text(todo.content)
                .font(.system(size: 10, weight: fontWeight))
                .foregroundColor(textColor)
                .lineLimit(1)
                .strikethrough(todo.status == .completed)

            Spacer()
        }
    }

    private var iconName: String {
        switch todo.status {
        case .pending:
            return "circle"
        case .inProgress:
            return "circle.lefthalf.filled"
        case .completed:
            return "checkmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch todo.status {
        case .pending:
            return .white.opacity(0.4)
        case .inProgress:
            return .orange
        case .completed:
            return .green
        }
    }

    private var textColor: Color {
        switch todo.status {
        case .pending:
            return .white.opacity(0.6)
        case .inProgress:
            return .white.opacity(0.9)
        case .completed:
            return .white.opacity(0.4)
        }
    }

    private var fontWeight: Font.Weight {
        todo.status == .inProgress ? .medium : .regular
    }
}

/// Compact inline todo summary showing progress
struct TodoProgressBadge: View {
    let todos: [ClaudeTodoItem]

    private var completedCount: Int {
        todos.filter { $0.status == .completed }.count
    }

    private var inProgressCount: Int {
        todos.filter { $0.status == .inProgress }.count
    }

    private var pendingCount: Int {
        todos.filter { $0.status == .pending }.count
    }

    var body: some View {
        HStack(spacing: 4) {
            if inProgressCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 8))
                        .foregroundColor(.orange)
                    Text("\(inProgressCount)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.orange)
                }
            }

            if completedCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.green)
                    Text("\(completedCount)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.green)
                }
            }

            if pendingCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "circle")
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(0.4))
                    Text("\(pendingCount)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.08))
        .cornerRadius(4)
    }
}

/// Current task display - shows the in-progress item
struct CurrentTaskView: View {
    let todos: [ClaudeTodoItem]

    private var currentTask: ClaudeTodoItem? {
        todos.first { $0.status == .inProgress }
    }

    var body: some View {
        if let task = currentTask {
            HStack(spacing: 6) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)

                Text(task.content)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
            }
        }
    }
}

#Preview {
    let sampleTodos = [
        ClaudeTodoItem(content: "Fix authentication bug", status: .completed),
        ClaudeTodoItem(content: "Implement JSONL parser", status: .inProgress),
        ClaudeTodoItem(content: "Add permission detection", status: .pending),
        ClaudeTodoItem(content: "Create UI components", status: .pending),
        ClaudeTodoItem(content: "Test multi-session support", status: .pending),
        ClaudeTodoItem(content: "Update documentation", status: .pending)
    ]

    VStack(spacing: 20) {
        TodoListView(todos: sampleTodos)
            .padding()
            .background(Color.black.opacity(0.8))
            .cornerRadius(8)

        TodoProgressBadge(todos: sampleTodos)
            .padding()
            .background(Color.black.opacity(0.8))
            .cornerRadius(8)

        CurrentTaskView(todos: sampleTodos)
            .padding()
            .background(Color.black.opacity(0.8))
            .cornerRadius(8)
    }
    .padding()
}
