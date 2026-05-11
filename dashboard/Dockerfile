# Stage 1: Build WASM frontend
FROM rust:1.87-bookworm AS wasm-builder
RUN rustup target add wasm32-unknown-unknown
RUN cargo install trunk

WORKDIR /build
COPY Cargo.toml ./
COPY shared/ shared/
COPY frontend/ frontend/
COPY server/ server/

WORKDIR /build/frontend
RUN trunk build --release

# Stage 2: Build server
FROM rust:1.87-bookworm AS server-builder
WORKDIR /build
COPY Cargo.toml ./
COPY shared/ shared/
COPY server/ server/
COPY frontend/ frontend/

WORKDIR /build/server
RUN cargo build --release

# Stage 3: Runtime
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=server-builder /build/target/release/dashboard-server /app/dashboard-server
COPY --from=wasm-builder /build/dist/ /app/static/

EXPOSE 8080
ENV RUST_LOG=info
CMD ["/app/dashboard-server"]
