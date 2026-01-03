# Things Bridge Setup

This guide covers installing the Things bridge on another Mac (for example, your Work MacBook).

## Install

1) In sideBar, open Settings -> Things and download the install script.
2) Run the script. It registers the bridge and starts it as a LaunchAgent.
3) Open Things at least once so it has created its local database.

## Enable Full Disk Access (for repeating metadata)

To read the Things database (for repeating tasks + due dates), grant Full Disk Access to the bridge app:

1) Ensure the app wrapper exists at `~/Applications/sideBarThingsBridge.app`.
2) System Settings -> Privacy & Security -> Full Disk Access.
3) Add `sideBarThingsBridge.app`.
4) Restart the bridge:
   `launchctl kickstart -k gui/$(id -u)/com.sidebar.things-bridge`

If Full Disk Access is not granted, the bridge still works, but repeating metadata is unavailable.

## Verify

- Open sideBar -> Tasks.
- If DB access is missing, a note appears at the bottom of the Tasks sidebar.

