# Multi-stage. The test stage must pass or no image is produced.
# Dhruv Davda - 24BCS10203
FROM node:22-alpine AS test
WORKDIR /app
COPY application/package.json ./
COPY application/src ./src
COPY application/test ./test
RUN node --test

FROM node:22-alpine AS runtime
WORKDIR /app
COPY application/package.json ./
COPY application/src ./src

# Run unprivileged, and give the non-root user ownership of the data mount.
RUN mkdir -p /data && chown -R node:node /data /app
USER node

ENV PORT=3000 DATA_DIR=/data APP_ENV=production
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
  CMD node -e "require('http').get('http://127.0.0.1:3000/healthz',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"

CMD ["node", "src/server.js"]
