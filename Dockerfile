FROM python:3.12-slim

# Copy uv tools from upstream
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Install system dependencies, Node.js, Podman, and build tools directly via apt
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    wget \
    git \
    make \
    cmake \
    fd-find \
    ripgrep \
    jq \
    tree \
    tar \
    unzip \
    procps \
    lsof \
    nodejs \
    npm \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Rust toolchain globally and non-interactively
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path && . "/usr/local/cargo/env"

# Install OpenHands
RUN uv tool install openhands --python 3.12
ENV PATH="/root/.local/bin:${PATH}"

COPY openhands-entrypoint.sh /usr/local/bin/openhands-entrypoint

ENTRYPOINT ["openhands-entrypoint"]
