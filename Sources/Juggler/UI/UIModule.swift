import AppKit
import Foundation
import JugglerCore
import ServiceManagement
import SwiftUI

// The Sources/Juggler/UI/ folder belongs to the UI task.
// `UIModule` function signatures are a contract with App/JugglerApp.swift and App/SelfTest.swift.

@MainActor
enum UIModule {
    /// All app scenes: the menu bar and the settings window.
    @SceneBuilder
    static func scenes(environment: AppEnvironment) -> some Scene {
        MenuBarExtra {
            TaskListView(environment: environment, model: environment.model)
                .followsLanguage()
        } label: {
            MenuBarLabel(model: environment.model, contextProvider: environment.bind.contextProvider)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(environment: environment)
                .followsLanguage()
        }
    }

    /// UI self-test for `--self-test`: no windows and no permission prompts.
    static func selfTest() -> [SelfTestResult] {
        UISelfTest.run()
    }
}
