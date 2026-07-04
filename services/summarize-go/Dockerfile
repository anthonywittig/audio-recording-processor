# Multi-stage build -> tiny static image on distroless.
FROM golang:1.24 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -o /out/summarize-go .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/summarize-go /summarize-go
ENTRYPOINT ["/summarize-go"]
