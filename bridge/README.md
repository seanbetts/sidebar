# Things Bridge (macOS)

Minimal bridge service that will proxy Things data to the sideBar backend.

## Setup

1) Create a virtual environment and install dependencies:
```
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

2) Export a shared token and run the server:
```
export THINGS_BRIDGE_TOKEN=your-bridge-token
export THINGS_BRIDGE_PORT=8787
python things_bridge.py
```

3) Register the bridge with the backend:
```
curl -s -X POST http://localhost:8001/api/things/bridges/register \
  -H "Authorization: Bearer YOUR_PAT" \
  -H "Content-Type: application/json" \
  -d '{"deviceId":"mac-studio","deviceName":"Mac Studio","baseUrl":"http://127.0.0.1:8787","capabilities":{"read":true,"write":true}}'
```

## Endpoints

- `GET /health`
- `GET /lists/{scope}` (today | inbox | upcoming | projects | areas)
- `POST /apply`
