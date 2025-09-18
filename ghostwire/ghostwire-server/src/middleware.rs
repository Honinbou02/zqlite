//! HTTP middleware

use axum::http::{header, Method};
use std::time::Duration;
use tower::ServiceBuilder;
use tower_http::{
    cors::{Any, CorsLayer},
    timeout::TimeoutLayer,
    trace::TraceLayer,
};

/// Create logging middleware
pub fn logging_middleware() -> TraceLayer {
    TraceLayer::new_for_http()
}

/// Create CORS middleware
pub fn cors_middleware() -> CorsLayer {
    CorsLayer::new()
        .allow_origin(Any)
        .allow_methods([Method::GET, Method::POST, Method::PUT, Method::DELETE])
        .allow_headers([header::CONTENT_TYPE, header::AUTHORIZATION])
}

/// Create timeout middleware
pub fn timeout_middleware() -> TimeoutLayer {
    TimeoutLayer::new(Duration::from_secs(30))
}