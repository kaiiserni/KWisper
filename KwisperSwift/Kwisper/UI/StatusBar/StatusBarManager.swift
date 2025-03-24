import AppKit
import SwiftUI

// Delegate protocol for StatusBarManager
protocol StatusBarManagerDelegate: AnyObject {
    func statusBarManagerDidRequestStartRecording()
    func statusBarManagerDidRequestStopRecording()
    func statusBarManagerDidRequestTogglePopover()
    func statusBarManagerDidRequestQuit()
}

class StatusBarManager: NSObject, StatusBarButtonViewDelegate { // Conform to new delegate
    private var statusItem: NSStatusItem!
    private var buttonView: StatusBarButtonView! // Use the custom view
    
    // Add delegate property
    weak var delegate: StatusBarManagerDelegate?
    
    // Track if recording was started by the long press
    private var isLongPressRecordingActive = false

    func setupStatusBar() {
        // Create the status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        // Create and configure the custom button view
        buttonView = StatusBarButtonView(frame: NSRect(x: 0, y: 0, width: NSStatusItem.squareLength, height: NSStatusItem.squareLength))
        buttonView.delegate = self // Set the delegate
        
        // Load initial image (Asset Catalog handles appearance)
        if let initialImage = NSImage(named: "StatusBarIconWhite") {
            buttonView.image = initialImage
        }
        
        // Assign the custom view to the status item
        statusItem.view = buttonView
        
        // Remove old button setup if any existed
        // if let button = statusItem.button { ... } // This block is no longer needed
    }

    // Update the image on the custom view
    func updateStatusBarIcon(isRecording: Bool, isTranscribing: Bool = false) {
        guard let view = buttonView else { return }
        
        var imageName: String
        if isRecording {
            imageName = "StatusBarIconWhiteRecording" // White recording version
        } else if isTranscribing {
            imageName = "StatusBarIconWhiteTranscribing" // White transcribing version
        } else {
            imageName = "StatusBarIconWhite" // Default white version
        }
        
        // Load the image - Asset Catalog handles light/dark appearance automatically
        if let newImage = NSImage(named: imageName) {
            view.image = newImage
        } else {
            // Fallback to original (black) icon if white version doesn't exist yet
            let fallbackName = isRecording ? "StatusBarIconRecording" : 
                              (isTranscribing ? "StatusBarIconTranscribing" : "StatusBarIcon")
            if let fallbackImage = NSImage(named: fallbackName) {
                view.image = fallbackImage
            }
        }
    }
    
    // MARK: - StatusBarButtonViewDelegate Methods
    
    func statusBarButtonDidReceiveMouseDown() {
        // Prepare for action, main logic is in mouseUp
    }
    
    // Called when the long press timer fires in the button view
    func statusBarButtonDidLongPress() {
        isLongPressRecordingActive = true // Set flag *before* calling delegate
        delegate?.statusBarManagerDidRequestStartRecording()
    }

    // Called when the mouse button is released over the button view
    func statusBarButtonDidReceiveMouseUp(isLongPress: Bool) {
        if isLongPress {
            // If the timer fired (long press), releasing the mouse means stop recording
            if isLongPressRecordingActive {
                 delegate?.statusBarManagerDidRequestStopRecording()
                 isLongPressRecordingActive = false // Reset flag
            }
        } else {
            // It was a short click
            if !isLongPressRecordingActive {
                showStatusBarMenu()
            } else {
                 // Reset the flag if there was a race condition
                 isLongPressRecordingActive = false
            }
        }
    }
    
    private func showStatusBarMenu() {
        // Create the context menu
        let menu = NSMenu()
        
        // Add Settings item
        let settingsItem = NSMenuItem(title: "Settings", action: #selector(handleSettingsMenuItemClicked), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        // Add separator
        menu.addItem(NSMenuItem.separator())
        
        // Add Quit item
        let quitItem = NSMenuItem(title: "Quit", action: #selector(handleQuitMenuItemClicked), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        // Display the menu
        if let statusBarButton = statusItem.view {
            // Position the menu below the status bar item
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: statusBarButton)
        }
    }
    
    @objc private func handleSettingsMenuItemClicked() {
        print("Settings menu item clicked")
        // Directly show the popover instead of going through the delegate cycle
        showPopover()
    }
    
    @objc private func handleQuitMenuItemClicked() {
        print("Quit menu item clicked")
        delegate?.statusBarManagerDidRequestQuit()
    }

    // Keep togglePopover logic, but it will be called via the delegate now
    @objc func togglePopover() {
        // This might still be needed if triggered elsewhere, but primary path is delegate
        // Check if popover is shown or not to decide action
        if let popover = popover, popover.isShown {
            hidePopover()
        } else {
            // Let the delegate handle the request, which might call showPopover internally
            delegate?.statusBarManagerDidRequestTogglePopover()
        }
    }
    
    // --- Popover related methods ---
    private var popover: NSPopover?
    
    func showPopover() { // Make it public so delegate can call it
        // Prevent showing popover if recording was just started via long press
        if isLongPressRecordingActive {
             print("Popover show cancelled, long press recording active.")
             return
        }
        
        // Prevent showing if already shown
        if let popover = popover, popover.isShown {
            return
        }
        
        if popover == nil {
            // Create settings view using SwiftUI
            let settingsView = SettingsView() // Assuming SettingsView exists
            let hostingController = NSHostingController(rootView: settingsView)
            
            popover = NSPopover()
            popover?.contentViewController = hostingController
            popover?.contentSize = NSSize(width: 350, height: 500) // Increased size
            popover?.behavior = .transient
            // Allow scrolling via mouse wheel
            popover?.animates = true 
            // popover?.delegate = self // Add if needed
        }

        if let view = statusItem.view { // Use statusItem.view
            popover?.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
            // Ensure popover becomes key and frontmost
             popover?.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
        }
    }

    func hidePopover() { // Make it public so delegate can call it
        popover?.performClose(nil)
        // Consider setting popover = nil here or in a delegate method if needed
    }
    
    // Optional: Implement NSPopoverDelegate if needed, e.g., to clear popover on close
    // func popoverDidClose(_ notification: Notification) {
    //     popover = nil
    // }
}
