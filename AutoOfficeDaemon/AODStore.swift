//
//  AODStore.swift
//  AutoOfficeDaemon
//
//  Created by Joe Angell on 1/16/21.
//

import Foundation
import Swifter
import SwiftUI

class AODStore : ObservableObject {
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

			reportAccessoryName = UserDefaults.standard.string( forKey: "ReportAccessoryName" ) ?? "Macintosh"

			waitBeforeReportingSleep    = UserDefaults.standard.bool(    forKey: "WaitBeforeReportingSleep"    )
			secondsBeforeReportingSleep = UserDefaults.standard.integer( forKey: "SecondsBeforeReportingSleep" )

			respondToSleepRequest       = UserDefaults.standard.bool(    forKey: "RespondToSleepRequest"       )
			respondToWakeRequest        = UserDefaults.standard.bool(    forKey: "RespondToWakeRequest"        )
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

	@Published var respondToSleepRequest    : Bool = true {		// Toggle if we should sleep when requested
		didSet {
			UserDefaults.standard.set( respondToSleepRequest, forKey: "RespondToSleepRequest" )
		}
	}

	@Published var respondToWakeRequest    : Bool = true {		// Toggle if we should wake when requested
		didSet {
			UserDefaults.standard.set( respondToWakeRequest, forKey: "RespondToWakeRequest" )
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

		let reg   = IORegistryEntryFromPath(kIOMasterPortDefault, "IOService:/IOResources/IODisplayWrangler")
		let entry = "IORequestIdle" as CFString

		IORegistryEntrySetCFProperty( reg, entry, goToSleep ? kCFBooleanTrue : kCFBooleanFalse );
		IOObjectRelease(reg);
	}


    // Mark as asleep, then arm the timer to actually send the sleep event
    public func sleepStateChanged( isNowAwake: Bool ) {
        isAwake = isNowAwake

        if isAwake {
            // For awake, we send immediately and clear the sleep report timer
			reportSleepState()
            timer?.invalidate()				// Stop the timer
            timer = nil;					// Clear it to empty

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
			guard let httpResponse = response as? HTTPURLResponse,
				(200...299).contains(httpResponse.statusCode) else {
				// HTTP response error
				if response != nil {
					self.statusString = "Error: Invalid HTTPURLResponse from report: \(response!)"
				} else {
					self.statusString = "Error: Invalid HTTPURLResponse from report:  (no information available)"
				}

				print( self.statusString! );
				return
			}

			self.statusString = nil
		}
		task.resume()
	}

	// MARK: - HTTP Server via Swifter
	// Manage the HTTP Server
	var httpServer   : HttpServer?									// THe instance of our Swifter server
	var statusString : String?										// Used to report errors to the user

	var isServerRunning : Bool {
		return httpServer != nil && (httpServer?.state == .starting || httpServer?.state == .running)
	}

	@Published var isServerListening : Bool = false					// Used to report to clients (mostly the app delegate) when the server is conencted or not.

	// Stop the HTTP server
	func StopHTTPServer() {
		statusString = nil
		if !isServerRunning {
			return;
		}

		httpServer?.stop()
		httpServer = nil
		isServerListening = false
	}

	// Start the HTTP server in anothet thread
	var didAppFinishLaunching : Bool = false						// True once the app finishes launching (as set by the app delegate)
	var restartTimer          : Timer?								// If we fail to start, we automatically try again in 10 seconds with this timer
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

		// Star the server ina  thread
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
					return .ok( .json(  ["isAwake":isAwakeAsInt] ) )
				}

				server["/wake"] = { _ in
					if !self.respondToWakeRequest {
						print( "wake; ignored per user setting" )
					} else {
						print( "wake" )
						sleepDisplay( false )
					}

					return .ok( .json(  ["isAwake":isAwakeAsInt] ) )
				}

				server["/sleep"] = { _ in
					if !self.respondToSleepRequest {
						print( "sleep; ignored per user setting" )
					} else {
						print( "sleep" )
						sleepDisplay( true )
					}

					return .ok( .json(  ["isAwake":isAwakeAsInt] ) )
				}

				try httpServer?.start( UInt16( listenPort ), forceIPv4: true )
				DispatchQueue.main.async {
					isServerListening = true
				}

			} catch {
				// Error
				statusString       = "HTTP Server Startup Error: \(error.localizedDescription)"
				httpServer         = nil

				DispatchQueue.main.async {
					isServerListening = false
				}
				
				// Try again in 10 seconds
				restartTimer = Timer.scheduledTimer( withTimeInterval: 10.0, repeats: false ) { _ in
					if !self.isServerRunning {
						return;
					}

					self.StartHTTPServer( restartIfRunning: false )
					self.restartTimer = nil
				}
			}
		}
	}
}

