import SwiftUI
import Playgrounds
import Foundation

struct ContentView: View {
    init() {
        AccessibilityManager().inspectRibbon()
    }
    
    var body: some View {
        Text("Hello, world!")
            .padding()
    }
}

#Preview {
    ContentView()
}

#Playground {
}
