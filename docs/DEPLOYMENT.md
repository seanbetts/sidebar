# Deployment Guide

## Maintenance Mode

The app supports a maintenance/holding page that can be toggled via environment variable.

### Enable Maintenance Mode in Vercel

1. Go to your Vercel project dashboard
2. Navigate to **Settings** → **Environment Variables**
3. Add a new environment variable:
   - **Name**: `MAINTENANCE_MODE`
   - **Value**: `true`
   - **Environment**: Production (or whichever environment you want)
4. Click **Save**
5. Redeploy your application or wait for the next deployment

### Disable Maintenance Mode

To show the full app again:

1. Go to **Settings** → **Environment Variables** in Vercel
2. Either:
   - Delete the `MAINTENANCE_MODE` variable, OR
   - Change its value to `false`
3. Redeploy

### Test Locally

To test the holding page locally:

```bash
# Navigate to frontend directory
cd frontend

# Run with maintenance mode enabled
MAINTENANCE_MODE=true npm run dev
```

Visit `http://localhost:3000` and you should see the holding page.

To run normally:

```bash
cd frontend
npm run dev
```

### Preview Deployments

By default, preview deployments will NOT show the maintenance page unless you explicitly set `MAINTENANCE_MODE=true` for the Preview environment in Vercel.

This allows you to:
- Keep production in maintenance mode
- Test the real app in preview deployments
- Share preview links with stakeholders before going live

## Vercel Deployment Settings

### Build Settings

- **Framework Preset**: SvelteKit
- **Build Command**: `npm run build` (from frontend directory)
- **Output Directory**: `.svelte-kit/output`
- **Install Command**: `npm install`

### Root Directory

Set to `frontend` since your SvelteKit app is in the frontend directory.

### Environment Variables Required

See `.env.example` for all required environment variables.
