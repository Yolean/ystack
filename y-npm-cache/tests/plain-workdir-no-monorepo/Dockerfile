#y-npm# FROM node:16.5.0-buster-slim@sha256:610ade6f0702b7355a045d7df4e53f78fded0060c5e765f2d5267b1a613465e8
#y-npm#
#y-npm# WORKDIR /usr/src/my-app
#y-npm#
#y-npm# COPY package*.json ./
#y-npm# RUN npm install --ignore-scripts
FROM /y-npm/

COPY . ./

ENTRYPOINT ["node", "./index"]
