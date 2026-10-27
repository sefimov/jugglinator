import Foundation

/// Итог привязки в виде, пригодном для JSON (`BindingCaptureResult` не Codable).
public struct CaptureSummary: Codable, Equatable, Sendable {
    /// `captured`, `needsManualLink` или `failed`.
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

/// JSON для `Juggler --probe-frontmost`.
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

/// Ключи `--probe-frontmost`: `--delay <сек>`, `--app <bundle id>`, `--prompt`.
public struct ProbeOptions: Equatable, Sendable {
    /// Пауза перед чтением, чтобы успеть переключиться на нужное окно.
    public var delay: Double = 0
    /// Читать контекст указанного запущенного приложения, а не переднего.
    public var bundleID: String?
    /// Разрешить системные запросы разрешений (Automation для Chrome).
    public var allowPrompts = false

    public init(delay: Double = 0, bundleID: String? = nil, allowPrompts: Bool = false) {
        self.delay = delay
        self.bundleID = bundleID
        self.allowPrompts = allowPrompts
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
            default:
                break
            }
            i += 1
        }
        return options
    }
}
