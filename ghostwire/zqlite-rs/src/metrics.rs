//! Metrics collection and observability for ZQLite

use metrics::{counter, gauge, histogram, Unit};
use std::time::{Duration, Instant};
use tracing::{debug, error, info, warn};

/// Metrics collector for ZQLite operations
#[derive(Debug, Clone)]
pub struct ZQLiteMetrics {
    prefix: String,
}

impl Default for ZQLiteMetrics {
    fn default() -> Self {
        Self::new("zqlite")
    }
}

impl ZQLiteMetrics {
    /// Create a new metrics collector with the given prefix
    pub fn new(prefix: &str) -> Self {
        Self {
            prefix: prefix.to_string(),
        }
    }

    /// Record a database connection opened
    pub fn connection_opened(&self, database_path: Option<&str>) {
        counter!(format!("{}_connections_opened_total", self.prefix)).increment(1);

        if let Some(path) = database_path {
            counter!(
                format!("{}_connections_opened_total", self.prefix),
                "database" => path.to_string()
            ).increment(1);
        }

        debug!("Database connection opened");
    }

    /// Record a database connection closed
    pub fn connection_closed(&self, database_path: Option<&str>) {
        counter!(format!("{}_connections_closed_total", self.prefix)).increment(1);

        if let Some(path) = database_path {
            counter!(
                format!("{}_connections_closed_total", self.prefix),
                "database" => path.to_string()
            ).increment(1);
        }

        debug!("Database connection closed");
    }

    /// Record query execution
    pub fn query_executed(&self, sql: &str, duration: Duration, success: bool) {
        let operation_type = self.classify_sql_operation(sql);

        counter!(format!("{}_queries_total", self.prefix)).increment(1);
        counter!(
            format!("{}_queries_total", self.prefix),
            "operation" => operation_type.clone(),
            "success" => success.to_string()
        ).increment(1);

        histogram!(
            format!("{}_query_duration_seconds", self.prefix),
            Unit::Seconds
        ).record(duration.as_secs_f64());

        histogram!(
            format!("{}_query_duration_seconds", self.prefix),
            Unit::Seconds,
            "operation" => operation_type
        ).record(duration.as_secs_f64());

        if success {
            debug!("Query executed successfully in {:?}", duration);
        } else {
            warn!("Query execution failed after {:?}", duration);
        }
    }

    /// Record prepared statement operations
    pub fn prepared_statement_created(&self) {
        counter!(format!("{}_prepared_statements_created_total", self.prefix)).increment(1);
        debug!("Prepared statement created");
    }

    /// Record prepared statement execution
    pub fn prepared_statement_executed(&self, duration: Duration, success: bool) {
        counter!(format!("{}_prepared_statements_executed_total", self.prefix)).increment(1);
        counter!(
            format!("{}_prepared_statements_executed_total", self.prefix),
            "success" => success.to_string()
        ).increment(1);

        histogram!(
            format!("{}_prepared_statement_duration_seconds", self.prefix),
            Unit::Seconds
        ).record(duration.as_secs_f64());

        if success {
            debug!("Prepared statement executed successfully in {:?}", duration);
        } else {
            warn!("Prepared statement execution failed after {:?}", duration);
        }
    }

    /// Record transaction operations
    pub fn transaction_started(&self) {
        counter!(format!("{}_transactions_started_total", self.prefix)).increment(1);
        gauge!(format!("{}_active_transactions", self.prefix)).increment(1.0);
        debug!("Transaction started");
    }

    /// Record transaction completion
    pub fn transaction_completed(&self, outcome: TransactionOutcome, duration: Duration) {
        counter!(format!("{}_transactions_completed_total", self.prefix)).increment(1);
        counter!(
            format!("{}_transactions_completed_total", self.prefix),
            "outcome" => outcome.as_str()
        ).increment(1);

        gauge!(format!("{}_active_transactions", self.prefix)).decrement(1.0);

        histogram!(
            format!("{}_transaction_duration_seconds", self.prefix),
            Unit::Seconds
        ).record(duration.as_secs_f64());

        histogram!(
            format!("{}_transaction_duration_seconds", self.prefix),
            Unit::Seconds,
            "outcome" => outcome.as_str()
        ).record(duration.as_secs_f64());

        match outcome {
            TransactionOutcome::Committed => info!("Transaction committed in {:?}", duration),
            TransactionOutcome::RolledBack => warn!("Transaction rolled back after {:?}", duration),
        }
    }

    /// Record connection pool metrics
    pub fn pool_metrics_updated(
        &self,
        active_connections: u32,
        idle_connections: u32,
        waiting_requests: u32,
    ) {
        gauge!(format!("{}_pool_active_connections", self.prefix))
            .set(active_connections as f64);
        gauge!(format!("{}_pool_idle_connections", self.prefix))
            .set(idle_connections as f64);
        gauge!(format!("{}_pool_waiting_requests", self.prefix))
            .set(waiting_requests as f64);
    }

    /// Record connection pool events
    pub fn pool_connection_acquired(&self, wait_duration: Duration) {
        counter!(format!("{}_pool_connections_acquired_total", self.prefix)).increment(1);
        histogram!(
            format!("{}_pool_connection_wait_duration_seconds", self.prefix),
            Unit::Seconds
        ).record(wait_duration.as_secs_f64());

        debug!("Connection acquired from pool in {:?}", wait_duration);
    }

    /// Record connection pool timeout
    pub fn pool_connection_timeout(&self) {
        counter!(format!("{}_pool_connection_timeouts_total", self.prefix)).increment(1);
        error!("Connection pool timeout");
    }

    /// Record database errors
    pub fn database_error(&self, error_type: &str) {
        counter!(format!("{}_errors_total", self.prefix)).increment(1);
        counter!(
            format!("{}_errors_total", self.prefix),
            "type" => error_type.to_string()
        ).increment(1);

        error!("Database error: {}", error_type);
    }

    /// Record row counts for queries
    pub fn query_rows_returned(&self, row_count: usize) {
        histogram!(format!("{}_query_rows_returned", self.prefix))
            .record(row_count as f64);
        debug!("Query returned {} rows", row_count);
    }

    /// Record database size metrics (if available)
    pub fn database_size_updated(&self, size_bytes: u64) {
        gauge!(format!("{}_database_size_bytes", self.prefix)).set(size_bytes as f64);
    }

    /// Classify SQL operation type for metrics labeling
    fn classify_sql_operation(&self, sql: &str) -> String {
        let sql_upper = sql.trim().to_uppercase();

        if sql_upper.starts_with("SELECT") {
            "select".to_string()
        } else if sql_upper.starts_with("INSERT") {
            "insert".to_string()
        } else if sql_upper.starts_with("UPDATE") {
            "update".to_string()
        } else if sql_upper.starts_with("DELETE") {
            "delete".to_string()
        } else if sql_upper.starts_with("CREATE") {
            "create".to_string()
        } else if sql_upper.starts_with("DROP") {
            "drop".to_string()
        } else if sql_upper.starts_with("ALTER") {
            "alter".to_string()
        } else if sql_upper.starts_with("BEGIN") || sql_upper.starts_with("START") {
            "begin".to_string()
        } else if sql_upper.starts_with("COMMIT") {
            "commit".to_string()
        } else if sql_upper.starts_with("ROLLBACK") {
            "rollback".to_string()
        } else {
            "other".to_string()
        }
    }
}

/// Transaction outcome for metrics
#[derive(Debug, Clone, Copy)]
pub enum TransactionOutcome {
    /// Transaction was committed
    Committed,
    /// Transaction was rolled back
    RolledBack,
}

impl TransactionOutcome {
    /// Get string representation for metrics labels
    pub fn as_str(&self) -> &'static str {
        match self {
            TransactionOutcome::Committed => "committed",
            TransactionOutcome::RolledBack => "rolled_back",
        }
    }
}

/// Timer helper for measuring operation durations
pub struct Timer {
    start: Instant,
    operation: String,
    metrics: ZQLiteMetrics,
}

impl Timer {
    /// Start a new timer
    pub fn new(operation: &str, metrics: ZQLiteMetrics) -> Self {
        Self {
            start: Instant::now(),
            operation: operation.to_string(),
            metrics,
        }
    }

    /// Finish the timer and record the duration
    pub fn finish(self, success: bool) {
        let duration = self.start.elapsed();

        match self.operation.as_str() {
            "query" => {
                // This would need the SQL string, so we use a generic approach
                histogram!(
                    format!("{}_operation_duration_seconds", self.metrics.prefix),
                    Unit::Seconds,
                    "operation" => "query",
                    "success" => success.to_string()
                ).record(duration.as_secs_f64());
            }
            "prepared_statement" => {
                self.metrics.prepared_statement_executed(duration, success);
            }
            _ => {
                histogram!(
                    format!("{}_operation_duration_seconds", self.metrics.prefix),
                    Unit::Seconds,
                    "operation" => self.operation,
                    "success" => success.to_string()
                ).record(duration.as_secs_f64());
            }
        }
    }
}

/// Prometheus metrics exporter configuration
#[derive(Debug, Clone)]
pub struct PrometheusConfig {
    /// Address to bind the metrics server
    pub bind_address: String,
    /// Path for metrics endpoint
    pub metrics_path: String,
}

impl Default for PrometheusConfig {
    fn default() -> Self {
        Self {
            bind_address: "0.0.0.0:9090".to_string(),
            metrics_path: "/metrics".to_string(),
        }
    }
}

/// Initialize Prometheus metrics exporter
pub async fn init_prometheus_exporter(config: PrometheusConfig) -> Result<(), Box<dyn std::error::Error>> {
    use metrics_exporter_prometheus::PrometheusBuilder;
    use std::net::SocketAddr;

    let addr: SocketAddr = config.bind_address.parse()?;

    let builder = PrometheusBuilder::new();
    let handle = builder.install()?;

    // Start the metrics server
    tokio::spawn(async move {
        let app = axum::Router::new()
            .route(&config.metrics_path, axum::routing::get(move || async move {
                handle.render()
            }));

        let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
        axum::serve(listener, app).await.unwrap();
    });

    info!("Prometheus metrics server started on {}{}", addr, config.metrics_path);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sql_operation_classification() {
        let metrics = ZQLiteMetrics::default();

        assert_eq!(metrics.classify_sql_operation("SELECT * FROM users"), "select");
        assert_eq!(metrics.classify_sql_operation("  select id from table  "), "select");
        assert_eq!(metrics.classify_sql_operation("INSERT INTO users VALUES (1)"), "insert");
        assert_eq!(metrics.classify_sql_operation("UPDATE users SET name = 'test'"), "update");
        assert_eq!(metrics.classify_sql_operation("DELETE FROM users"), "delete");
        assert_eq!(metrics.classify_sql_operation("CREATE TABLE test (id INTEGER)"), "create");
        assert_eq!(metrics.classify_sql_operation("DROP TABLE test"), "drop");
        assert_eq!(metrics.classify_sql_operation("ALTER TABLE test ADD COLUMN name TEXT"), "alter");
        assert_eq!(metrics.classify_sql_operation("BEGIN TRANSACTION"), "begin");
        assert_eq!(metrics.classify_sql_operation("COMMIT"), "commit");
        assert_eq!(metrics.classify_sql_operation("ROLLBACK"), "rollback");
        assert_eq!(metrics.classify_sql_operation("PRAGMA table_info(users)"), "other");
    }

    #[test]
    fn test_timer() {
        let metrics = ZQLiteMetrics::default();
        let timer = Timer::new("test_operation", metrics);

        std::thread::sleep(Duration::from_millis(10));
        timer.finish(true);
    }

    #[tokio::test]
    async fn test_prometheus_config() {
        let config = PrometheusConfig::default();
        assert_eq!(config.bind_address, "0.0.0.0:9090");
        assert_eq!(config.metrics_path, "/metrics");
    }
}