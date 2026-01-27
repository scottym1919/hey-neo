import SwiftUI

@main
struct HeyNeoWatchApp: App {
    @StateObject private var connectivity = WatchPhoneConnectivity()
    
    var body: some Scene {
        WindowGroup {
            HomeWatchView()
                .environmentObject(connectivity)
        }
    }
}
