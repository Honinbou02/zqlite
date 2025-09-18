# 🐳 ZQLite FFI Docker Testing Environment

A lightweight, containerized testing environment for ZQLite FFI bindings with Zig 0.16 and Rust nightly.

## 🚀 Quick Start

### Prerequisites

- Docker & Docker Compose
- Git

### Basic Usage

```bash
# Clone and enter the project
git clone https://github.com/ghostkellz/zqlite.git
cd zqlite

# Build and run the testing environment
docker-compose -f docker/docker-compose.yml up zqlite-ffi-test

# Or run in detached mode
docker-compose -f docker/docker-compose.yml up -d zqlite-ffi-test

# Access the container
docker exec -it zqlite-ffi-testing bash
```

## 🛠 Available Services

### 1. `zqlite-ffi-test` - Interactive Testing
Main development and testing environment with interactive shell.

```bash
docker-compose -f docker/docker-compose.yml up zqlite-ffi-test
```

**Features:**
- Zig 0.16.0-dev.252
- Rust nightly with full toolchain
- Interactive bash shell
- Persistent workspace volume
- Pre-installed development tools

**Inside the container:**
```bash
# Install ZQLite FFI
./GhostwireInstall.sh

# Test the installation
cd ghostwire
cargo run --example basic_usage

# Run tests
cargo test

# Development with hot-reload
cargo watch -x 'run --example basic_usage'
```

### 2. `zqlite-dev` - Development with Hot-Reload
Automatically installs and runs with file watching for development.

```bash
docker-compose -f docker/docker-compose.yml up zqlite-dev
```

**Features:**
- Auto-installation on startup
- Hot-reload with `cargo watch`
- Automatic test running
- Debug logging enabled

### 3. `zqlite-ci` - Continuous Integration
Comprehensive CI testing pipeline.

```bash
docker-compose -f docker/docker-compose.yml up zqlite-ci
```

**Runs:**
- `cargo check` - Fast compilation check
- `cargo test` - Run all tests
- `cargo clippy` - Linting
- `cargo fmt --check` - Code formatting check
- `cargo build --release` - Release build
- Example execution

### 4. `zqlite-bench` - Performance Testing
Optimized environment for benchmarking.

```bash
docker-compose -f docker/docker-compose.yml up zqlite-bench
```

**Features:**
- Release optimizations enabled
- CPU-native compilation
- Benchmark execution
- Performance profiling ready

### 5. `zqlite-docs` - Documentation Builder
Generates and serves documentation.

```bash
docker-compose -f docker/docker-compose.yml up zqlite-docs
```

**Features:**
- Generates Rust documentation
- Serves docs on port 8080
- Offline documentation support

## 🔧 Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ZIG_VERSION` | `0.16.0-dev.252+ae00a2a84` | Zig compiler version |
| `RUST_VERSION` | `nightly` | Rust toolchain version |
| `ZQLITE_DIR` | `/workspace/zqlite-ffi` | ZQLite source directory |
| `GHOSTWIRE_DIR` | `/workspace/ghostwire` | Ghostwire project directory |
| `CARGO_HOME` | `/home/developer/.cargo` | Cargo cache directory |

## 📂 Volume Mounts

- **Source Code**: `../:/workspace/zqlite-source:ro` (read-only)
- **Workspace**: Persistent volume for each service
- **Cargo Cache**: Shared across all containers for faster builds

## 🧪 Testing Workflows

### Development Workflow

```bash
# Start development environment
docker-compose -f docker/docker-compose.yml up -d zqlite-dev

# Watch logs
docker-compose -f docker/docker-compose.yml logs -f zqlite-dev

# Access for manual testing
docker exec -it zqlite-ffi-dev bash
```

### CI/CD Workflow

```bash
# Run full CI pipeline
docker-compose -f docker/docker-compose.yml up zqlite-ci

# Check exit code
echo $?
```

### Performance Testing

```bash
# Run benchmarks
docker-compose -f docker/docker-compose.yml up zqlite-bench

# Custom benchmark
docker-compose -f docker/docker-compose.yml run --rm zqlite-bench bash -c "
  ./GhostwireInstall.sh &&
  cd ghostwire &&
  cargo bench --features=crypto
"
```

## 🚀 Advanced Usage

### Custom Build with Different Zig Version

```bash
# Build with custom Zig version
docker build \
  --build-arg ZIG_VERSION=0.16.0-dev.300+abc123 \
  -f docker/Dockerfile \
  -t zqlite-custom \
  .
```

### Running Specific Tests

```bash
# Run specific test
docker-compose -f docker/docker-compose.yml run --rm zqlite-ffi-test bash -c "
  ./GhostwireInstall.sh &&
  cd ghostwire/zqlite-rs &&
  cargo test test_connection
"
```

### Development with IDE Integration

```bash
# Mount current directory for live editing
docker run -it --rm \
  -v $(pwd):/workspace/zqlite-source \
  -v zqlite_cargo_cache:/home/developer/.cargo \
  -p 8080:8080 \
  zqlite-ffi-testing bash
```

## 🐛 Troubleshooting

### Common Issues

1. **Permission Denied**
   ```bash
   # Fix file permissions
   sudo chown -R $USER:$USER .
   ```

2. **Out of Disk Space**
   ```bash
   # Clean up Docker
   docker system prune -a
   docker volume prune
   ```

3. **Build Failures**
   ```bash
   # Rebuild from scratch
   docker-compose -f docker/docker-compose.yml build --no-cache
   ```

### Debug Mode

```bash
# Run with debug output
docker-compose -f docker/docker-compose.yml run --rm zqlite-ffi-test bash -c "
  export RUST_LOG=debug &&
  export RUST_BACKTRACE=1 &&
  ./GhostwireInstall.sh
"
```

### Check Container Health

```bash
# Check all services
docker-compose -f docker/docker-compose.yml ps

# Check specific service logs
docker-compose -f docker/docker-compose.yml logs zqlite-ffi-test
```

## 📊 Performance Considerations

- **Cargo Cache**: Shared volume significantly speeds up subsequent builds
- **Layer Caching**: Dockerfile optimized for layer reuse
- **Multi-stage**: Consider separating build and runtime stages for production
- **Resource Limits**: Add memory/CPU limits for CI environments

## 🔐 Security Notes

- Containers run as non-root user `developer`
- Source code mounted read-only
- No privileged containers
- Minimal attack surface with Debian slim base

## 🛡 Health Checks

The Dockerfile includes health checks to ensure:
- Zig compiler is functional
- Rust toolchain is operational
- Basic system health

## 🔄 Updating

### Update Zig Version

1. Edit `docker/Dockerfile` - change `ZIG_VERSION`
2. Rebuild: `docker-compose -f docker/docker-compose.yml build`

### Update Rust Version

1. Edit `docker/Dockerfile` - change `RUST_VERSION`
2. Rebuild: `docker-compose -f docker/docker-compose.yml build`

## 💡 Tips & Best Practices

1. **Use specific service names** for targeted testing
2. **Clean up volumes** periodically to save disk space
3. **Pin versions** for reproducible builds
4. **Use multi-stage builds** for production deployments
5. **Mount source read-only** to prevent accidental modifications

## 🤝 Contributing

When adding new services:
1. Add service to `docker-compose.yml`
2. Create specific volume if needed
3. Document usage in this README
4. Test all combinations

## 📋 Example Commands Reference

```bash
# Quick test
docker-compose -f docker/docker-compose.yml run --rm zqlite-ffi-test ./GhostwireInstall.sh

# Development session
docker-compose -f docker/docker-compose.yml up zqlite-dev

# Full CI pipeline
docker-compose -f docker/docker-compose.yml up zqlite-ci

# Performance testing
docker-compose -f docker/docker-compose.yml up zqlite-bench

# Documentation
docker-compose -f docker/docker-compose.yml up zqlite-docs

# Clean everything
docker-compose -f docker/docker-compose.yml down -v
```

---

**🎯 Perfect for:** Development, Testing, CI/CD, Debugging, Performance Analysis, Documentation Generation

**🚀 Ready to use:** Just run `docker-compose up` and start coding!