import Foundation
import JugglerCore

/// Корень композиции: создаёт и связывает компоненты UI, SWITCH и BIND.
///
/// Компоненты берутся только из фабрик модулей своих папок:
/// `BindModule` (Sources/Juggler/Bind/), `SwitchModule` (Sources/Juggler/Switch/),
/// `UIModule` (Sources/Juggler/UI/). Задачи второго этапа меняют реализации внутри
/// своих модулей и не трогают этот файл; итоговую связку проверяет PACK.
@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment.makeLive()

    let model: AppModel
    let bind: BindServices
    let binder: CurrentChatBinding
    let card: TransitionCardPresenting
    let switcher: TaskSwitching
    let hotkeys: HotkeyRegistering

    private(set) var isStarted = false

    init(
        model: AppModel,
        bind: BindServices,
        binder: CurrentChatBinding,
        card: TransitionCardPresenting,
        switcher: TaskSwitching,
        hotkeys: HotkeyRegistering
    ) {
        self.model = model
        self.bind = bind
        self.binder = binder
        self.card = card
        self.switcher = switcher
        self.hotkeys = hotkeys
    }

    /// Рабочая сборка. `store` можно подменить (например, для самопроверки).
    static func makeLive(store: TaskStore = TaskStore()) -> AppEnvironment {
        let model = AppModel(store: store)
        model.load()
        let bind = BindModule.makeServices()
        let card = SwitchModule.makeCardPresenter()
        let binder = BindModule.makeCurrentChatBinder(model: model, services: bind, card: card,
                                                      toggleHotkey: SwitchModule.bindHotkey)
        let switcher = SwitchModule.makeSwitcher(model: model, bind: bind, card: card)
        let hotkeys = SwitchModule.makeHotkeys()
        return AppEnvironment(model: model, bind: bind, binder: binder, card: card, switcher: switcher, hotkeys: hotkeys)
    }

    /// Запуск после `applicationDidFinishLaunching`: регистрирует хоткеи.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        hotkeys.start { [weak self] action in
            self?.perform(action)
        }
    }

    func stop() {
        hotkeys.stop()
        isStarted = false
    }

    /// Единая точка для действий хоткеев и пунктов меню.
    func perform(_ action: HotkeyAction) {
        switch action {
        case .nextTask: switcher.switchTask(.next)
        case .previousTask: switcher.switchTask(.previous)
        case .bindCurrentChat: binder.toggleCurrentChat()
        }
    }
}
