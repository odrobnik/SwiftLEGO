import SwiftUI

/// The grey rounded tile shown in place of a thumbnail that has no image, with a
/// symbol in the middle.
struct ThumbnailPlaceholder: View {
    let systemImage: String
    /// Draws the symbol at 60 % of the tile instead of at its natural size.
    var scalesSymbol = false
    var width: CGFloat? = nil
    var height: CGFloat? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(uiColor: .tertiarySystemFill))
            .frame(width: width, height: height)
            .overlay {
                if scalesSymbol {
                    GeometryReader { proxy in
                        let dimension = min(proxy.size.width, proxy.size.height) * 0.6
                        Image(systemName: systemImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: dimension, height: dimension)
                            .foregroundStyle(.secondary)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                } else {
                    Image(systemName: systemImage)
                        .foregroundStyle(.secondary)
                }
            }
    }
}

#Preview {
    HStack {
        ThumbnailPlaceholder(systemImage: "cube.transparent", scalesSymbol: true, width: 80, height: 60)
        ThumbnailPlaceholder(systemImage: "person.fill", width: 64, height: 64)
    }
    .padding()
}
