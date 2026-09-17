# Stage 1 - build the static bundle with the full Node toolchain.
FROM node:22-alpine AS build
WORKDIR /app

# Copy the manifest first. Docker caches this layer, so "npm install" is only
# re-run when the dependencies actually change, not on every source edit.
COPY package.json ./
RUN npm install

COPY . .
RUN npm run build

# Stage 2 - ship only the compiled bundle. No node, no npm, no source.
FROM nginx:1.27-alpine
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
