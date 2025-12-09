# syntax=docker/dockerfile:1.7
FROM node:20-alpine AS base
WORKDIR /workspace

COPY package.json package-lock.json* ./
RUN npm ci --omit=dev

FROM node:20-alpine AS build
WORKDIR /workspace
COPY package.json package-lock.json* ./
RUN npm ci
COPY tsconfig.json jest.config.js src tests ./
RUN npm run build && npm test

FROM node:20-alpine AS runtime
WORKDIR /workspace
ENV NODE_ENV=production
COPY --from=base /workspace/node_modules ./node_modules
COPY --from=build /workspace/dist ./dist
COPY package.json ./

EXPOSE 8080
CMD ["node", "dist/index.js"]
