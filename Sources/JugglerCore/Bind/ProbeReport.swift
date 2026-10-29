import Foundation

/// Binding outcome in a JSON-friendly form (`BindingCaptureResult` is not Codable).
public struct CaptureSummary: Codable, Equatable, Sendable {
    /// `captured`, `needsManualLink` or `failed`.
    public var status: String
    public var source: BindingSource?
    public var binding: TaskBinding?
    public var suggestedTitle: String?
    public var message: String?

    public init(_ result: BindingCaptureResult) {
        switch result {
        case .captured(let binding, let title):
            status = "captured"; source = binding.source; self.binding = binding; suggestedTitle = title; message = nil
        case .needsManualLink(let source, let title):
            status = "needsManualLink"; self.source = source; binding = nil; suggestedTitle = title
            message = BindTexts.manualLinkTitle(source)
        case .failed(let text):
            status = "failed"; source = nil; binding = nil; suggestedTitle = nil; message = text
        }
    }
}

/// JSON for `Jugglinator --probe-frontmost`.
public struct ProbeReport: Codable, Equatable, Sendable {
    public var context: FrontmostContext
    public var diagnostics: ContextDiagnostics
    public var capture: CaptureSummary

    public init(context: FrontmostContext, diagnostics: ContextDiagnostics, capture: BindingCaptureResult) {
        self.context = context
        self.diagnostics = diagnostics
        self.capture = CaptureSummary(capture)
    }

    public func json() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}

/// `--probe-frontmost` options: `--delay <sec>`, `--app <bundle id>`, `--prompt`, `--window-title <title>`.
public struct ProbeOptions: Equatable, Sendable {
    /// Pause before reading, to have time to switch to the right window.
    public var delay: Double = 0
    /// Read the context of the given running app instead of the frontmost one.
    public var bundleID: String?
    /// Allow system permission prompts (Automation for Chrome).
    public var allowPrompts = false
    /// Use this window title instead of the one read: to test ChatGPT thread lookup without Accessibility.
    public var windowTitle: String?

    public init(delay: Double = 0, bundleID: String? = nil, allowPrompts: Bool = false, windowTitle: String? = nil) {
        self.delay = delay
        self.bundleID = bundleID
        self.allowPrompts = allowPrompts
        self.windowTitle = windowTitle
    }

    public static func parse(_ arguments: [String]) -> ProbeOptions {
        var options = ProbeOptions()
        var i = 0
        while i < arguments.count {
            switch arguments[i] {
            case "--delay" where i + 1 < arguments.count:
                options.delay = max(0, min(Double(arguments[i + 1]) ?? 0, 60))
                i += 1
            case "--app" where i + 1 < arguments.count:
                options.bundleID = arguments[i + 1]
                i += 1
            case "--prompt":
                options.allowPrompts = true
            case "--window-title" where i + 1 < arguments.count:
                options.windowTitle = arguments[i + 1]
                i += 1
            default:
                break
            }
            i += 1
        }
        return options
    }
}
