//! Configuration management

use anyhow::{Context, Result};
use ghostwire_common::ServerConfig;
use std::path::Path;
use tokio::fs;

/// Load configuration from file
pub async fn load_config(config_path: &str) -> Result<ServerConfig> {
    if Path::new(config_path).exists() {
        let config_content = fs::read_to_string(config_path)
            .await
            .with_context(|| format!("Failed to read config file: {}", config_path))?;

        let config: ServerConfig = toml::from_str(&config_content)
            .with_context(|| format!("Failed to parse config file: {}", config_path))?;

        Ok(config)
    } else {
        // Use default configuration
        Ok(ServerConfig::default())
    }
}