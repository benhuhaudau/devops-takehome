# Multi-stage build: tiny, non-root, static binary.
# Builder toolchain version matters: an old go distro embeds old stdlib CVEs.
FROM golang:1.26-alpine AS build
WORKDIR /src
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /out/quote-api .

FROM gcr.io/distroless/static:nonroot
WORKDIR /app
COPY --from=build /out/quote-api /app/quote-api
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/app/quote-api"]
