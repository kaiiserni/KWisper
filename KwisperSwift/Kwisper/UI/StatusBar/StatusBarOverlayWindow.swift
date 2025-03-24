import Cocoa
import SwiftUI

class StatusBarOverlayWindow: NSWindow {
    private let recordingIndicator = NSVisualEffectView()
    private let pulseAnimation: CABasicAnimation
    
    init() {
        // Create a pulse animation for the recording indicator
        pulseAnimation = CABasicAnimation(keyPath: "opacity")
        pulseAnimation.fromValue = 1.0
        pulseAnimation.toValue = 0.5
        pulseAnimation.duration = 0.5
        pulseAnimation.autoreverses = true
        pulseAnimation.repeatCount = Float.infinity
        
        // Initialize the window
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 16, height: 16),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        // Configure window properties
        self.isOpaque = false
        self.hasShadow = false
        self.backgroundColor = .clear
        self.level = .statusBar
        self.ignoresMouseEvents = true
        
        // Configure the visual effect view for the indicator
        recordingIndicator.frame = NSRect(x: 0, y: 0, width: 16, height: 16)
        recordingIndicator.material = .hudWindow
        recordingIndicator.state = .active
        recordingIndicator.wantsLayer = true
        recordingIndicator.layer?.cornerRadius = 8
        recordingIndicator.layer?.masksToBounds = true
        
        // Add a red circle inside the effect view
        let circleView = NSView(frame: NSRect(x: 2, y: 2, width: 12, height: 12))
        circleView.wantsLayer = true
        circleView.layer?.backgroundColor = NSColor.red.cgColor
        circleView.layer?.cornerRadius = 6
        recordingIndicator.addSubview(circleView)
        
        // Set the visual effect view as the window's content view
        self.contentView = recordingIndicator
    }
    
    func show() {
        // Position the window near the status bar
        if let screen = NSScreen.main {
            let statusBarHeight: CGFloat = 22
            let xPos = screen.frame.width - 30 // Position near status bar icons
            let yPos = screen.frame.height - statusBarHeight / 2 - 8 // Center with status bar
            self.setFrameOrigin(NSPoint(x: xPos, y: yPos))
        }
        
        // Start the animation and show the window
        self.recordingIndicator.layer?.add(pulseAnimation, forKey: "pulse")
        self.makeKeyAndOrderFront(nil)
    }
    
    override func close() {
        // Stop the animation and close the window
        self.recordingIndicator.layer?.removeAnimation(forKey: "pulse")
        super.close()
    }
}