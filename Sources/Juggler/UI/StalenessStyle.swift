import JugglerCore
import SwiftUI

extension StalenessLevel {
    /// Цвет «не был N мин» по уровню старения.
    var color: Color {
        switch self {
        case .never: return .secondary
        case .fresh: return .green
        case .aging: return .yellow
        case .stale: return .orange
        case .forgotten: return .red
        }
    }
}
