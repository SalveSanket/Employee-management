# Frontend image: React app built with Vite, served by Nginx
# Multi-stage build: stage 1 builds, stage 2 only serves the result

# ---------- Stage 1: build the React app ----------
FROM node:22-alpine AS build

WORKDIR /app

# Install dependencies first (cached when package files do not change)
COPY package.json package-lock.json ./
RUN npm ci

# Copy the source code and build it
COPY . .

# Empty = the app calls the API on its own address (Nginx forwards /record)
ARG VITE_API_URL=""
ENV VITE_API_URL=${VITE_API_URL}
RUN npm run build

# ---------- Stage 2: serve the built files ----------
FROM nginx:alpine

# Our Nginx settings (serve React, forward /record to the backend)
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Only the finished files from stage 1, no Node.js and no source code
COPY --from=build /app/dist /usr/share/nginx/html

EXPOSE 80
