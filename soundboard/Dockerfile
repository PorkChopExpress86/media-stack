FROM node:20-alpine

WORKDIR /app

COPY package.json ./
RUN npm install --omit=dev

COPY server.js ./
COPY public/ ./public/

# Sounds and config are stored in mounted volumes
RUN mkdir -p /data/sounds /data/config

EXPOSE 8055

CMD ["node", "server.js"]
