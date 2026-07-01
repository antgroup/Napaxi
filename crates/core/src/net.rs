//! Shared SSRF guards for outbound HTTP from LLM-reachable tools.
//!
//! Any code path that lets the model (directly or via prompt injection) choose
//! an outbound URL must run it through these guards before building a client:
//! the `http` builtin, `web_fetch`, and MCP HTTP/SSE transports all do. The
//! guards reject private / link-local / metadata targets, pin DNS so a hostname
//! cannot resolve to a blocked address after the check ("DNS rebinding"), and
//! callers must additionally disable redirect-following so a 30x cannot bounce a
//! vetted request to an internal address.
//!
//! Loopback policy differs by caller, expressed via [`UrlPolicy`]:
//! - [`UrlPolicy::strict`] blocks loopback too (general web fetch — no local use
//!   case).
//! - [`UrlPolicy::allow_loopback`] permits `localhost` / `127.0.0.1` / `::1`
//!   (local HTTP MCP servers), mirroring the OAuth module's localhost allowance,
//!   while still blocking link-local metadata and private ranges.
//!
//! Usage:
//! ```ignore
//! let url = UrlPolicy::strict().validate_url(raw)?;
//! let addrs = UrlPolicy::strict().validate_dns_target(&url).await?;
//! let client = reqwest::Client::builder()
//!     .redirect(reqwest::redirect::Policy::none())
//!     .resolve_to_addrs(url.host_str().unwrap(), &addrs)
//!     .build()?;
//! ```

use std::net::{IpAddr, SocketAddr, ToSocketAddrs};

/// Outbound-URL safety policy. The only knob is whether loopback is permitted;
/// every other dangerous range is blocked unconditionally.
#[derive(Clone, Copy, Debug)]
pub(crate) struct UrlPolicy {
    allow_loopback: bool,
}

impl UrlPolicy {
    /// Blocks loopback in addition to all other dangerous ranges. For general
    /// web fetch tools with no legitimate local target.
    pub(crate) fn strict() -> Self {
        Self {
            allow_loopback: false,
        }
    }

    /// Permits loopback (`localhost` / `127.0.0.1` / `::1`) for callers that
    /// legitimately reach local services (e.g. a local HTTP MCP server), while
    /// still blocking link-local metadata and private ranges.
    pub(crate) fn allow_loopback() -> Self {
        Self {
            allow_loopback: true,
        }
    }

    /// Parses `url` and rejects schemes/hosts that must never be reachable from
    /// an LLM-chosen request. Returns the parsed URL for reuse by the caller.
    pub(crate) fn validate_url(self, url: &str) -> Result<reqwest::Url, String> {
        let parsed = reqwest::Url::parse(url).map_err(|error| format!("invalid URL: {error}"))?;
        match parsed.scheme() {
            "http" | "https" => {}
            scheme => return Err(format!("unsupported URL scheme: {scheme}")),
        }
        let host = parsed
            .host_str()
            .ok_or_else(|| "URL missing host".to_string())?;
        let lowered = host.trim_end_matches('.').to_ascii_lowercase();
        // `host_str()` keeps the brackets on an IPv6 literal (`[::1]`), which
        // would make a naive `parse::<IpAddr>()` miss it — strip them first.
        let ip_candidate = lowered
            .strip_prefix('[')
            .and_then(|rest| rest.strip_suffix(']'))
            .unwrap_or(&lowered);
        if let Ok(ip) = ip_candidate.parse::<IpAddr>() {
            self.reject_ip(ip)?;
            return Ok(parsed);
        }
        let is_localhost_name = lowered == "localhost" || lowered.ends_with(".localhost");
        if is_localhost_name && self.allow_loopback {
            return Ok(parsed);
        }
        if is_localhost_name
            || lowered.ends_with(".local")
            || lowered.ends_with(".internal")
            || lowered == "metadata.google.internal"
        {
            return Err("URL host is not allowed".to_string());
        }
        Ok(parsed)
    }

    /// Resolves `url`'s host and rejects it if any resolved address is blocked.
    /// The returned addresses must be pinned into the client
    /// (`resolve_to_addrs`) so the connection cannot target a different address
    /// than the one vetted here.
    pub(crate) async fn validate_dns_target(
        self,
        url: &reqwest::Url,
    ) -> Result<Vec<SocketAddr>, String> {
        let host = url
            .host_str()
            .ok_or_else(|| "URL missing host".to_string())?
            .to_string();
        let port = url
            .port_or_known_default()
            .ok_or_else(|| "URL missing port".to_string())?;
        // Strip IPv6 brackets so `[::1]` is recognized as a literal here too
        // (matching `validate_url`).
        let ip_candidate = host
            .strip_prefix('[')
            .and_then(|rest| rest.strip_suffix(']'))
            .unwrap_or(&host);
        if let Ok(ip) = ip_candidate.parse::<IpAddr>() {
            self.reject_ip(ip)?;
            return Ok(vec![SocketAddr::new(ip, port)]);
        }
        let addrs = tokio::task::spawn_blocking(move || {
            (host.as_str(), port)
                .to_socket_addrs()
                .map(|items| items.collect::<Vec<_>>())
        })
        .await
        .map_err(|error| format!("DNS resolution failed: {error}"))?
        .map_err(|error| format!("DNS resolution failed: {error}"))?;
        if addrs.is_empty() {
            return Err("DNS resolution returned no addresses".to_string());
        }
        for addr in &addrs {
            self.reject_ip(addr.ip())?;
        }
        Ok(addrs)
    }

    /// Rejects private, link-local, multicast, broadcast, unspecified, and
    /// reserved ranges (covering cloud metadata endpoints like 169.254.169.254).
    /// Loopback is rejected unless this policy permits it.
    fn reject_ip(self, ip: IpAddr) -> Result<(), String> {
        let blocked = "URL resolved to a blocked IP address".to_string();
        match ip {
            IpAddr::V4(ip) => {
                if (ip.is_loopback() && !self.allow_loopback)
                    || ip.is_private()
                    || ip.is_link_local()
                    || ip.is_multicast()
                    || ip.is_broadcast()
                    || ip.is_unspecified()
                    || ip.octets()[0] == 0
                    || ip.octets()[0] >= 224
                {
                    return Err(blocked);
                }
            }
            IpAddr::V6(ip) => {
                if (ip.is_loopback() && !self.allow_loopback)
                    || ip.is_unspecified()
                    || ip.is_multicast()
                    || matches!(ip.segments()[0], 0xfc00..=0xfdff | 0xfe80..=0xfebf)
                {
                    return Err(blocked);
                }
                if let Some(v4) = ip.to_ipv4_mapped() {
                    self.reject_ip(IpAddr::V4(v4))?;
                }
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strict_blocks_local_and_metadata_targets() {
        let p = UrlPolicy::strict();
        assert!(p.validate_url("https://example.com/data.json").is_ok());
        assert!(p.validate_url("file:///etc/passwd").is_err());
        assert!(p.validate_url("http://127.0.0.1/").is_err());
        assert!(p.validate_url("https://localhost/").is_err());
        assert!(p.validate_url("https://metadata.google.internal/").is_err());
        assert!(
            p.validate_url("http://169.254.169.254/latest/meta-data/")
                .is_err()
        );
        assert!(p.validate_url("http://[::1]/").is_err());
    }

    #[test]
    fn allow_loopback_permits_localhost_only() {
        let p = UrlPolicy::allow_loopback();
        // Loopback is allowed for local MCP servers.
        assert!(p.validate_url("http://127.0.0.1:3000/").is_ok());
        assert!(p.validate_url("http://localhost:3000/sse").is_ok());
        assert!(p.validate_url("http://[::1]:3000/").is_ok());
        // But metadata / private / internal stay blocked even here.
        assert!(
            p.validate_url("http://169.254.169.254/latest/meta-data/")
                .is_err()
        );
        assert!(p.validate_url("http://10.0.0.1/").is_err());
        assert!(p.validate_url("http://192.168.1.1/").is_err());
        assert!(p.validate_url("https://metadata.google.internal/").is_err());
    }

    #[test]
    fn reject_ip_covers_metadata_and_mapped() {
        let p = UrlPolicy::strict();
        assert!(p.reject_ip("169.254.169.254".parse().unwrap()).is_err());
        assert!(p.reject_ip("10.0.0.1".parse().unwrap()).is_err());
        assert!(p.reject_ip("192.168.1.1".parse().unwrap()).is_err());
        assert!(p.reject_ip("::ffff:127.0.0.1".parse().unwrap()).is_err());
        assert!(p.reject_ip("1.1.1.1".parse().unwrap()).is_ok());
        // Mapped loopback is still blocked under allow_loopback's mapped path?
        // allow_loopback permits direct loopback but the mapped form resolves to
        // 127.0.0.1 which is loopback — allowed too, consistent with intent.
        assert!(
            UrlPolicy::allow_loopback()
                .reject_ip("::ffff:127.0.0.1".parse().unwrap())
                .is_ok()
        );
    }
}
