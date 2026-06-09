import SwiftUI
import PacketPewKit

@main
struct PacketPewApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    init() {
        // Non-graphical smoke test: `swift run PacketPew --selftest`.
        if CommandLine.arguments.contains("--selftest") {
            for line in runSelfTest() { print(line) }
            let sem = DispatchSemaphore(value: 0)
            var asyncLog: [String] = []
            Task.detached {
                asyncLog = await runAsyncSelfTest()
                sem.signal()
            }
            sem.wait()
            for line in asyncLog { print(line) }
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup("Packet Pew") {
            RootView()
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        #endif
    }
}
