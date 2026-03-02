FROM ghcr.io/yolean/node-distroless:504b8f7d64ee26cae89c3a14363462c5635e9433@sha256:5f059ae2a058e19d813989b9a1ff39059a7bbddd2e9fde80f88dd403f7d0ec65

ARG build_tag
ARG git_commit
ENV BUILD_TAG=$build_tag
ENV GIT_COMMIT=$git_commit

COPY src/ ./
