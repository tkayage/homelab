# Non-T3 fixture: a containerizable repo that already ships its OWN image config.
# SCAF-06 contract — the scaffolder MUST validate and reuse this Dockerfile, never
# overwrite it. It carries the two signals detect reads: an EXPOSE line (resolved
# container port -> 8080) and a non-root USER (so no "missing non-root USER" warning).
FROM node:22.17.0-alpine

WORKDIR /app
COPY server.js ./

# Run as a non-root user (uid 1001), never overwritten by the scaffolder.
RUN addgroup -g 1001 -S app && adduser -u 1001 -S app -G app
USER app

EXPOSE 8080
CMD ["node", "server.js"]
