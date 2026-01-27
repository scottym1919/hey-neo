import SwiftUI

@main
struct HeyNeoApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var speechRecognizer = SpeechRecognizer()
    
    // Gateway client is created with settings
    @State private var gateway: GatewayClient?
    
    // Watch connectivity manager
    @StateObject private var watchConnectivity = WatchConnectivityManager()
    
    var body: some Scene {
        WindowGroup {
            Group {
                if let gateway = gateway {
                    HomeView(gateway: gateway, speechRecognizer: speechRecognizer)
                        .environmentObject(settings)
                        .environmentObject(watchConnectivity)
                } else {
                    ProgressView("Loading...")
                        .task {
                            gateway = GatewayClient(settings: settings)
                            
                            // Set up watch connectivity with gateway
                            watchConnectivity.setGateway(gateway!)
                            
                            // Auto-connect if configured
                            if settings.autoConnect && settings.isConfigured {
                                await gateway?.connect()
                            }
                        }
                }
            }
        }
    }
}
