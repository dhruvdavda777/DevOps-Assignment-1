# Deliberately pinned to an OLDER base image so the container scan has real
# CVEs to report. A hardened version is in Dockerfile.hardened.
FROM node:20.11-alpine3.18

WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev
COPY src ./src

ENV PORT=3000
EXPOSE 3000
CMD ["node", "src/server.js"]
