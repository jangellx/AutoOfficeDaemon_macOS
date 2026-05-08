//
//  AODStore.swift
//  AutoOfficeDaemon
//
//  Created by Joe Angell on 1/16/21.
//

import Foundation
import Network
import SwiftUI
import IOKit.ps
import IOKit.pwr_mgt


struct LogEntry: Identifiable {
	let id      = UUID()
	let date    : Date
	let message : String
	let isError : Bool
}

struct InboundRequest {
	let path : String
	let date : Date
}

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

	@Published var launchAgentIsLoaded : Bool = false
	var quittingAfterAgentLoad : Bool = false

	private static let agentLabel = "joeangell.AutoOfficeDaemon.agent"

	private var agentPlistURL: URL {
		FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent("Library/LaunchAgents/\(AODStore.agentLabel).plist")
	}

	func checkLaunchAgentStatus() {
		launchAgentIsLoaded = FileManager.default.fileExists(atPath: agentPlistURL.path)
	}

	func toggleLaunchAgent() {
		if launchAgentIsLoaded {
			unloadAgent()
		} else {
			loadAgent()
		}
	}

	private func loadAgent() {
		let executablePath = Bundle.main.executableURL!.path

		let plist: [String: Any] = [
			"Label":            AODStore.agentLabel,
			"ProgramArguments": [executablePath],
			"RunAtLoad":        true,
			"KeepAlive":        true
		]

		let launchAgentsDir = FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent("Library/LaunchAgents")

		do {
			try FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
			let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
			try data.write(to: agentPlistURL)
		} catch {
			appendLog("Failed to write agent plist: \(error.localizedDescription)", isError: true)
			return
		}

		let task = Process()
		task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
		task.arguments = ["load", agentPlistURL.path]
		do {
			try task.run()
			task.waitUntilExit()
			if task.terminationStatus == 0 {
				launchAgentIsLoaded = true
				quittingAfterAgentLoad = true
				DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
			} else {
				appendLog("launchctl load exited with status \(task.terminationStatus)", isError: true)
			}
		} catch {
			appendLog("Failed to run launchctl load: \(error.localizedDescription)", isError: true)
		}
	}

	func unloadAgentIfNeeded() {
		guard launchAgentIsLoaded, !quittingAfterAgentLoad else { return }
		unloadAgent()
	}

	private func unloadAgent() {
		let task = Process()
		task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
		task.arguments = ["unload", agentPlistURL.path]
		do {
			try task.run()
			task.waitUntilExit()
		} catch {
			appendLog("Failed to run launchctl unload: \(error.localizedDescription)", isError: true)
		}

		try? FileManager.default.removeItem(at: agentPlistURL)
		launchAgentIsLoaded = false
	}

	// MARK: - Sleep/Wake Handling
	var isAwake      : Bool = true
	var isAwakeAsInt : Int { isAwake ? 1  : 0 }

	// Sleep or wake the display.  "force" is mostly for the "Sleep Display Now" button; most clients respect
	//  the enable state and leave it at false.
	func sleepDisplay( _ goToSleep: Bool , force: Bool = false ) {
		if !enabled && !force {
			return
		}

		// Only do something if we're not already in that state
		if isAwake == !goToSleep {
			return;
		}

		/* This doesn't work on M1 machines, so we just call the command line tool pmset to do it for us.
		 Feels hacky, but it is what it is.

		 let reg    = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/IOResources/IODisplayWrangler")
		 let entry  = "IORequestIdle" as CFString

		 let result = IORegistryEntrySetCFProperty( reg, entry, goToSleep ? kCFBooleanTrue : kCFBooleanFalse );
		 IOObjectRelease(reg);

		 print( "sleep/wake result: \(result) (\(result == KERN_SUCCESS ? "success" : "error" ))" )
		 */

		if goToSleep {
			let task = Process()
			task.launchPath = "/usr/bin/env"
			task.arguments  = ["pmset", "displaysleepnow"]
			task.terminationHandler = { t in
				print("displaysleepnow: \(t.terminationStatus == 0 ? "success" : "error")")
			}
			task.launch()
		} else {
			// Declare remote user activity, which resets the HID idle timer so the system
			// grants the full configured display-sleep timeout before sleeping again.
			var assertionID: IOPMAssertionID = 0
			let result = IOPMAssertionDeclareUserActivity(
				"AutoOfficeDaemon remote wake" as CFString,
				kIOPMUserActiveLocal,
				&assertionID
			)
			print("wake result: \(result == kIOReturnSuccess ? "success" : "error")")
		}

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
					self.appendLog(self.statusString!, isError: true)
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

	// MARK: - HTTP Server via Network.framework

	var listener              : NWListener?							// The NWListener for our HTTP server
	@Published var statusString : String?							// Used to report errors to the user; @Published so SwiftUI re-renders on change

	var isServerRunning : Bool {
		switch listener?.state {
		case .ready, .waiting:
			return true
		default:
			return false
		}
	}

	@Published var isServerListening  : Bool = false				// Used to report to clients (mostly the app delegate) when the server is connected or not.
	@Published var recentLog          : [LogEntry]      = []		// Log of recent errors; shown in the UI
	@Published var lastInboundRequest : InboundRequest? = nil		// Most recent inbound HTTP request; used for the menu bar tooltip
	private var pendingRestart        : Bool    = false				// Signals the .cancelled handler to start a new listener once the port is free

	private let serverQueue = DispatchQueue(label: "com.AutoOfficeDaemon.HTTPServer", qos: .utility)

	// Stop the HTTP server.  listener is nilled in the .cancelled callback rather than here to
	// avoid an EADDRINUSE race where the new bind fires before the OS releases the port.
	func StopHTTPServer() {
		pendingRestart = false			// Explicit stop; don't restart on .cancelled
		statusString = nil
		stopHealthCheck()
		restartTimer?.invalidate()
		restartTimer = nil
		listener?.cancel()				// Async; listener = nil deferred to .cancelled callback
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
					self.appendLog("HTTP Server stopped unexpectedly; restarting...", isError: true)
					self.StartHTTPServer(restartIfRunning: false)
				}
			}
		}
	}

	func stopHealthCheck() {
		healthCheckTimer?.invalidate()
		healthCheckTimer = nil
	}

	private func appendLog(_ message: String, isError: Bool = false) {
		let entry = LogEntry(date: Date(), message: message, isError: isError)
		DispatchQueue.main.async {
			self.recentLog.insert(entry, at: 0)
			if self.recentLog.count > 50 {
				self.recentLog.removeLast()
			}
		}
	}

	var didAppFinishLaunching : Bool = false						// True once the app finishes launching (as set by the app delegate)
	var restartTimer          : Timer?								// If we fail to start, we automatically try again in 10 seconds with this timer
	var healthCheckTimer      : Timer?								// Periodically verifies the server is still running and restarts it if not

	// NWListener.start() is async/callback-driven, so no background thread is needed here.
	func StartHTTPServer( restartIfRunning: Bool ) {
		if !didAppFinishLaunching { return }
		if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return }

		// If any listener still exists (even mid-cancellation), don't try to bind the same port yet.
		// For a restart, signal .cancelled to call StartHTTPServer again once the port is released.
		if listener != nil {
			if restartIfRunning {
				pendingRestart = true
				stopHealthCheck()
				isServerListening = false
				listener?.cancel()			// .cancelled callback will call StartHTTPServer again
			}
			return
		}

		pendingRestart = false
		restartTimer?.invalidate()
		restartTimer = nil
		statusString  = nil

		do {
			let params = NWParameters.tcp
			params.allowLocalEndpointReuse = true
			let portValue   = UInt16(min(max(listenPort, 1), 65535))
			let port        = NWEndpoint.Port(rawValue: portValue)!
			let newListener = try NWListener(using: params, on: port)
			listener        = newListener

			newListener.stateUpdateHandler = { [weak self, weak newListener] state in
				DispatchQueue.main.async {
					guard let self = self, let newListener = newListener else { return }
					guard self.listener === newListener else { return }		// Ignore callbacks from replaced listeners
					switch state {
					case .ready:
						self.statusString      = nil
						self.isServerListening = true
						self.startHealthCheck()
					case .failed(let error):
						newListener.cancel()
						self.stopHealthCheck()
						// Don't nil listener here; .cancelled will do it and schedule the retry
						self.statusString      = "HTTP Server Error: \(error.localizedDescription)"
						self.appendLog("HTTP Server Error: \(error.localizedDescription)", isError: true)
						self.isServerListening = false
					case .cancelled:
						self.listener          = nil		// Port is now free
						self.isServerListening = false
						let shouldRestart = self.pendingRestart
						self.pendingRestart = false
						if shouldRestart {
							// Immediate restart triggered by a settings change
							self.StartHTTPServer(restartIfRunning: false)
						} else if self.statusString != nil, self.enabled, self.restartTimer == nil {
							// Retry after a failure; statusString was set in .failed
							self.restartTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
								guard let self = self, self.listener == nil else { return }
								self.restartTimer = nil
								self.StartHTTPServer(restartIfRunning: false)
							}
						}
					default:
						break
					}
				}
			}

			newListener.newConnectionHandler = { [weak self] connection in
				self?.handleConnection(connection)
			}

			newListener.start(queue: serverQueue)

		} catch {
			statusString      = "HTTP Server Startup Error: \(error.localizedDescription)"
			appendLog("HTTP Server Startup Error: \(error.localizedDescription)", isError: true)
			isServerListening = false
			if restartTimer == nil {
				restartTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
					guard let self = self, self.listener == nil else { return }
					self.restartTimer = nil
					self.StartHTTPServer(restartIfRunning: false)
				}
			}
		}
	}

	// Handle an incoming HTTP connection: read the request, route by path, send a response.
	private func handleConnection(_ connection: NWConnection) {
		connection.start(queue: serverQueue)
		connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
			if let error = error {
				self?.appendLog("Inbound connection error: \(error.localizedDescription)", isError: true)
				connection.cancel()
				return
			}
			guard let self = self, let data = data, !data.isEmpty else {
				connection.cancel()
				return
			}

			let request   = String(data: data, encoding: .utf8) ?? ""
			let firstLine = request.components(separatedBy: "\r\n").first ?? ""
			let parts     = firstLine.components(separatedBy: " ")
			let rawPath   = parts.count > 1 ? parts[1] : "/"
			let path      = rawPath.components(separatedBy: "?").first ?? "/"

			DispatchQueue.main.async {
				self.lastInboundRequest = InboundRequest(path: path, date: Date())
			}

			var statusLine  = "200 OK"
			var contentType = "application/json"
			var body        : String

			switch path {
			case "/":
				contentType = "text/html"
				body        = "AutoOfficeDaemon now running."

			case "/status":
				print("status")
				body = "{\"isAwake\":\(self.isAwakeAsInt)}"

			case "/wake":
				if !self.respondToWakeRequest {
					print("wake; ignored per user setting")
				} else if self.onlyActWhenPluggedIn && !self.isPluggedIn {
					print("wake: ignored per user setting when not plugged in")
				} else {
					print("wake")
					self.sleepDisplay(false)
				}
				body = "{\"isAwake\":\(self.isAwakeAsInt)}"

			case "/sleep":
				if !self.respondToSleepRequest {
					print("sleep; ignored per user setting")
				} else if self.onlyActWhenPluggedIn && !self.isPluggedIn {
					print("sleep: ignored per user setting when not plugged in")
				} else {
					print("sleep")
					self.sleepDisplay(true)
				}
				body = "{\"isAwake\":\(self.isAwakeAsInt)}"

			default:
				statusLine  = "404 Not Found"
				contentType = "text/plain"
				body        = "Not Found"
			}

			let bodyData     = Data(body.utf8)
			let responseText = "HTTP/1.1 \(statusLine)\r\nContent-Type: \(contentType)\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n\(body)"
			connection.send(content: Data(responseText.utf8), completion: .contentProcessed { _ in
				connection.cancel()
			})
		}
	}
}
