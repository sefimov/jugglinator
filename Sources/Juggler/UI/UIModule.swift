import AppKit
import Foundation
import JugglerCore
import ServiceManagement
import SwiftUI

// Папка Sources/Juggler/UI/ принадлежит задаче UI.
// Сигнатуры функций `UIModule` — контракт с App/JugglerApp.swift и App/SelfTest.swift.

@MainActor
enum UIModule {
    /// Все сцены приложения: меню-бар и окно настроек.
    @SceneBuilder
    static func scenes(environment: AppEnvironment) -> some Scene {
        MenuBarExtra {
            TaskListView(environment: environment, model: environment.model)
                .followsLanguage()
        } label: {
            MenuBarLabel(model: environment.model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(environment: environment)
                .followsLanguage()
        }
    }

    /// Самопроверка UI для `--self-test`: без окон и запросов разрешений.
    static func selfTest() -> [SelfTestResult] {
        UISelfTest.run()
    }
}
