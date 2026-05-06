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
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

	var popover:       NSPopover?
	var statusBarItem: NSStatusItem!

	let aodStore:          AODStore          = AODStore.shared								// Initialize and hold onto an instance of our store
	var backgroundActivity: NSObjectProtocol?												// Prevents macOS from automatically terminating the process when idle

	func applicationDidFinishLaunching(_ aNotification: Notification) {
		if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {		// Don't create the status bar icon if we're just running previews in Xcode, or it keeps stealing the focus
			return;
		}

		// Create the status bar item for the menu bar
		self.statusBarItem = NSStatusBar.system.statusItem(withLength: CGFloat(NSStatusItem.variableLength))
		if let button = self.statusBarItem.button {
			button.image = NSImage(named: "AOD-StatusBar-Idle")
			button.action = #selector(TogglePopover(_:))

			// Watch for server state changes and update the status icon.
			// Task inherits @MainActor isolation from the enclosing context.
			Task { [weak self] in
				guard let self else { return }
				for await isListening in self.aodStore.$isServerListening.values {
					self.UpdateStatusIcon( isListening: isListening )
				}
			}

			// Watch for inbound request changes to update the tooltip.
			Task { [weak self] in
				guard let self else { return }
				for await _ in self.aodStore.$lastInboundRequest.values {
					self.updateTooltip()
				}
			}
		}

		// Listen for wake/sleep notifications
		NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector( sleepListener(_:) ), name: NSWorkspace.screensDidSleepNotification, object: nil)
		NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector( sleepListener(_:) ), name: NSWorkspace.screensDidWakeNotification,  object: nil)

		// Hold a background activity assertion so macOS does not automatically terminate this process when idle
		backgroundActivity = ProcessInfo.processInfo.beginActivity(
			options: .userInitiatedAllowingIdleSystemSleep,
			reason: "AutoOfficeDaemon must run continuously to monitor display state and serve HTTP requests"
		)

		// Try to start the server
		aodStore.didAppFinishLaunching = true
		aodStore.StartHTTPServer( restartIfRunning: false )

		// Report current display sleep state
		aodStore.reportSleepState()
	}

	// Update the status icon based on the listening and enabled state.
	func UpdateStatusIcon( isListening : Bool ) {
		if let button = self.statusBarItem.button {
			if !aodStore.enabled {
				button.image = NSImage( named: "AOD-StatusBar-Idle" )
			} else {
				button.image = NSImage( named: isListening ? "AOD-StatusBar-Connected" : "AOD-StatusBar-NotConnected" )
			}
		}
		updateTooltip()
	}

	func updateTooltip() {
		guard let button = statusBarItem.button else { return }
		var lines = ["AutoOfficeDaemon"]
		if !aodStore.enabled {
			lines.append( "Disabled" )
		} else if aodStore.isServerListening {
			lines.append( "Listening on port \(aodStore.listenPort)" )
		} else {
			lines.append( "Not connected (port \(aodStore.listenPort))" )
		}
		if let req = aodStore.lastInboundRequest {
			let formatter = DateFormatter()
			formatter.timeStyle = .medium
			lines.append( "Last request: \(req.path) at \(formatter.string(from: req.date))" )
		}
		button.toolTip = lines.joined(separator: "\n")
	}

	@objc func TogglePopover(_ sender: AnyObject?) {
		if let button = self.statusBarItem.button {
			if popover?.isShown ?? false {
				popover?.performClose(nil)

			} else {
				if self.popover == nil {
					// Create the SwiftUI view that provides the popover contents.
					let contentView = ContentView()
						.frame(width: 500)

					// Create the popover that will host our UI
					let hostingController = NSHostingController(rootView: contentView)
					hostingController.sizingOptions = .preferredContentSize
					popover = NSPopover()
					popover?.behavior              = .transient
					popover?.contentViewController = hostingController
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

	func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
		guard aodStore.launchAgentIsLoaded else { return .terminateNow }
		Task { [weak self] in
			await self?.aodStore.unloadAgentIfNeeded()
			NSApplication.shared.reply(toApplicationShouldTerminate: true)
		}
		return .terminateLater
	}

	func applicationWillTerminate(_ aNotification: Notification) {
		aodStore.StopHTTPServer()
		popover = nil
	}

	// This common function is used to handle if the display is currently asleep or awake,
	//  storing the state in isAwake.
	@objc func sleepListener(_ aNotification: NSNotification) {
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
