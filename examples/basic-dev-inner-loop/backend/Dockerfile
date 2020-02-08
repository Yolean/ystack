FROM node:10.16.3-alpine@sha256:77c898d0da5e7bfb6e05c9a64de136ba4e03889a72f3c298e95df822a38f450d

ARG build_tag
ARG build_timestamp
ARG git_commit
ENV BUILD_TAG=$build_tag
ENV BUILD_TIMESTAMP=$build_timestamp
ENV GIT_COMMIT=$git_commit

WORKDIR /app
EXPOSE 3000
CMD ["npm", "run", "dev"]

COPY package* ./
RUN npm install
COPY . .
