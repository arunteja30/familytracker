# Build stage
FROM node:18-alpine as build

WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

COPY . ./
RUN npm run build

# Production stage
FROM node:18-alpine as production

WORKDIR /app

# Install serve globally
RUN npm install -g serve

# Copy built assets from build stage
COPY --from=build /app/build ./build

# Expose port
EXPOSE 3000

# Start the server
CMD ["serve", "-s", "build", "-l", "3000"]
