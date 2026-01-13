FROM node:20-alpine AS builder
WORKDIR /app

# Copy service package manifest (ignore lock to avoid file: link issues in CI)
COPY backend/services/notification-service/package.json ./
# Copy shared config package to the path expected by file:../../libs/shared/config/node
COPY backend/libs/shared/config /libs/shared/config

RUN npm install --package-lock=false

# Copy sources
COPY backend/services/notification-service/tsconfig.json ./
COPY backend/services/notification-service/src ./src
RUN npm run build

FROM node:20-alpine
WORKDIR /app
ENV NODE_ENV=production

# Copy manifest and install prod deps (no lock)
COPY backend/services/notification-service/package.json ./
COPY backend/libs/shared/config /libs/shared/config
RUN npm install --omit=dev --package-lock=false

COPY --from=builder /app/dist ./dist
CMD ["node", "dist/index.js"]
