# TODO needs more thought

#y-npm# FROM node:16.5.0-buster-slim@sha256:610ade6f0702b7355a045d7df4e53f78fded0060c5e765f2d5267b1a613465e8 \
#y-npm#   as base
#y-npm#
#y-npm# WORKDIR /usr/src/my-app
#y-npm#
#y-npm# COPY package*.json ./
#y-npm# RUN npm install --ignore-scripts --only=prod
FROM /y-npm/

FROM base as test
RUN npm install --ignore-scripts
COPY . ./
RUN npm test

FROM base
COPY . ./
ENTRYPOINT ["node", "./index"]
