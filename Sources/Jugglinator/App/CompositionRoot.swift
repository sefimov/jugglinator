import Foundation
import JugglerCore

/// Composition root: creates and wires the UI, SWITCH and BIND components.
///
/// Components come only from the module factories in their folders:
/// `BindModule` (Sources/Jugglinator/Bind/), `SwitchModule` (Sources/Jugglinator/Switch/),
/// `UIModule` (Sources/Jugglinator/UI/), `MCPModule` (Sources/Jugglinator/MCP/). Second-stage tasks change implementations inside
/// their modules and don't touch this file; PACK verifies the final wiring.
@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment.makeLive()

    let model: AppModel
    let bind: BindServices
    let binder: CurrentChatBinding
    let card: TransitionCardPresenting
    let switcher: TaskSwitching
    let doneToggler: DoneToggling
    let hotkeys: HotkeyRegistering
    /// The MCP server for AI assistants (`nil` in wiring self-tests that don't need it).
    let mcp: MCPServerController?

    private(set) var isStarted = false

    init(
        model: AppModel,
        bind: BindServices,
        binder: CurrentChatBinding,
        card: TransitionCardPresenting,
        switcher: TaskSwitching,
        doneToggler: DoneToggling,
        hotkeys: HotkeyRegistering,
        mcp: MCPServerController? = nil
    ) {
        self.model = model
        self.bind = bind
        self.binder = binder
        self.card = card
        self.switcher = switcher
        self.doneToggler = doneToggler
        self.hotkeys = hotkeys
        self.mcp = mcp
    }

    /// Production build. `store` can be substituted (e.g., for the self-test).
    static func makeLive(store: TaskStore = TaskStore()) -> AppEnvironment {
        let model = AppModel(store: store)
        model.load()
        let bind = BindModule.makeServices()
        let card = SwitchModule.makeCardPresenter()
        let binder = BindModule.makeCurrentChatBinder(model: model, services: bind, card: card,
                                                      toggleHotkey: SwitchModule.bindHotkey)
        let switcher = SwitchModule.makeSwitcher(model: model, bind: bind, card: card)
        let doneToggler = SwitchModule.makeDoneToggler(model: model, bind: bind, card: card,
                                                       addWithDialogs: { [weak binder] in binder?.bindCurrentChat() })
        let hotkeys = SwitchModule.makeHotkeys()
        let mcp = MCPModule.makeServer(model: model, bind: bind, switcher: switcher, card: card)
        return AppEnvironment(model: model, bind: bind, binder: binder, card: card, switcher: switcher,
                              doneToggler: doneToggler, hotkeys: hotkeys, mcp: mcp)
    }

    /// Start after `applicationDidFinishLaunching`: registers hotkeys, starts the MCP server if it is enabled.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        hotkeys.start { [weak self] action in
            self?.perform(action)
        }
        mcp?.startIfEnabled()
    }

    func stop() {
        mcp?.stop()
        hotkeys.stop()
        isStarted = false
    }

    /// Single entry point for hotkey and menu item actions.
    func perform(_ action: HotkeyAction) {
        switch action {
        case .nextTask: switcher.switchTask(.next)
        case .previousTask: switcher.switchTask(.previous)
        case .bindCurrentChat: binder.toggleCurrentChat()
        case .toggleDone: doneToggler.toggleDone()
        }
    }
}
