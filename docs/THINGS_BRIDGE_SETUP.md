# Things Bridge Setup

This guide covers installing the Things bridge on another Mac (for example, your Work MacBook).

## Install

1) In sideBar, open Settings -> Things and download the install script.
2) Run the script. It registers the bridge and starts it as a LaunchAgent.
3) Open Things at least once so it has created its local database.

## Cloudflare Tunnel (bridge.seanbetts.com)

Use a Cloudflare Tunnel to expose the local bridge to the Fly backend.

1) Install and login:
   `brew install cloudflared`
   `cloudflared tunnel login`
2) Create the tunnel:
   `cloudflared tunnel create sidebar-bridge`
3) Route DNS:
   `cloudflared tunnel route dns sidebar-bridge bridge.seanbetts.com`
4) Create `~/.cloudflared/config.yml`:
   ```
   tunnel: <TUNNEL_ID>
   credentials-file: /Users/<you>/.cloudflared/<TUNNEL_ID>.json

   ingress:
     - hostname: bridge.seanbetts.com
       service: http://127.0.0.1:8787
     - service: http_status:404
   ```
5) Run the tunnel:
   `cloudflared tunnel run sidebar-bridge`

Verify:
`curl -s https://bridge.seanbetts.com/health`

Update the bridge base URL (so Fly reaches the tunnel):
```
DEVICE_NAME="$(scutil --get ComputerName || hostname)"
DEVICE_ID="$(echo "$DEVICE_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-')"

curl -s -X POST https://sidebar-api.fly.dev/api/v1/things/bridges/register \
  -H "Authorization: Bearer <PAT>" \
  -H "Content-Type: application/json" \
  -d "{\"deviceId\":\"$DEVICE_ID\",\"deviceName\":\"$DEVICE_NAME\",\"baseUrl\":\"https://bridge.seanbetts.com\",\"capabilities\":{\"read\":true,\"write\":true}}"
```

## Auto-start

Bridge auto-start is handled by a LaunchAgent created during install.

To confirm it is running:
`launchctl print gui/$(id -u)/com.sidebar.things-bridge`

Cloudflared auto-start:
`cloudflared service install`

If you want the tunnel to start at boot (before login), install with sudo:
`sudo cloudflared service install`

## Enable Full Disk Access (for repeating metadata)

To read the Things database (for repeating tasks + due dates), grant Full Disk Access to the bridge app:

1) Ensure the app wrapper exists at `/Applications/sideBarThingsBridge.app` (or `~/Applications/sideBarThingsBridge.app` if `/Applications` is not writable).
2) System Settings -> Privacy & Security -> Full Disk Access.
3) Add `sideBarThingsBridge.app`.
4) Restart the bridge:
   `launchctl kickstart -k gui/$(id -u)/com.sidebar.things-bridge`

If Full Disk Access is not granted, the bridge still works, but repeating metadata is unavailable.

## Automation Permission Prompt (Things control)

When the bridge first talks to Things via Apple Events, macOS may prompt:
“python3.x wants access to control Things”. This is expected because the bridge runs inside the
app bundle using an embedded Python runtime. Click **Allow** once and macOS will remember it.

Troubleshooting: Things DB not found

- Re-run the installer to refresh the LaunchAgent. The bridge must be launched as the `sideBarThingsBridge.app` bundle for Full Disk Access to apply.
- After reinstalling, run `launchctl kickstart -k gui/$(id -u)/com.sidebar.things-bridge` and re-check Tasks.

## Verify

- Open sideBar -> Tasks.
- If DB access is missing, a note appears at the bottom of the Tasks sidebar.

## Optional: URL Scheme Token for Writes

To use the Things URL scheme for writes (more reliable than AppleScript), add your Things URL auth token:

1) In Things, copy your URL scheme auth token.
2) In sideBar -> Settings -> Things, paste the token and click **Save Token**.

CLI alternative:
`security add-generic-password -a "things-url-token" -s "sidebar-things-bridge" -w "YOUR_TOKEN" -U`
