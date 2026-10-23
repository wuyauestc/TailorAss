import SwiftUI

/// The pattern-design route is backed exclusively by the GarmentCode-native
/// parameter model and pattern-only generator. The former approximate
/// The former approximate generator and its preview/export UI have been removed.
struct PatternDesignView: View {
    var body: some View {
        GarmentCodeNativeDesignView()
    }
}
