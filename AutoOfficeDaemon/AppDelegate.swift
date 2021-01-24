//
//  AppDelegate.swift
//  AutoOfficeDaemon
//
//  Created by Joe Angell on 1/16/21.
//

import Cocoa
import SwiftUI
import Combine

// The app delegate is used to add a menu bar item for our UI.  The code is mostly
// copied from here: https://medium.com/@acwrightdesign/creating-a-macos-menu-bar-application-using-swiftui-54572a5d5f87
@main
class AppDelegate: NSObject, NSApplicationDelegate {

	var popover:       NSPopover?
	var statusBarItem: NSStatusItem!
	
	let aodStore:      AODStore = AODStore.shared																		// Initialize and hold onto an instance of our store
	var isServerListeningCanceller : AnyCancellable?																		// We have to hold onto this or else our sink() will stop working

	func applicationDidFinishLaunching(_ aNotification: Notification) {
		if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {									// Don't create the status bar icon if we're just running previews in Xcode, or it keeps stealing the focus
			return;
		}

		// Create the status bar item for the menu bar
		self.statusBarItem = NSStatusBar.system.statusItem(withLength: CGFloat(NSStatusItem.variableLength))
		if let button = self.statusBarItem.button {
			button.image = NSImage(named: "AOD-StatusBar-Idle")
			button.action = #selector(TogglePopover(_:))

			isServerListeningCanceller = aodStore.$isServerListening																			// Listen for chagnes to the server state
				.sink {
					self.UpdateStatusIcon( isListening: $0 )
				}
		}

		NSApp.activate(ignoringOtherApps: true)

		// Listen for wake/sleep notifications
		NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector( sleepListener(_:) ), name: NSWorkspace.screensDidSleepNotification, object: nil)
		NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector( sleepListener(_:) ), name: NSWorkspace.screensDidWakeNotification,  object: nil)
		
		// Try to start the server
		aodStore.didAppFinishLaunching = true
		aodStore.StartHTTPServer( restartIfRunning: false )
		
		// Report current display sleep state
		aodStore.reportSleepState()
	}

	// Update the status icon based on the listening and enabled state.  For some reason we have to pass the listening state, or we always get false.  Weird.
	func UpdateStatusIcon( isListening : Bool ) {
		if let button = self.statusBarItem.button {
			if !aodStore.enabled {
				button.image = NSImage( named: "AOD-StatusBar-Idle" )
			} else {
				button.image = NSImage( named: isListening ? "AOD-StatusBar-Connected" : "AOD-StatusBar-NotConnected" )
			}
		}
	}

	@objc func TogglePopover(_ sender: AnyObject?) {
		if let button = self.statusBarItem.button {
			if popover?.isShown ?? false {
				popover?.performClose(sender)

			} else {
				if self.popover == nil {
					// Create the SwiftUI view that provides the popover contents.
					let contentView = ContentView()

					// Create the popover that will host our UI
					popover = NSPopover()
					popover?.contentSize           = NSSize(width: 500, height: 500)
					popover?.behavior              = .transient
					popover?.contentViewController = NSHostingController(rootView: contentView)
				}

				popover?.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
				popover?.contentViewController?.view.window?.becomeKey()
			}
		}
	}

	// The popover should close when the user clicks elsewhere, but it seems to stick open for some reason.  This might help...?
	@objc func applicationWillResignActive(_ notification: Notification) {
		if popover?.isShown ?? false {
			popover?.close()
			popover = nil
		}
	}

	func applicationWillTerminate(_ aNotification: Notification) {
		// Insert code here to tear down your application
		popover = nil
	}

    // This common function is used to handle if the display is currently asleep or awake,
    //  storing the state in isAwake.
    @objc func sleepListener(_ aNotification:NSNotification) {
        if aNotification.name == NSWorkspace.screensDidSleepNotification {
            print("Display slept; arming timer to send message to remote")
            aodStore.sleepStateChanged( isNowAwake: false )

        } else if aNotification.name == NSWorkspace.screensDidWakeNotification {
            print("Display woke; stopping timer and sending message to remote")
            aodStore.sleepStateChanged( isNowAwake: true )

        } else {
            print("Unknown sleep/wake event")
        }
    }

}

