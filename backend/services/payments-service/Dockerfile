FROM node:20-alpine AS builder
WORKDIR /app

COPY backend/services/payments-service/package.json ./
COPY backend/libs/shared/config /libs/shared/config

RUN npm install --package-lock=false

COPY backend/services/payments-service/tsconfig.json ./
COPY backend/services/payments-service/src ./src
RUN npm run build

FROM node:20-alpine
WORKDIR /app
ENV NODE_ENV=production

COPY backend/services/payments-service/package.json ./
COPY backend/libs/shared/config /libs/shared/config
RUN npm install --omit=dev --package-lock=false

COPY --from=builder /app/dist ./dist
CMD ["node", "dist/index.js"]
