FROM node:22-alpine

WORKDIR /app
COPY server.js .

# node:alpine ships an unprivileged "node" user - use it instead of root.
USER node

ENV PORT=3000
EXPOSE 3000
CMD ["node", "server.js"]
