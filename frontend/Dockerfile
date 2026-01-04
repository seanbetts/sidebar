FROM node:20 AS builder

WORKDIR /app

# Install all dependencies (including dev) for the build
ENV NPM_CONFIG_PRODUCTION=false
ENV NPM_CONFIG_OMIT=

# Copy package files
COPY package*.json ./

# Install dependencies with cache mount to speed up rebuilds
RUN --mount=type=cache,target=/root/.npm \
    npm install --include=dev

# Copy source code
COPY . .

# Allow larger heap during build to avoid OOM in Docker
ENV NODE_OPTIONS=--max-old-space-size=4096

# Build the app with Vite (SvelteKit plugin handles SSR + adapter)
RUN npm run build

# Production image
FROM node:20-slim

WORKDIR /app

# Copy built app from builder
COPY --from=builder /app/build ./build
COPY --from=builder /app/package.json ./
COPY --from=builder /app/node_modules ./node_modules

ENV NODE_ENV=production
ENV PORT=3000

EXPOSE 3000

CMD ["node", "build"]
