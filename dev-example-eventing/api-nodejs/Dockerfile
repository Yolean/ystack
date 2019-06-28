FROM node:10.16.0-alpine@sha256:07897ec27318d8e43cfc6b1762e7a28ed01479ba4927aca0cdff53c1de9ea6fd

WORKDIR /usr/src/app

COPY package*.json ./

RUN npm ci

COPY src .

EXPOSE 8080
CMD [ "node", "./" ]
