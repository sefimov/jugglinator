import AppKit
import Foundation
import JugglerCore
import SwiftUI

// Папка Sources/Juggler/UI/ принадлежит задаче UI.
// Сигнатуры функций `UIModule` — контракт с App/JugglerApp.swift и App/SelfTest.swift.
// Сцены ниже — минимальный каркас, который UI заменяет настоящим списком и настройками.

@MainActor
enum UIModule {
    /// Все сцены приложения: меню-бар и окно настроек.
    @SceneBuilder
    static func scenes(environment: AppEnvironment) -> some Scene {
        MenuBarExtra {
            StubMenuContent(environment: environment, model: environment.model)
        } label: {
            StubMenuBarLabel(model: environment.model)
        }
        Settings {
            StubSettingsView(environment: environment)
        }
    }

    static func selfTest() -> [SelfTestResult] {
        []
    }
}

private struct StubMenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Text(model.currentTaskNumber.map(String.init) ?? "J")
    }
}

private struct StubMenuContent: View {
    let environment: AppEnvironment
    @ObservedObject var model: AppModel

    var body: some View {
        let now = Date()
        if model.tasks.isEmpty {
            Text("Задач пока нет")
        }
        ForEach(Array(model.tasks.enumerated()), id: \.element.id) { index, task in
            Button {
                environment.switcher.activateTask(id: task.id)
            } label: {
                let mark = task.id == model.document.lastActiveTaskID ? "▸ " : ""
                let done = task.isDone ? " ✓" : ""
                Text("\(mark)\(index + 1). \(task.title)\(done) — \(Staleness.absenceText(lastVisited: task.lastVisitedAt, now: now))")
            }
        }
        Divider()
        Button("Новая задача") {
            model.update { $0.tasks.append(JugglerTask(title: "Новая задача")) }
        }
        Button("Сделать задачей текущий чат") {
            environment.perform(.bindCurrentChat)
        }
        Divider()
        SettingsLink {
            Text("Настройки…")
        }
        Button("Выйти") {
            NSApp.terminate(nil)
        }
    }
}

private struct StubSettingsView: View {
    let environment: AppEnvironment

    var body: some View {
        Form {
            Section("Хоткеи") {
                SwitchModule.hotkeySettingsView(environment: environment)
            }
        }
        .padding()
        .frame(width: 420)
    }
}
