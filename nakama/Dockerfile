FROM heroiclabs/nakama-pluginbuilder:3.26.0 AS builder
WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download
COPY runtime ./runtime
RUN CGO_ENABLED=1 go build --trimpath --buildmode=plugin -o /out/catdex.so ./runtime

FROM heroiclabs/nakama:3.26.0
COPY --from=builder /out/catdex.so /nakama/data/modules/catdex.so
