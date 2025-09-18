//! Ghostwire Coordination Server
//!
//! High-performance mesh VPN coordination server powered by ZQLite

use anyhow::{Context, Result};
use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::Json,
    routing::{delete, get, post, put},
    Router,
};
use clap::Parser;
use ghostwire_common::{
    protocol::{ApiResponse, PaginationParams},
    GhostwireError, PeerInfo, RegisterPeerRequest, RegisterPeerResponse, ServerConfig,
};
use std::{net::SocketAddr, sync::Arc};
use tokio::net::TcpListener;
use tracing::{error, info, warn};
use uuid::Uuid;

mod config;
mod coordination;
mod database;
mod handlers;
mod metrics;
mod middleware;

use coordination::CoordinationServer;

/// Command line arguments
#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct Args {
    /// Configuration file path
    #[arg(short, long, default_value = "ghostwire.toml")]
    config: String,

    /// Database path (overrides config)
    #[arg(long)]
    database: Option<String>,

    /// Bind address (overrides config)
    #[arg(long)]
    bind: Option<SocketAddr>,

    /// Log level
    #[arg(long, default_value = "info")]
    log_level: String,
}

/// Application state shared across handlers
#[derive(Clone)]
struct AppState {
    coordination_server: Arc<CoordinationServer>,
    metrics: zqlite_rs::ZQLiteMetrics,
}

#[tokio::main]
async fn main() -> Result<()> {
    let args = Args::parse();

    // Initialize tracing
    init_tracing(&args.log_level)?;

    info!("Starting Ghostwire Coordination Server v{}", env!("CARGO_PKG_VERSION"));

    // Load configuration
    let mut config = config::load_config(&args.config).await?;

    // Override config with command line arguments
    if let Some(database) = args.database {
        config.database_path = database;
    }
    if let Some(bind) = args.bind {
        config.bind_address = bind;
    }

    info!("Configuration loaded: {:#?}", config);

    // Initialize metrics
    let metrics = zqlite_rs::ZQLiteMetrics::new("ghostwire_server");

    // Initialize Prometheus metrics if enabled
    if config.metrics_config.enabled {
        if let Some(prometheus_addr) = config.metrics_config.prometheus_address {
            let prometheus_config = zqlite_rs::PrometheusConfig {
                bind_address: prometheus_addr.to_string(),
                metrics_path: config.metrics_config.metrics_path.clone(),
            };

            zqlite_rs::init_prometheus_exporter(prometheus_config)
                .await
                .context("Failed to initialize Prometheus metrics")?;

            info!("Prometheus metrics server started on {}", prometheus_addr);
        }
    }

    // Initialize coordination server with ZQLite backend
    let coordination_server = CoordinationServer::new(&config, metrics.clone())
        .await
        .context("Failed to initialize coordination server")?;

    let app_state = AppState {
        coordination_server: Arc::new(coordination_server),
        metrics,
    };

    // Build the application router
    let app = build_router(app_state);

    // Start the server
    let listener = TcpListener::bind(&config.bind_address)
        .await
        .with_context(|| format!("Failed to bind to {}", config.bind_address))?;

    info!("Ghostwire server listening on {}", config.bind_address);

    axum::serve(listener, app)
        .await
        .context("Server error")?;

    Ok(())
}

/// Initialize tracing/logging
fn init_tracing(log_level: &str) -> Result<()> {
    use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

    let log_level = log_level.parse::<tracing::Level>()
        .context("Invalid log level")?;

    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| {
                    format!("ghostwire_server={},zqlite_rs={}", log_level, log_level).into()
                })
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    Ok(())
}

/// Build the application router with all routes
fn build_router(state: AppState) -> Router {
    Router::new()
        // Health check endpoint
        .route("/health", get(health_check))

        // API v1 routes
        .route("/api/v1/peers/register", post(handlers::register_peer))
        .route("/api/v1/peers", get(handlers::list_peers))
        .route("/api/v1/peers/:id", get(handlers::get_peer))
        .route("/api/v1/peers/:id", put(handlers::update_peer))
        .route("/api/v1/peers/:id", delete(handlers::unregister_peer))

        .route("/api/v1/topology", get(handlers::get_topology))

        .route("/api/v1/acl/rules", get(handlers::get_acl_rules))
        .route("/api/v1/acl/rules", post(handlers::add_acl_rule))
        .route("/api/v1/acl/rules/:id", put(handlers::update_acl_rule))
        .route("/api/v1/acl/rules/:id", delete(handlers::delete_acl_rule))

        // WebSocket endpoint for real-time updates
        .route("/api/v1/ws", get(handlers::websocket_handler))

        // Metrics endpoint
        .route("/metrics", get(metrics_handler))

        // Add middleware
        .layer(middleware::logging_middleware())
        .layer(middleware::cors_middleware())
        .layer(middleware::timeout_middleware())

        // Add shared state
        .with_state(state)
}

/// Health check handler
async fn health_check() -> Json<ApiResponse<serde_json::Value>> {
    let health_data = serde_json::json!({
        "status": "healthy",
        "version": env!("CARGO_PKG_VERSION"),
        "timestamp": chrono::Utc::now(),
    });

    Json(ApiResponse::success(health_data))
}

/// Metrics handler (Prometheus format)
async fn metrics_handler() -> Result<String, StatusCode> {
    // This would integrate with the metrics collection system
    // For now, return a simple response
    Ok("# HELP ghostwire_server_info Server information\n# TYPE ghostwire_server_info gauge\nghostwire_server_info{version=\"0.1.0\"} 1\n".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum_test::TestServer;

    fn create_test_state() -> AppState {
        // This would create a test coordination server
        // For now, we'll skip the actual implementation
        todo!("Create test coordination server")
    }

    #[tokio::test]
    async fn test_health_check() {
        let app = build_router(create_test_state());
        let server = TestServer::new(app).unwrap();

        let response = server.get("/health").await;
        response.assert_status_ok();

        let body: ApiResponse<serde_json::Value> = response.json();
        assert!(body.success);
        assert!(body.data.is_some());
    }
}