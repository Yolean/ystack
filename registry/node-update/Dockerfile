FROM --platform=${BUILDPLATFORM:-linux/amd64} golang:1.22.5-bookworm@sha256:6c2780255bb7b881e904e303be0d7a079054160b2ce1efde446693c0850a39ad

WORKDIR /src

COPY go.* ./
RUN go mod download

COPY . .

RUN go test ./...

RUN sed -i 's/zap.NewDevelopment()/zap.NewProduction()/' main.go

ARG TARGETOS TARGETARCH
RUN GOOS=$TARGETOS GOARCH=$TARGETARCH \
  CGO_ENABLED=0 \
  go build -ldflags '-w -extldflags "-static"'

FROM --platform=${TARGETPLATFORM:-linux/amd64} gcr.io/distroless/static-debian12:nonroot@sha256:8dd8d3ca2cf283383304fd45a5c9c74d5f2cd9da8d3b077d720e264880077c65

COPY --from=0 /src/node-update /usr/local/bin/node-update

ENTRYPOINT ["node-update"]
