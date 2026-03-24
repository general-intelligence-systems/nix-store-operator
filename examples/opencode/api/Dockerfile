FROM oven/bun:alpine

WORKDIR /app
COPY package.json .
RUN bun install
COPY server.ts .

EXPOSE 3000
CMD ["bun", "run", "server.ts"]
