# Single-stage equivalent of the class multi-stage Dockerfile, built only so I
# can measure what the second stage actually saves.
FROM node:24-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3000
CMD ["npm", "start"]
