# FadeToSleep — specification

**Tagline:** Start a timer and your Mac's volume and screen glide down together before it pauses music and sleeps.

**Category:** Audio

**Inspired by (paid):** Awaken ($6.99 one-time)

**Frameworks:** SwiftUI, AppKit, CoreAudio, IOKit, UserNotifications, ServiceManagement

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

What the paid app does: Awaken is a 6.99 dollar Mac App Store app whose sleep mode gradually fades out music volume and screen brightness. Several similar sleep timer apps such as Sleepytime at 4.99 dollars and Sleepr at 6.99 dollars are also sold, which shows steady demand from people who fall asleep to podcasts, rain noise or videos on a Mac. Built-in macOS offers no fade at all, so the Mac either keeps blasting audio all night or sleeps abruptly.

Feature set for our clean-room version: Pick a duration with presets of 15, 30, 45, 60 and 90 minutes plus a custom field. During the final fade window, which defaults to 5 minutes, ramp the default output volume down smoothly to zero in small steps, ramp the built-in display brightness down where supported, then pause media by sending the system play pause media key event, and finally put the Mac to sleep or only the display to sleep, as chosen. Offer a cancel button, a plus 15 minutes button, and an option to restore the original volume after wake so mornings are not silent. Roughly 300 lines.

UI spec: A MenuBarExtra with window style. The idle state shows preset buttons and a custom minutes stepper. The running state shows a large countdown, a progress ring, buttons for Add 15 Minutes and Cancel, and a line saying what happens at the end. The menu bar title shows the remaining minutes while a timer runs. Settings has these fields: fade length in minutes, end action picker with Sleep Mac, Sleep display only and Do nothing but pause, fade brightness toggle, restore volume on wake toggle, and launch at login. A global hotkey can be recorded for starting the last used duration.

Technical approach: Read and write the default output device volume scalar through the Core Audio hardware property for the virtual main volume, using the default output device selector. If a device has no volume control, fall back to adjusting each channel scalar, and if neither exists show a note that the device cannot be faded. Drive the fade with a repeating Timer at a one second cadence, computing volume as the starting value multiplied by the remaining fraction of the fade window. For brightness use the IODisplayConnect services in IOKit with the display parameter calls, only for the built-in display, and skip silently otherwise. Posting the media key uses a CGEvent system defined event with the play pause key code. Sleep uses an IOKit power management call for system sleep, and display sleep uses the pmset-equivalent IOKit display wrangler setting. Store settings with AppStorage. UserNotifications posts a notice one minute before the fade begins, requested when the first timer starts. Launch at login uses SMAppService.

Edge cases and error handling: If the user manually changes volume during the fade, detect the difference from the expected value and stop fading to respect them, asking in the menu whether to resume. If the Mac sleeps early or the lid closes, cancel the timer and restore state. If output device changes mid-fade, restart the ramp using the new device's current level. Guard against a duration shorter than the fade window by shrinking the window. Always restore the stored volume and brightness if the app quits during a fade.
