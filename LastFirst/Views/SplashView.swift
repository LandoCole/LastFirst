import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            Image("IconMark")
                .resizable()
                .scaledToFit()
                .frame(width: 120)
        }
    }
}
