//
//  AODStore.swift
//  AutoOfficeDaemon
//
//  Created by Joe Angell on 1/16/21.
//

import Foundation
@preconcurrency import Swifter
import SwiftUI
import IOKit.ps

class AODStore: ObservableObject, @unchecked Sendable {
	// MARK: - Singleton
	static let _SingletonSharedInstance = AODStore()
	class var shared : AODStore {
		return _SingletonSharedInstance
	}

	// MARK: - Init
	init() {
 		let testListenPort = UserDefaults.standard.integer( forKey: "ListenPort" )
 		if testListenPort > 0 {
			// We use listenPort as our "is anything initialized yet", only reading other state if it is
			enabled = UserDefaults.standard.bool( forKey: "Enabled" )

			listenPort = testListenPort

			reportToAddress = UserDefaults.standard.string( forKey: "ReportToAddress" ) ?? "192.168.1.231"

			reportToPort = UserDefaults.standard.integer( forKey: "ReportToPort" )
			if( reportToPort < 1 ) {
				reportToPort = 51931
			}

			reportAccessoryName         = UserDefaults.standard.string( forKey: "ReportAccessoryName" ) ?? "Macintosh"

			waitBeforeReportingSleep    = UserDefaults.standard.bool(    forKey: "WaitBeforeReportingSleep"    )
			secondsBeforeReportingSleep = UserDefaults.standard.integer( forKey: "SecondsBeforeReportingSleep" )

			respondToSleepRequest       = UserDefaults.standard.bool(    forKey: "RespondToSleepRequest"       )
			respondToWakeRequest        = UserDefaults.standard.bool(    forKey: "RespondToWakeRequest"        )

			onlyActWhenPluggedIn        = UserDefaults.standard.bool(    forKey: "OnlyActWhenPluggedIn"        )
 		}
	}

	// MARK: - Settings
	// Settings
	@Published var enabled         : Bool    = true {				// Enable toggle, which also starts/stops the HTTP server
		didSet {
			UserDefaults.standard.set( enabled, forKey: "Enabled" )
			if( enabled ) {
				StartHTTPServer( restartIfRunning: true )
			} else {
				StopHTTPServer()
			}
		}
	}

	@Published var listenPort      : Int	 = 8182 {				// Port to listen on
		didSet {
			UserDefaults.standard.set( listenPort, forKey: "ListenPort" )
			if( enabled ) {
				StartHTTPServer( restartIfRunning: true )
			}
		}
	}

	@Published var reportToAddress : String  = "192.168.1.231" {	// Address to report status changes to
		didSet {
			UserDefaults.standard.set( reportToAddress, forKey: "ReportToAddress" )
		}
	}

	@Published var reportToPort    : Int	 = 51931 {				// Port to use at the above address
		didSet {
			UserDefaults.standard.set( reportToPort, forKey: "ReportToPort" )
		}
	}
	
	@Published var reportAccessoryName: String = "Macintosh" {		// Accessory name used as part of the URL
		didSet {
			UserDefaults.standard.set( reportAccessoryName, forKey: "ReportAccessoryName" )
		}
	}

	@Published var waitBeforeReportingSleep    : Bool = false {		// Toggle if we should wait before reporting display sleep
		didSet {
			UserDefaults.standard.set( waitBeforeReportingSleep, forKey: "WaitBeforeReportingSleep" )
		}
	}

	@Published var secondsBeforeReportingSleep : Int  = 60 {		// Number of seconds to wait before reporting that the display has slept
		didSet {
			UserDefaults.standard.set( secondsBeforeReportingSleep, forKey: "SecondsBeforeReportingSleep" )
		}
	}

	@Published var respondToSleepRequest    : Bool = true {			// Toggle if we should sleep when requested
		didSet {
			UserDefaults.standard.set( respondToSleepRequest, forKey: "RespondToSleepRequest" )
		}
	}

	@Published var respondToWakeRequest    : Bool = true {			// Toggle if we should wake when requested
		didSet {
			UserDefaults.standard.set( respondToWakeRequest, forKey: "RespondToWakeRequest" )
		}
	}

	@Published var onlyActWhenPluggedIn    : Bool = true {			// Toggle if we should react to wake/sleep events when plugged in
		didSet {
			UserDefaults.standard.set( onlyActWhenPluggedIn, forKey: "OnlyActWhenPluggedIn" )
		}
	}

	// MARK: - Sleep/Wake Handling
	// Indicate if the display is currently awake or asleep
	var isAwake      : Bool = true
	var isAwakeAsInt : Int { isAwake ? 1  : 0 }

	// Sleep or wake the diaplsy.  "force" is mostly for the "Sleep Display Now" button; most clients respect
	//  the enable state and leave it at false.
	func sleepDisplay( _ goToSleep: Bool , force: Bool = false ) {
		if !enabled && !force {
			return
		}
		
		// Only do something if we're not already in that state
		if isAwake == !goToSleep {
			return;
		}
		
		/* This doesn't work on M1 machines, so we just call the command line too pmset to do it for us.
		 Feels hacky, but it is what it is.
		 
		 let reg    = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/IOResources/IODisplayWrangler")
		 let entry  = "IORequestIdle" as CFString
		 
		 let result = IORegistryEntrySetCFProperty( reg, entry, goToSleep ? kCFBooleanTrue : kCFBooleanFalse );
		 IOObjectRelease(reg);
		 
		 print( "sleep/wake result: \(result) (\(result == KERN_SUCCESS ? "success" : "error" ))" )
		 */
		
		let task = Process()
		task.launchPath = "/usr/bin/env"

		if goToSleep {
			task.arguments = ["pmset", "displaysleepnow" ]			// Turn off
		} else {
			task.arguments = ["caffeinate", "-u", "-t", "60" ]		// Turn on.  Timeout of one minute; setting it too short causes us to go back to sleep again
		}

		task.launch()
		task.waitUntilExit()

		print( "sleep/wake result: \(task.terminationStatus) (\(task.terminationStatus == 0 ? "success" : "error" ))" )
	}

    // Mark as asleep, then arm the timer to actually send the sleep event
    public func sleepStateChanged( isNowAwake: Bool ) {
        isAwake = isNowAwake

        if isAwake {
            // For awake, we send immediately and clear the sleep report timer
            timer?.invalidate()				// Stop the timer
            timer = nil;					// Clear it to empty
			reportSleepState()

        } else {
            // Arm the timer
            ArmReportTimer();
        }
    }

	var timer : Timer? = nil				// Timer used to wait before sending a sleep "put" request

	// Arm a timer, which we use to send a delayed sleep notification to the remote client
	func ArmReportTimer() {
		if timer != nil {
			// Timer already running; stop it first
            timer?.invalidate()            // Stop the timer
            timer = nil;                   // Clear it to empty
		}

		if !waitBeforeReportingSleep || secondsBeforeReportingSleep == 0 {
			// No delay defined; fire the action now
			reportSleepState()
			return;
		}
		
		// Delay defined; arm the timer
		print( "Arming timer for \(secondsBeforeReportingSleep) seconds to notify remote to sleep" )
		timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(secondsBeforeReportingSleep), repeats: false) { timer in
			self.reportSleepState()
        }
	}

	// Report the sleep change to the client.  We format this to match the homebridge-http-webhooks status report:
	//  https://www.npmjs.com/package/homebridge-http-webhooks
	func reportSleepState() {
		if !enabled {
			return;
		}

		let url  = URL( string: "http://\(reportToAddress):\(reportToPort)/?accessoryId=\(reportAccessoryName)&state=\(isAwake ? "true" : "false")")!
		print( "Calling remote with URL:  \(url)")
		let task = URLSession.shared.dataTask(with: url) { data, response, error in
			DispatchQueue.main.async {
				guard let httpResponse = response as? HTTPURLResponse,
					(200...299).contains(httpResponse.statusCode) else {
					// HTTP response error
					if response != nil {
						self.statusString = "Error: Invalid HTTPURLResponse from report: \(response!)"
					} else {
						self.statusString = "Error: Invalid HTTPURLResponse from report:  (no information available)"
					}
					print( self.statusString! )
					return
				}
				self.statusString = nil
			}
		}
		task.resume()
	}

	// Check to see if the device even has an internal battery.
	// https://developer.apple.com/forums/thread/712711
	var hasInternalBattery : Bool {
		guard
			let psi = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
			let cf  = IOPSCopyPowerSourcesList(psi)?.takeRetainedValue()
		else { return false }

		let psl = cf as [CFTypeRef]
		for ps in psl {
			guard let cfd = IOPSGetPowerSourceDescription(psi, ps)?.takeUnretainedValue() else { return false }

			let d = cfd as! [String: Any]
			guard let psTypeStr = d[kIOPSTypeKey] as? String else { return false }

			if psTypeStr == kIOPSInternalBatteryType {
				return true
			}
		}
    
		return false
	}

	// Check to see if the device has an internal battery and is plugged into it.  Devices without a battery will
	// always return true.  We also assume we're plugged in if any error occurs.
	var isPluggedIn : Bool {
		if !hasInternalBattery {
			return true
		}

		guard let type = IOPSGetProvidingPowerSourceType( nil )?.takeRetainedValue() else {
			return true;
		}

		return (type as String) != kIOPMBatteryPowerKey
	}

	// MARK: - HTTP Server via Swifter
	// Manage the HTTP Server
	var httpServer        : HttpServer?								// THe instance of our Swifter server
	@Published var statusString : String?							// Used to report errors to the user; @Published so SwiftUI re-renders on change

	var isServerRunning : Bool {
		return httpServer != nil && (httpServer?.state == .starting || httpServer?.state == .running)
	}

	@Published var isServerListening : Bool = false					// Used to report to clients (mostly the app delegate) when the server is conencted or not.

	// Stop the HTTP server
	func StopHTTPServer() {
		statusString = nil
		stopHealthCheck()
		if !isServerRunning {
			return;
		}

		httpServer?.stop()
		httpServer = nil
		isServerListening = false
	}

	// Periodically verify the server is still running; restart it if it has stopped unexpectedly.
	// Must be called from the main thread (timer is scheduled on the main RunLoop).
	func startHealthCheck() {
		healthCheckTimer?.invalidate()
		healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
			guard let self = self, self.enabled else { return }
			if !self.isServerRunning {
				self.isServerListening = false
				if self.restartTimer == nil {
					self.statusString = "HTTP Server stopped unexpectedly; restarting..."
					self.StartHTTPServer(restartIfRunning: false)
				}
			}
		}
	}

	func stopHealthCheck() {
		healthCheckTimer?.invalidate()
		healthCheckTimer = nil
	}

	// Start the HTTP server in anothet thread
	var didAppFinishLaunching : Bool = false						// True once the app finishes launching (as set by the app delegate)
	var restartTimer          : Timer?								// If we fail to start, we automatically try again in 10 seconds with this timer
	var healthCheckTimer      : Timer?								// Periodically verifies the server is still running and restarts it if not
	func StartHTTPServer( restartIfRunning: Bool ) {
		if !didAppFinishLaunching {
			return;
		}

		if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
			// Don't run the server we're just running previews in Xcode
			return
		}

		// Handle what to do if the server is running
		if isServerRunning {
			if restartIfRunning {
				StopHTTPServer()
			} else {
				return
			}
		}

		// Stop the restart timer
		if restartTimer != nil {
			restartTimer?.invalidate()
			restartTimer = nil
		}

		// Start the server in a thread
		statusString = nil
		DispatchQueue.global(qos: .utility).async { [unowned self] in
			do {
				let server = HttpServer()
				httpServer = server;
				
				server["/"] = { _ in
					.ok( .htmlBody("AutoOfficeDaemon now running.") )
				}

				server["/status"] = { _ in
					print( "status" )
					return .ok( .json(  ["isAwake":self.isAwakeAsInt] ) )
				}

				server["/wake"] = { _ in
					if !self.respondToWakeRequest {
						print( "wake; ignored per user setting" )
					} else if self.onlyActWhenPluggedIn && !self.isPluggedIn {
						print( "wake: ignored per user setting when not plugged in" )
					} else {
						print( "wake" )
						self.sleepDisplay( false )
					}

					return .ok( .json(  ["isAwake":self.isAwakeAsInt] ) )
				}

				server["/sleep"] = { _ in
					if !self.respondToSleepRequest {
						print( "sleep; ignored per user setting" )
					} else if self.onlyActWhenPluggedIn && !self.isPluggedIn {
						print( "sleep: ignored per user setting when not plugged in" )
					} else {
						print( "sleep" )
						self.sleepDisplay( true )
					}

					return .ok( .json(  ["isAwake":self.isAwakeAsInt] ) )
				}

				try httpServer?.start( UInt16( min( listenPort, 65535 ) ), forceIPv4: true )
				DispatchQueue.main.async {
					self.statusString      = nil
					self.isServerListening = true
					self.startHealthCheck()
				}

			} catch {
				httpServer = nil
				DispatchQueue.main.async {
					self.statusString      = "HTTP Server Startup Error: \(error.localizedDescription)"
					self.isServerListening = false
					self.restartTimer = Timer.scheduledTimer( withTimeInterval: 10.0, repeats: false ) { _ in
						if self.isServerRunning {
							return
						}
						self.StartHTTPServer( restartIfRunning: false )
						self.restartTimer = nil
					}
				}
			}
		}
	}
}

