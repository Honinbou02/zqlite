//! Protocol definitions for Ghostwire

use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// API version
pub const API_VERSION: &str = "v1";

/// Base path for REST API
pub const API_BASE_PATH: &str = "/api/v1";

/// WebSocket protocol messages
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", content = "data")]
pub enum WebSocketMessage {
    /// Peer registration
    PeerRegister(crate::RegisterPeerRequest),
    /// Peer registration response
    PeerRegisterResponse(Result<crate::RegisterPeerResponse, String>),
    /// Health check
    HealthCheck(crate::HealthCheck),
    /// Topology update
    TopologyUpdate(crate::NetworkTopology),
    /// Peer disconnected
    PeerDisconnected { peer_id: Uuid },
    /// Error message
    Error { message: String },
    /// Ping message for keep-alive
    Ping,
    /// Pong response to ping
    Pong,
}

/// REST API endpoints
pub mod endpoints {
    use super::API_BASE_PATH;

    /// Peer registration endpoint
    pub const REGISTER_PEER: &str = const_format::concatcp!(API_BASE_PATH, "/peers/register");

    /// Get peer information
    pub const GET_PEER: &str = const_format::concatcp!(API_BASE_PATH, "/peers/{id}");

    /// List all peers
    pub const LIST_PEERS: &str = const_format::concatcp!(API_BASE_PATH, "/peers");

    /// Update peer information
    pub const UPDATE_PEER: &str = const_format::concatcp!(API_BASE_PATH, "/peers/{id}");

    /// Unregister peer
    pub const UNREGISTER_PEER: &str = const_format::concatcp!(API_BASE_PATH, "/peers/{id}");

    /// Get network topology
    pub const GET_TOPOLOGY: &str = const_format::concatcp!(API_BASE_PATH, "/topology");

    /// Get ACL rules
    pub const GET_ACL_RULES: &str = const_format::concatcp!(API_BASE_PATH, "/acl/rules");

    /// Add ACL rule
    pub const ADD_ACL_RULE: &str = const_format::concatcp!(API_BASE_PATH, "/acl/rules");

    /// Update ACL rule
    pub const UPDATE_ACL_RULE: &str = const_format::concatcp!(API_BASE_PATH, "/acl/rules/{id}");

    /// Delete ACL rule
    pub const DELETE_ACL_RULE: &str = const_format::concatcp!(API_BASE_PATH, "/acl/rules/{id}");

    /// Health check endpoint
    pub const HEALTH: &str = const_format::concatcp!(API_BASE_PATH, "/health");

    /// Metrics endpoint (Prometheus format)
    pub const METRICS: &str = "/metrics";

    /// WebSocket endpoint for real-time updates
    pub const WEBSOCKET: &str = const_format::concatcp!(API_BASE_PATH, "/ws");
}

/// HTTP response wrapper
#[derive(Debug, Serialize, Deserialize)]
pub struct ApiResponse<T> {
    /// Success status
    pub success: bool,
    /// Response data
    pub data: Option<T>,
    /// Error message if any
    pub error: Option<String>,
    /// Request timestamp
    pub timestamp: chrono::DateTime<chrono::Utc>,
}

impl<T> ApiResponse<T> {
    /// Create a successful response
    pub fn success(data: T) -> Self {
        Self {
            success: true,
            data: Some(data),
            error: None,
            timestamp: chrono::Utc::now(),
        }
    }

    /// Create an error response
    pub fn error(message: String) -> Self {
        Self {
            success: false,
            data: None,
            error: Some(message),
            timestamp: chrono::Utc::now(),
        }
    }
}

/// Paginated response wrapper
#[derive(Debug, Serialize, Deserialize)]
pub struct PaginatedResponse<T> {
    /// Items in this page
    pub items: Vec<T>,
    /// Current page number (0-based)
    pub page: u32,
    /// Page size
    pub page_size: u32,
    /// Total number of items
    pub total_count: u64,
    /// Total number of pages
    pub total_pages: u32,
    /// Whether there's a next page
    pub has_next: bool,
    /// Whether there's a previous page
    pub has_previous: bool,
}

impl<T> PaginatedResponse<T> {
    /// Create a new paginated response
    pub fn new(items: Vec<T>, page: u32, page_size: u32, total_count: u64) -> Self {
        let total_pages = ((total_count as f64) / (page_size as f64)).ceil() as u32;
        let has_next = page + 1 < total_pages;
        let has_previous = page > 0;

        Self {
            items,
            page,
            page_size,
            total_count,
            total_pages,
            has_next,
            has_previous,
        }
    }
}

/// Query parameters for pagination
#[derive(Debug, Serialize, Deserialize)]
pub struct PaginationParams {
    /// Page number (0-based)
    pub page: Option<u32>,
    /// Page size (default: 50, max: 1000)
    pub page_size: Option<u32>,
    /// Sort field
    pub sort_by: Option<String>,
    /// Sort order (asc/desc)
    pub sort_order: Option<SortOrder>,
}

/// Sort order enumeration
#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SortOrder {
    Asc,
    Desc,
}

impl Default for PaginationParams {
    fn default() -> Self {
        Self {
            page: Some(0),
            page_size: Some(50),
            sort_by: None,
            sort_order: Some(SortOrder::Asc),
        }
    }
}

impl PaginationParams {
    /// Get page number with default
    pub fn page(&self) -> u32 {
        self.page.unwrap_or(0)
    }

    /// Get page size with default and bounds checking
    pub fn page_size(&self) -> u32 {
        self.page_size.unwrap_or(50).min(1000).max(1)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_api_response() {
        let success_response = ApiResponse::success("test data");
        assert!(success_response.success);
        assert_eq!(success_response.data, Some("test data"));
        assert!(success_response.error.is_none());

        let error_response: ApiResponse<String> = ApiResponse::error("test error".to_string());
        assert!(!error_response.success);
        assert!(error_response.data.is_none());
        assert_eq!(error_response.error, Some("test error".to_string()));
    }

    #[test]
    fn test_paginated_response() {
        let items = vec![1, 2, 3, 4, 5];
        let response = PaginatedResponse::new(items, 0, 10, 25);

        assert_eq!(response.page, 0);
        assert_eq!(response.page_size, 10);
        assert_eq!(response.total_count, 25);
        assert_eq!(response.total_pages, 3);
        assert!(response.has_next);
        assert!(!response.has_previous);
    }

    #[test]
    fn test_pagination_params() {
        let params = PaginationParams::default();
        assert_eq!(params.page(), 0);
        assert_eq!(params.page_size(), 50);

        let custom_params = PaginationParams {
            page: Some(2),
            page_size: Some(1500), // Should be clamped to 1000
            sort_by: None,
            sort_order: None,
        };
        assert_eq!(custom_params.page(), 2);
        assert_eq!(custom_params.page_size(), 1000);
    }

    #[test]
    fn test_websocket_message_serialization() {
        let msg = WebSocketMessage::Ping;
        let json = serde_json::to_string(&msg).unwrap();
        let deserialized: WebSocketMessage = serde_json::from_str(&json).unwrap();

        match deserialized {
            WebSocketMessage::Ping => (),
            _ => panic!("Expected Ping message"),
        }
    }
}