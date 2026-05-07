//
//  ContentView.swift
//  AutoOfficeDaemon
//
//  Created by Joe Angell on 1/16/21.
//

import SwiftUI

struct ContentView: View {
	@ObservedObject var aodStore = AODStore.shared
	
	var body: some View {
		VStack {
			VStack {
				ZStack {
					Rectangle()
						.foregroundColor( Color( red: 0.5, green: 0.65, blue: 0.7 ) )
						.padding( .leading,  -20 )
						.padding( .trailing, -20 )
						.shadow( radius: 10 )
					HStack {
						Spacer()
						Text( "AutoOfficeDaemon" )
							.font( .title )
							.foregroundColor(.white)
							.shadow( radius: 10 )
						Spacer()
					}
				}
				.frame( height: 80 )
				.padding(0)
				
				HStack {
					Spacer()
					Text( "Enable" )
						.font( .title2 )
						.bold()
					Toggle( "Enabled", isOn: $aodStore.enabled )
						.toggleStyle( SwitchToggleStyle( tint: Color.green ) )
						.labelsHidden()
						.frame( height: 40 )
					Spacer()
				}
				
				
				// Connections
				HStack {
					Text( "Connections" )
						.font( .headline )
					Spacer()
				}
				
				VStack {
					HStack {
						Text( "Listening port" )
							.frame( width: 100, alignment: .trailing )
						
						TextField( "8182", value: $aodStore.listenPort, formatter: NumberFormatter() )
							.frame( width: 60 )
						Spacer()
					}
					
					HStack {
						Text( "Report status to" )
							.frame( width: 100, alignment: .trailing )
						TextField( "192.168.1.231", text: $aodStore.reportToAddress )
							.frame( width: 200 )
						Text( "on port" )
						TextField( "51931", value: $aodStore.reportToPort, formatter: NumberFormatter() )
							.frame( width: 60 )
						Spacer()
					}
					
					HStack {
						Text( "Accessory ID" )
							.frame( width: 100, alignment: .trailing )
						
						TextField( "Macintosh", text: $aodStore.reportAccessoryName )
							.frame( width: 200 )
						Spacer()
					}
				}
				.padding( .leading, 10 )
				
				
				// Options
				Spacer()
					.frame( height: 20 )
				HStack {
					Text( "Options" )
						.font( .headline )
					Spacer()
				}
				
				VStack( alignment: .leading ) {
					HStack {
						Spacer()
							.frame( width: 100 )
						
						VStack( alignment: .leading ) {
							HStack {
								Toggle( "Wait", isOn: $aodStore.waitBeforeReportingSleep )
								TextField( "60", value: $aodStore.secondsBeforeReportingSleep, formatter: NumberFormatter() )
									.frame( width: 30 )
									.disabled( !aodStore.waitBeforeReportingSleep )
								Text( "seconds before reporting display sleep" )
								Spacer()
							}
							
							Toggle( "Respond to Sleep Requests", isOn: $aodStore.respondToSleepRequest )
								.help( "When true, sleep requests received by remote clients will cause this machine's display to sleep." )
							
							Toggle( "Respond to Wake Requests",  isOn: $aodStore.respondToWakeRequest  )
								.help( "When true, sleep requests received by remote clients will cause this machine's display to wake." )
							
							Toggle( "Act only when plugged in", isOn: $aodStore.onlyActWhenPluggedIn )
								.help( "When true, sleep and wake requests are only acted on when the device is plugged into an external power source.  Only applies when the an internal battery is available" )
								.disabled( !aodStore.hasInternalBattery )
							
							HStack {
								Spacer()
									.frame( width: 30 )
								Text( aodStore.isPluggedIn ? "● Plugged in" : "● Not plugged in" )
								.font( .caption )
								.foregroundColor( aodStore.isPluggedIn ? .green : .secondary )
							}
						}
					}
				}
				.padding( .leading, 10 )
				
				
				// Utilities
				Spacer()
					.frame( height: 20 )
				HStack {
					Text( "Utilities" )
						.font( .headline )
					Spacer()
				}

				HStack {
					Spacer()
						.frame( width: 100 )
					Button( action: { aodStore.toggleLaunchAgent() } ) {
						Text( aodStore.launchAgentIsLoaded ? "Unload Agent" : "Load Agent" )
							.frame( width: 100 )
					}
					.help( aodStore.launchAgentIsLoaded
						? "Unloads the LaunchAgent. launchd will stop its managed instance."
						: "Loads the LaunchAgent and quits this instance. launchd takes over from here." )
					Text( aodStore.launchAgentIsLoaded ? "● Loaded" : "● Not loaded" )
						.font( .caption )
						.foregroundColor( aodStore.launchAgentIsLoaded ? .green : .secondary )
					Spacer()
				}
				.padding( .bottom, 6 )
				
				Divider()
					.padding( .horizontal, 40 )

				HStack {
					Spacer()

					// Sleep Now
					Button(action: {
						aodStore.sleepDisplay( true, force: true )
					}) {
						Text( "Sleep Display Now" )
							.frame( width: 150 )
					}

					Spacer()

					// Quit
					Button(action: {
						aodStore.unloadAgentIfNeeded()
						NSApplication.shared.terminate(nil)
					}) {
						Text( "Quit" )
							.frame( width: 150 )
					}
					Spacer()
				}


				// Recent Log
				Spacer()
					.frame( height: 20 )
				HStack {
					Text( "Recent Log" )
						.font( .headline )
					Spacer()
				}

				if aodStore.recentLog.isEmpty {
					Text( "No errors logged yet" )
						.font( .caption )
						.foregroundColor( .secondary )
				} else {
					ScrollView {
						VStack( alignment: .leading, spacing: 3 ) {
							ForEach( aodStore.recentLog ) { entry in
								HStack( alignment: .top, spacing: 6 ) {
									Text( entry.date, style: .time )
										.font( .caption.monospacedDigit() )
										.foregroundColor( .secondary )
										.frame( width: 65, alignment: .trailing )
									Text( entry.message )
										.font( .caption )
										.foregroundColor( entry.isError ? .red : .primary )
										.frame( maxWidth: .infinity, alignment: .leading )
								}
							}
						}
						.padding( 4 )
					}
					.frame( height: 100 )
					.background( Color( NSColor.textBackgroundColor ) )
					.clipShape( RoundedRectangle( cornerRadius: 4 ) )
				}
			}
			.padding( .leading,  20 )
			.padding( .trailing, 20 )
			.onAppear { aodStore.checkLaunchAgentStatus() }
			
			VStack {
				ZStack( alignment: .top ) {
					Rectangle()
						.foregroundColor( Color( red: 0.3, green: 0.5, blue: 0.6 ) )
						.frame( height: 60 )
						.shadow( radius: 10 )
					HStack( alignment: .top ) {
						Text( "Status" )
							.foregroundColor( .white )
						Text( aodStore.statusString ?? "OK" )
							.foregroundColor( .white )
							.lineLimit( 2 )
						Spacer()
					}
					.padding( 5 )
					.padding( .horizontal, 3 )
				}
			}
			.padding( 0 )
		}
	}
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
			.frame( width: 500 )
    }
}
