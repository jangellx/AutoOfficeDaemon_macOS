# AutoOfficeDaemon_macOS
 
Latest version of my AutoOfficeDaemon.  Written in Swift using SwiftUI for configuration, and using [Swifter](https://github.com/jmcarpenter2/swifter) for the HTTP server.  It requires macOS 11.1 for certain SwiftUI features, and since it was just for me I didn't bother to add compatibility for older operating systems.
[Details about the setup can be found on my site](http://www.tmproductions.com/projects-blog/2021/1/24/auto-office-through-homekit}.

The daemon's job is twofold:
- Listen for display wake and sleep events from macOS and report them to a report machine using the HTTP protocol defined by [homebridge-http-webhooks](https://www.npmjs.com/package/homebridge-http-webhooks).
- Listen for incomming connections via HTTP to wake or sleep the Mac's display.

When combined with homebridge-http-webhooks, this allows any number of Macs to be displyed in and controlled by HomeKit.  Homebridge does not need to be running on the Mac that is to be controlled.  I have it running on three Macs, one of which hosts the Homebridge instance.

## Basic Homebridge Configuration

The wake/sleep URLs are simply called "wake" and sleep".  Here's a simple example config entry for [homebridge-http-webhooks](https://www.npmjs.com/package/homebridge-http-webhooks).

```xml
 "switches": [
  {
   "id": "myiMac",
   "name": "iMac",
   "on_url": "http://192.168.1.234:8183/wake",
   "off_url": "http://192.168.1.234:8183/sleep"
  }
 ]
```

The iMac now shows up as a switch the Home app, and it can be woken or slept directly from there.  It will also show the current display sleep status.

## Features

The daemon is configured entirely through its status bar interface.  This includes the accessory ID in Homebridge, the server address and port, and the port to listen on for remote connections.

Another feature of the daemon include a "wait X seconds before reporting sleep" feature, which is useful when the display has gone to sleep while you were looking at another machine and you want a buffer to wake it back up again before your HomeKit automatiion runs.

Finally is to ignore remote wake or sleep requests.  I use this on one of my less-used Macs to ensure that it always sleeps with the others, but it requires that I explicitly wake it.

## Swifter HTTP Server
I used [Swifter](https://github.com/jmcarpenter2/swifter) for the HTTP server due to its simplicity.  I was going to use SwiftNIO, but it was overkill for what I needed.  I do wish Swifter had more proper documentation and didn't require me to dive into barely commented source files, but using this package saved me a lot of time, and other than that I can't really complain.  It does its job and does it well.

![](https://images.squarespace-cdn.com/content/v1/510dbdc1e4b037c811a42c5a/1611529216004-ZAIBM0NT8NN509ENO0FN/ke17ZwdGBToddI8pDm48kHJEfLQYED5-xOEnUNUwgJZ7gQa3H78H3Y0txjaiv_0fDoOvxcdMmMKkDsyUqMSsMWxHk725yiiHCCLfrh8O1z5QHyNOqBUUEtDDsRWrJLTmYyyZeBpvmvOdJdoDyhppNjvFG0W_q_70fzJvFNhzDEd5N4HgfvD-fLi6OkD5kLFb/Screen+Shot+2021-01-24+at+5.59.45+PM.png?format=2500w)
