import SwiftUI

@main
struct PayApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
                .onOpenURL { _ in }   // sochipay:// — quay về từ app ngân hàng, chỉ cần mở app
        }
    }
}
