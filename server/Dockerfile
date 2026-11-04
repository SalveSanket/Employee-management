# Backend image: Node.js + Express API

# Small, official Node.js 22 (LTS) base image
FROM node:22-alpine

# All app files live in /app inside the container
WORKDIR /app

# Copy only the package files first, so Docker can cache the install step
COPY package.json package-lock.json ./

# Install exact versions from the lock file, production packages only
RUN npm ci --omit=dev

# Copy the application code (files in .dockerignore are skipped)
COPY . .

# Run as the built-in non-root user for security
USER node

# The API listens on this port
EXPOSE 5050

# ATLAS_URI is passed when the container starts, never stored in the image
CMD ["node", "server.js"]
