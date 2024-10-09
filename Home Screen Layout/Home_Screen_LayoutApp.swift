import SwiftUI

@main
struct Home_Screen_LayoutApp: App {
    @StateObject private var server = Server()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(server)
        }
    }
}
