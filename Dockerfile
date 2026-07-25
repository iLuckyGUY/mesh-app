# Stage 1: Build the React application.
# Pinned to --platform=$BUILDPLATFORM: this stage only runs `npm ci` + a Vite
# build, which produce architecture-independent static JS/CSS/HTML. Forcing
# it to build natively (instead of letting buildx run it once per --platform
# under QEMU emulation) avoids multi-hour hangs on arm64 emulation of npm/
# esbuild/rollup native binaries. Only Stage 2 (nginx) needs to be multi-arch,
# and nginx:alpine already ships official multi-arch images, so no emulation
# is needed there either.
FROM --platform=$BUILDPLATFORM node:20-alpine AS builder

WORKDIR /app

# Copy package files
COPY package.json package-lock.json* ./

# Install dependencies
RUN if [ -f package-lock.json ]; then npm ci; else npm install; fi

# Copy source code
COPY . .

# Build arguments for environment variables
ARG VITE_API_URL=/api
ARG VITE_TELEGRAM_BOT_USERNAME
ARG VITE_APP_NAME=Cabinet
ARG VITE_APP_LOGO=V

# Set environment variables for build
ENV VITE_API_URL=$VITE_API_URL
ENV VITE_TELEGRAM_BOT_USERNAME=$VITE_TELEGRAM_BOT_USERNAME
ENV VITE_APP_NAME=$VITE_APP_NAME
ENV VITE_APP_LOGO=$VITE_APP_LOGO

# Build the application. Type-check намеренно пропущен: tsc --noEmit уже
# гоняется CI на каждый PR (lint.yml), образ собирается из проверенного
# коммита - повторная проверка стоила бы ~10s на каждую сборку.
RUN npm run build:docker

# Stage 2: Serve with Nginx.
# Not pinned to BUILDPLATFORM - this DOES need to be built per target
# platform (linux/amd64, linux/arm64), but since it's just copying static
# files onto an official multi-arch nginx:alpine base, buildx resolves the
# correct native nginx image for each platform with no QEMU emulation.
FROM nginx:alpine

# Copy built assets from builder stage
COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Expose port
EXPOSE 80

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:80/ || exit 1
