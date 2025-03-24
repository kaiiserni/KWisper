import Cocoa
import SwiftUI // Needed for @EnvironmentObject potentially later, keep for now

// Protocol to communicate events back to the manager
protocol StatusBarButtonViewDelegate: AnyObject {
    func statusBarButtonDidReceiveMouseDown()
    func statusBarButtonDidLongPress() // Added: Signals when long press timer fires
    func statusBarButtonDidReceiveMouseUp(isLongPress: Bool) // isLongPress now indicates if timer fired before mouse up
}

class StatusBarButtonView: NSView {
    weak var delegate: StatusBarButtonViewDelegate?
    
    var image: NSImage? {
        didSet {
            // Request redraw when the image changes
            needsDisplay = true
        }
    }
    
    private var longPressTimer: Timer?
    private var isMouseDown: Bool = false
    private var longPressDetected: Bool = false
    private let longPressDuration: TimeInterval = 1.0 // 1 second for long press

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Initialization code if needed
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // Draw the image centered in the view
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let image = image else { return }
        
        // Calculate position to draw the image centered
        let imageSize = image.size
        let x = (bounds.width - imageSize.width) / 2
        let y = (bounds.height - imageSize.height) / 2
        let drawRect = NSRect(x: x, y: y, width: imageSize.width, height: imageSize.height)
        
        // The system automatically handles template image rendering based on effectiveAppearance
        image.draw(in: drawRect)
    }

    // Handle Mouse Down Event
    override func mouseDown(with event: NSEvent) {
        isMouseDown = true
        longPressDetected = false
        delegate?.statusBarButtonDidReceiveMouseDown() // Notify delegate immediately if needed

        // Start timer for long press detection
        longPressTimer?.invalidate() // Invalidate any existing timer
        longPressTimer = Timer.scheduledTimer(
            timeInterval: longPressDuration,
            target: self,
            selector: #selector(longPressFired),
            userInfo: nil,
            repeats: false
        )
        
        // Optional: Change appearance on mouse down (e.g., slightly different image)
        // self.image = NSImage(named: "StatusBarIconPressed") // Example
        needsDisplay = true
    }

    // Handle Mouse Up Event
    override func mouseUp(with event: NSEvent) {
        longPressTimer?.invalidate() // Stop the timer
        longPressTimer = nil
        
        if isMouseDown {
            isMouseDown = false
            // Notify delegate about mouse up, indicating if it was a long press
            delegate?.statusBarButtonDidReceiveMouseUp(isLongPress: longPressDetected)
            
            // Reset appearance if changed on mouse down
            // Needs coordination with actual recording state - handled by updateStatusBarIcon
            needsDisplay = true
        }
        longPressDetected = false // Reset flag
    }
    
    // Handle Mouse Dragged Event
    override func mouseDragged(with event: NSEvent) {
        // Intentionally empty - mouse drag doesn't affect functionality
    }

    // Called by the timer if mouse is held down long enough
    @objc private func longPressFired() {
        if isMouseDown { // Ensure mouse is still down
            longPressDetected = true
            delegate?.statusBarButtonDidLongPress()
        }
        longPressTimer = nil
    }
    
    // Ensure the view accepts mouse events
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}
