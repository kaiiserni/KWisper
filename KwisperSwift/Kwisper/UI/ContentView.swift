import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSImage(named: "StatusBarIcon") ?? NSImage())
                .resizable()
                .frame(width: 64, height: 64)
            
            Text("Kwisper")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Record and transcribe with a keyboard shortcut")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Spacer()
                .frame(height: 30)
            
            Text("Press Command+Option+V to start recording")
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            
            Spacer()
            
            Button("Settings") {
                // TODO: Implement settings action
            }
            .buttonStyle(.bordered)
        }
        .frame(width: 400, height: 300)
        .padding()
    }
}