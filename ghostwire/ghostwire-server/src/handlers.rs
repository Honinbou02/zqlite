//! HTTP request handlers

use axum::{
    extract::{Path, Query, State, WebSocketUpgrade},
    http::StatusCode,
    response::{Json, Response},
};
use ghostwire_common::{
    protocol::{ApiResponse, PaginationParams},
    AclRule, PeerInfo, RegisterPeerRequest, RegisterPeerResponse,
};
use uuid::Uuid;

use crate::AppState;

/// Register a new peer
pub async fn register_peer(
    State(_state): State<AppState>,
    Json(_request): Json<RegisterPeerRequest>,
) -> Result<Json<ApiResponse<RegisterPeerResponse>>, StatusCode> {
    // TODO: Implement peer registration
    Err(StatusCode::NOT_IMPLEMENTED)
}

/// Get peer by ID
pub async fn get_peer(
    State(_state): State<AppState>,
    Path(_peer_id): Path<Uuid>,
) -> Result<Json<ApiResponse<PeerInfo>>, StatusCode> {
    // TODO: Implement get peer
    Err(StatusCode::NOT_IMPLEMENTED)
}

/// List all peers
pub async fn list_peers(
    State(_state): State<AppState>,
    Query(_params): Query<PaginationParams>,
) -> Result<Json<ApiResponse<Vec<PeerInfo>>>, StatusCode> {
    // TODO: Implement list peers
    Err(StatusCode::NOT_IMPLEMENTED)
}

/// Update peer information
pub async fn update_peer(
    State(_state): State<AppState>,
    Path(_peer_id): Path<Uuid>,
    Json(_peer_info): Json<PeerInfo>,
) -> Result<Json<ApiResponse<PeerInfo>>, StatusCode> {
    // TODO: Implement update peer
    Err(StatusCode::NOT_IMPLEMENTED)
}

/// Unregister a peer
pub async fn unregister_peer(
    State(_state): State<AppState>,
    Path(_peer_id): Path<Uuid>,
) -> Result<StatusCode, StatusCode> {
    // TODO: Implement unregister peer
    Err(StatusCode::NOT_IMPLEMENTED)
}

/// Get network topology
pub async fn get_topology(
    State(_state): State<AppState>,
) -> Result<Json<ApiResponse<ghostwire_common::NetworkTopology>>, StatusCode> {
    // TODO: Implement get topology
    Err(StatusCode::NOT_IMPLEMENTED)
}

/// Get ACL rules
pub async fn get_acl_rules(
    State(_state): State<AppState>,
    Query(_params): Query<PaginationParams>,
) -> Result<Json<ApiResponse<Vec<AclRule>>>, StatusCode> {
    // TODO: Implement get ACL rules
    Err(StatusCode::NOT_IMPLEMENTED)
}

/// Add ACL rule
pub async fn add_acl_rule(
    State(_state): State<AppState>,
    Json(_rule): Json<AclRule>,
) -> Result<Json<ApiResponse<AclRule>>, StatusCode> {
    // TODO: Implement add ACL rule
    Err(StatusCode::NOT_IMPLEMENTED)
}

/// Update ACL rule
pub async fn update_acl_rule(
    State(_state): State<AppState>,
    Path(_rule_id): Path<Uuid>,
    Json(_rule): Json<AclRule>,
) -> Result<Json<ApiResponse<AclRule>>, StatusCode> {
    // TODO: Implement update ACL rule
    Err(StatusCode::NOT_IMPLEMENTED)
}

/// Delete ACL rule
pub async fn delete_acl_rule(
    State(_state): State<AppState>,
    Path(_rule_id): Path<Uuid>,
) -> Result<StatusCode, StatusCode> {
    // TODO: Implement delete ACL rule
    Err(StatusCode::NOT_IMPLEMENTED)
}

/// WebSocket handler for real-time updates
pub async fn websocket_handler(
    _ws: WebSocketUpgrade,
    State(_state): State<AppState>,
) -> Response {
    // TODO: Implement WebSocket handler
    StatusCode::NOT_IMPLEMENTED.into_response()
}