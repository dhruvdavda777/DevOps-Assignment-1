# Multi-stage: the test stage never ships.
FROM node:22-alpine AS test
WORKDIR /app
COPY package.json ./
COPY src ./src
COPY test ./test
RUN node --test

FROM node:22-alpine AS runtime
WORKDIR /app
COPY package.json ./
COPY src ./src

# Run unprivileged.
USER node

ENV PORT=3000
ENV APP_VERSION=docker
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD node -e "require('http').get('http://127.0.0.1:3000/healthz',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"

CMD ["node", "src/server.js"]
