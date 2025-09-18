# ZQLite FFI Testing Environment
# Lightweight Debian-based container with Zig 0.16 and Rust for testing ZQLite FFI bindings

FROM debian:bookworm-slim

# Set environment variables
ENV ZIG_VERSION=0.16.0-dev.252+ae00a2a84
ENV RUST_VERSION=nightly
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    build-essential \
    pkg-config \
    libssl-dev \
    libclang-dev \
    llvm-dev \
    xz-utils \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Zig
RUN cd /opt && \
    wget -q "https://ziglang.org/builds/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" && \
    tar -xJf "zig-x86_64-linux-${ZIG_VERSION}.tar.xz" && \
    rm "zig-x86_64-linux-${ZIG_VERSION}.tar.xz" && \
    ln -s "/opt/zig-x86_64-linux-${ZIG_VERSION}/zig" /usr/local/bin/zig

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain ${RUST_VERSION}
ENV PATH="/root/.cargo/bin:${PATH}"

# Install common Rust tools for development (nightly-specific tools)
RUN cargo install cargo-watch cargo-edit cargo-expand cargo-udeps

# Verify installations
RUN zig version && \
    rustc --version && \
    cargo --version

# Create working directory
WORKDIR /workspace

# Create a non-root user for safer development
RUN useradd -m -s /bin/bash developer && \
    chown -R developer:developer /workspace

# Switch to non-root user
USER developer

# Set up user environment
ENV PATH="/home/developer/.cargo/bin:${PATH}"
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain ${RUST_VERSION}

# Install rust-src for better IDE support and enable nightly features
RUN /home/developer/.cargo/bin/rustup component add rust-src rust-analyzer clippy rustfmt

# Copy the installation script
COPY --chown=developer:developer GhostwireInstall.sh /workspace/

# Make the script executable
RUN chmod +x /workspace/GhostwireInstall.sh

# Create a startup script for easy testing
RUN echo '#!/bin/bash\n\
echo "🚀 ZQLite FFI Testing Environment"\n\
echo "Zig version: $(zig version)"\n\
echo "Rust version: $(rustc --version)"\n\
echo "Cargo version: $(cargo --version)"\n\
echo ""\n\
echo "📁 Available commands:"\n\
echo "  ./GhostwireInstall.sh          - Run full installation"\n\
echo "  ./GhostwireInstall.sh test     - Test existing installation"\n\
echo "  ./GhostwireInstall.sh clean    - Clean installation"\n\
echo ""\n\
echo "🔧 Quick start:"\n\
echo "  1. Run: ./GhostwireInstall.sh"\n\
echo "  2. Test: cd ghostwire && cargo run --example basic_usage"\n\
echo ""\n\
if [ -d "ghostwire" ]; then\n\
    echo "✅ Ghostwire installation found"\n\
    echo "💻 To test: cd ghostwire && cargo run --example basic_usage"\n\
else\n\
    echo "❌ No Ghostwire installation found"\n\
    echo "🚀 Run: ./GhostwireInstall.sh to get started"\n\
fi\n\
echo ""\n\
' > /workspace/welcome.sh && chmod +x /workspace/welcome.sh

# Set default command
CMD ["/bin/bash", "-c", "./welcome.sh && /bin/bash"]

# Health check to ensure Zig and Rust are properly installed
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD zig version && rustc --version || exit 1

# Labels for documentation
LABEL maintainer="Ghostwire Team <team@ghostwire.dev>"
LABEL description="ZQLite FFI Testing Environment with Zig 0.16 and Rust"
LABEL version="1.0"
LABEL zig.version="${ZIG_VERSION}"
LABEL rust.version="${RUST_VERSION}"