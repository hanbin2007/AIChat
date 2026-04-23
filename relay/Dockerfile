# syntax=docker/dockerfile:1.7
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json ./
RUN --mount=type=cache,target=/root/.npm npm install --no-audit --no-fund

FROM node:22-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build

FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    PORT=8787 \
    RELAY_DATA_DIR=/data

RUN addgroup -S relay && adduser -S relay -G relay && mkdir -p /data && chown relay:relay /data
COPY --from=builder --chown=relay:relay /app/.next/standalone ./
COPY --from=builder --chown=relay:relay /app/.next/static ./.next/static
COPY --from=builder --chown=relay:relay /app/public ./public

USER relay
EXPOSE 8787
VOLUME ["/data"]
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s CMD wget -qO- http://127.0.0.1:8787/api/health || exit 1
CMD ["node", "server.js"]
