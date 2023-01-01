FROM node:18.12.1-alpine@sha256:a136ed7b0df71082cdb171f36d640ea3b392a5c70401c642326acee767b8c540

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
