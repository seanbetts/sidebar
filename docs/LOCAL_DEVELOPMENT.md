# Local Development (Native)

This guide sets up native (non-Docker) development with hot reload for backend and frontend. It uses production Supabase and R2, so read the safety notes carefully. Secrets are loaded from Doppler.

## Quick Start

```bash
# 1. Create local environment overrides
cp .env.example .env.local

# 2. Edit .env.local
# - Set AUTH_DEV_MODE=true
# - Set DEFAULT_USER_ID to a dedicated test user
# - Set API_URL=http://localhost:8001
# - Set APP_ENV=local
# - Configure Doppler (DOPPLER_TOKEN or doppler login)
# - (Optional) APNs env vars for push: APNS_ENV, APNS_TOPIC, APNS_TOPIC_IOS, APNS_TOPIC_MACOS

# 3. Install dependencies
cd backend && uv sync && cd ..
cd frontend && npm install && cd ..

# 4. Validate setup
./scripts/health-check.sh

# 5. Run migrations (Supabase)
./scripts/migrate.sh --supabase upgrade head

# 6. Start development
./dev.sh start
```

## Daily Workflow

```bash
# Ensure on dev branch
git checkout dev

# Start services
./dev.sh start

# Check status
./dev.sh status

# View logs
./dev.sh logs              # Both
./dev.sh logs backend      # Backend only
./dev.sh logs frontend     # Frontend only

# Cleanup stale processes (if ports are stuck)
./dev.sh cleanup

# Run tests
./scripts/test.sh all

# Stop services
./dev.sh stop
```

## iOS App (Xcode)

1) Copy `ios/sideBar/Config/SideBar.local.xcconfig.example` to `ios/sideBar/Config/SideBar.local.xcconfig`.
2) Update API and Supabase values in the local xcconfig (escape `//` in URLs).
3) Open `ios/sideBar/sideBar.xcodeproj` in Xcode.
4) In the `sideBar` target, set the Debug base configuration to `Config/SideBar.xcconfig`.
5) Build/run in the simulator.

Run iOS unit tests from the CLI:

```bash
./scripts/test-ios.sh
xcodebuild -project ios/sideBar/sideBar.xcodeproj -scheme sideBar -destination 'platform=iOS Simulator,name=iPhone 15' test
```

## Safety Notes (Production Data)

You are connecting to production Supabase and R2.

- All database changes are permanent.
- File uploads/deletes in R2 are real.
- Use a dedicated test user ID to keep data scoped.
- Consider a separate Supabase project for long-term development.

### Auth Dev Mode Guard

`AUTH_DEV_MODE=true` is only allowed when `APP_ENV=local` (or tests). This prevents accidental auth bypass in production.

## Common Commands

```bash
./scripts/health-check.sh
./scripts/migrate.sh --supabase upgrade head
./scripts/test.sh backend
./dev.sh restart
```


## Troubleshooting

### Port Already in Use

```bash
lsof -i :8001
lsof -i :3000
```

### Backend Won't Start

```bash
tail -n 200 /tmp/sidebar-backend.log
cd backend && uv sync
```

### Frontend Proxy Not Working

```bash
echo $API_URL
curl http://localhost:8001/api/health
```

## URLs

- Frontend: http://localhost:3000
- Backend: http://localhost:8001
- API Docs: http://localhost:8001/docs
