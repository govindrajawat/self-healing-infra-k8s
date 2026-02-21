FROM node:18-alpine

WORKDIR /app

# Install curl so simulate-failure.sh can trigger endpoints via kubectl exec
RUN apk add --no-cache curl

# Copy package files and install production deps only
COPY package*.json ./
RUN npm ci --only=production

# Copy application code
COPY app.js .

# Use a non-root user for security
RUN addgroup -g 1001 -S nodejs && adduser -S nodejs -u 1001
USER nodejs

EXPOSE 3000

CMD ["node", "app.js"]