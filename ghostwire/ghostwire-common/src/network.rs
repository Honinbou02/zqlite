//! Network utilities for Ghostwire

use crate::{GhostwireError, Result};
use std::net::{IpAddr, Ipv4Addr};

/// IP address allocator for a CIDR block
pub struct IpAllocator {
    network: ipnetwork::Ipv4Network,
    allocated: std::collections::HashSet<Ipv4Addr>,
}

impl IpAllocator {
    /// Create a new IP allocator for the given CIDR block
    pub fn new(cidr: &str) -> Result<Self> {
        let network = cidr
            .parse::<ipnetwork::Ipv4Network>()
            .map_err(|_| GhostwireError::InvalidCidr(cidr.to_string()))?;

        Ok(Self {
            network,
            allocated: std::collections::HashSet::new(),
        })
    }

    /// Allocate the next available IP address
    pub fn allocate(&mut self) -> Result<Ipv4Addr> {
        for ip in self.network.iter() {
            // Skip network and broadcast addresses
            if ip == self.network.network() || ip == self.network.broadcast() {
                continue;
            }

            if !self.allocated.contains(&ip) {
                self.allocated.insert(ip);
                return Ok(ip);
            }
        }

        Err(GhostwireError::Network("No available IP addresses".to_string()))
    }

    /// Release an IP address back to the pool
    pub fn release(&mut self, ip: Ipv4Addr) -> bool {
        self.allocated.remove(&ip)
    }

    /// Check if an IP address is allocated
    pub fn is_allocated(&self, ip: Ipv4Addr) -> bool {
        self.allocated.contains(&ip)
    }

    /// Get the network CIDR
    pub fn network_cidr(&self) -> String {
        self.network.to_string()
    }

    /// Get count of allocated addresses
    pub fn allocated_count(&self) -> usize {
        self.allocated.len()
    }

    /// Get count of available addresses
    pub fn available_count(&self) -> usize {
        // Subtract 2 for network and broadcast addresses
        self.network.size() as usize - 2 - self.allocated.len()
    }
}

/// Check if two CIDR blocks overlap
pub fn cidrs_overlap(cidr1: &str, cidr2: &str) -> Result<bool> {
    let net1 = cidr1
        .parse::<ipnetwork::IpNetwork>()
        .map_err(|_| GhostwireError::InvalidCidr(cidr1.to_string()))?;

    let net2 = cidr2
        .parse::<ipnetwork::IpNetwork>()
        .map_err(|_| GhostwireError::InvalidCidr(cidr2.to_string()))?;

    Ok(net1.overlaps(net2))
}

/// Check if an IP address is within a CIDR block
pub fn ip_in_cidr(ip: IpAddr, cidr: &str) -> Result<bool> {
    let network = cidr
        .parse::<ipnetwork::IpNetwork>()
        .map_err(|_| GhostwireError::InvalidCidr(cidr.to_string()))?;

    Ok(network.contains(ip))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ip_allocator() {
        let mut allocator = IpAllocator::new("192.168.1.0/30").unwrap();

        // Should have 2 available IPs (4 total - network - broadcast)
        assert_eq!(allocator.available_count(), 2);

        let ip1 = allocator.allocate().unwrap();
        let ip2 = allocator.allocate().unwrap();

        assert_ne!(ip1, ip2);
        assert_eq!(allocator.available_count(), 0);

        // Should fail to allocate when full
        assert!(allocator.allocate().is_err());

        // Release and re-allocate
        assert!(allocator.release(ip1));
        assert_eq!(allocator.available_count(), 1);

        let ip3 = allocator.allocate().unwrap();
        assert_eq!(ip1, ip3);
    }

    #[test]
    fn test_cidr_overlap() {
        assert!(cidrs_overlap("192.168.1.0/24", "192.168.1.128/25").unwrap());
        assert!(!cidrs_overlap("192.168.1.0/24", "192.168.2.0/24").unwrap());
        assert!(cidrs_overlap("10.0.0.0/8", "10.1.1.0/24").unwrap());
    }

    #[test]
    fn test_ip_in_cidr() {
        assert!(ip_in_cidr("192.168.1.100".parse().unwrap(), "192.168.1.0/24").unwrap());
        assert!(!ip_in_cidr("192.168.2.100".parse().unwrap(), "192.168.1.0/24").unwrap());
    }
}