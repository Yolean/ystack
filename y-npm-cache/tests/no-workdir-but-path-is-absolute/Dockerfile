#y-npm# FROM node:16.5.0-buster-slim@sha256:610ade6f0702b7355a045d7df4e53f78fded0060c5e765f2d5267b1a613465e8 \
#y-npm#   as y-npm.lib-in-monorepo
#y-npm# COPY --chown=nobody:nogroup lib-in-monorepo/package.json /usr/src/lib-in-monorepo/
#y-npm# RUN cd /usr/src/lib-in-monorepo/ && npm install --ignore-scripts --no-bin-links --no-package-lock --only=prod
FROM /y-npm/
COPY --chown=nobody:nogroup . ./
