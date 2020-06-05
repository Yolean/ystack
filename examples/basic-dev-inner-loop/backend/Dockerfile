FROM node:12.16.3-alpine@sha256:84f5c9090cc741421b2376b2393e7d5fa2f89d36167c12eb57aef16dd64ecf6c

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
