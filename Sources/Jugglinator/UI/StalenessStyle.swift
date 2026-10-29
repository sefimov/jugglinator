import JugglerCore
import SwiftUI

extension StalenessLevel {
    /// Color of "away N min" by staleness level.
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
