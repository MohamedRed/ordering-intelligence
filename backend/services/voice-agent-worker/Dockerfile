# syntax=docker/dockerfile:1

FROM node:20-bookworm AS builder
WORKDIR /workspace

# Copy repository contents needed for the build
COPY backend /workspace/backend
COPY infra /workspace/infra

# Build the shared voice-agent-config helper so local file installs have fresh artifacts
WORKDIR /workspace/backend/libs/voice-agent-config
RUN npm install \
  && npm run build

# Install dependencies and build the worker
WORKDIR /workspace/backend/services/voice-agent-worker
RUN npm install \
  && npm run build

FROM node:20-bookworm-slim
WORKDIR /workspace
ENV NODE_ENV=production

# Runtime assets (voice-agent presets)
COPY --from=builder /workspace/infra/voice-agents /workspace/infra/voice-agents

# Local dependency pulled via file:../../libs/voice-agent-config
COPY --from=builder /workspace/backend/libs/voice-agent-config /workspace/backend/libs/voice-agent-config
RUN rm -rf /workspace/backend/libs/voice-agent-config/node_modules

# Install only production deps for the worker itself
COPY backend/services/voice-agent-worker/package.json backend/services/voice-agent-worker/package-lock.json* backend/services/voice-agent-worker/tsconfig.json /workspace/backend/services/voice-agent-worker/
WORKDIR /workspace/backend/services/voice-agent-worker
RUN npm install --omit=dev

# Copy the compiled TypeScript bundle
COPY --from=builder /workspace/backend/services/voice-agent-worker/dist ./dist

ENV VOICE_AGENT_CONFIG_DIR=/workspace/infra/voice-agents
CMD ["node", "dist/index.js"]
