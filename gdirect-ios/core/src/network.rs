use crate::{Progress, allowed_url, field, token, valid_endpoint};
use anyhow::{Result, bail, ensure};
use reqwest::blocking::Client;
use serde_json::{Value, json};
use std::{
    collections::BTreeSet,
    net::{IpAddr, SocketAddr, ToSocketAddrs},
    time::{Duration, Instant},
};
use url::Url;

pub(crate) fn client(ip: Option<&str>) -> Result<Client> {
    let mut builder = Client::builder()
        .no_proxy()
        .redirect(reqwest::redirect::Policy::none())
        .connect_timeout(Duration::from_secs(4))
        .timeout(Duration::from_secs(20));
    if let Some(ip) = ip.filter(|s| !s.is_empty()) {
        ensure!(valid_endpoint(ip), "endpoint must be a public IP");
        let ip: IpAddr = ip.parse()?;
        for host in [
            "www.googleapis.com",
            "drive.usercontent.google.com",
            "drive.google.com",
        ] {
            builder = builder.resolve(host, SocketAddr::new(ip, 443));
        }
    }
    builder
        .build()
        .map_err(|_| anyhow::anyhow!("unable to create network client"))
}
fn get(value: &Value, path: &str, query: &[(&str, &str)]) -> Result<Value> {
    let auth = token(value)?.ok_or_else(|| anyhow::anyhow!("Google login required"))?;
    let response = client(value["ip"].as_str())?
        .get(format!("https://www.googleapis.com/drive/v3/{path}"))
        .bearer_auth(auth)
        .query(query)
        .send()
        .map_err(|_| anyhow::anyhow!("Drive network request failed"))?;
    let status = response.status();
    ensure!(status.is_success(), "Drive HTTP {}", status.as_u16());
    response
        .json()
        .map_err(|_| anyhow::anyhow!("invalid Drive response"))
}
pub fn list(value: &Value) -> Result<Value> {
    let folder = field(value, "folder")?;
    ensure!(
        !folder.is_empty()
            && folder.len() <= 256
            && folder
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-'),
        "invalid folder ID"
    );
    // One page per request: Swift can yield and refresh credentials between pages.
    let q = format!("'{folder}' in parents and trashed = false");
    get(
        value,
        "files",
        &[
            ("q", &q),
            (
                "fields",
                "nextPageToken,files(id,name,mimeType,size,modifiedTime,md5Checksum,resourceKey)",
            ),
            ("pageSize", "200"),
            ("orderBy", "folder,name_natural"),
            ("supportsAllDrives", "true"),
            ("includeItemsFromAllDrives", "true"),
            ("pageToken", value["page"].as_str().unwrap_or_default()),
        ],
    )
}
pub fn metadata(value: &Value) -> Result<Value> {
    let file = crate::drive::FileRef::parse(field(value, "input")?)?;
    let mut query = vec![
        ("fields", "id,name,mimeType,size,md5Checksum,resourceKey"),
        ("supportsAllDrives", "true"),
    ];
    if let Some(key) = &file.resource_key {
        query.push(("resourcekey", key));
    }
    get(value, &format!("files/{}", file.id), &query)
}
pub fn scan(value: &Value, progress: Option<Progress>) -> Result<Value> {
    let mut candidates = BTreeSet::new();
    if let Some(ips) = value["candidates"].as_array() {
        ensure!(ips.len() <= 256, "at most 256 candidates per scan");
        for ip in ips {
            let ip = ip
                .as_str()
                .ok_or_else(|| anyhow::anyhow!("invalid candidate"))?;
            ensure!(valid_endpoint(ip), "candidate must be a public IP");
            candidates.insert(ip.to_owned());
        }
    }
    if candidates.is_empty() {
        candidates.insert("183.56.143.147".to_owned());
        for host in [
            "www.googleapis.com",
            "drive.usercontent.google.com",
            "drive.google.com",
        ] {
            if let Ok(addresses) = (host, 443).to_socket_addrs() {
                candidates.extend(
                    addresses
                        .map(|address| address.ip().to_string())
                        .filter(|ip| valid_endpoint(ip)),
                );
            }
        }
    }
    ensure!(candidates.len() <= 256, "at most 256 candidates per scan");
    let mut endpoints = vec![];
    let total = candidates.len() as i64;
    // Serial bounded probes avoid a burst of mobile sockets. Cancellation checked per probe.
    for (index, ip) in candidates.into_iter().enumerate() {
        if progress.is_some_and(|p| p.emit(index as i64, total, 0, 0)) {
            bail!("cancelled");
        }
        let start = Instant::now();
        let verified = (|| -> Result<()> {
            let client = client(Some(&ip))?;
            let response = client
                .get("https://www.googleapis.com/drive/v3/about?fields=user")
                .send()?;
            ensure!(response.status().as_u16() == 401, "invalid probe status");
            let body: Value = response.json()?;
            ensure!(body["error"]["code"] == 401, "invalid API endpoint");
            // A valid TLS handshake plus a normal response from the download origin is required.
            // Do not depend on someone else's publicly shared file remaining available forever.
            let url = Url::parse(
                "https://drive.usercontent.google.com/download?id=gdirect-probe-invalid&export=download",
            )?;
            ensure!(allowed_url(&url), "invalid probe URL");
            let response = client.get(url).send()?;
            ensure!(
                [400, 403, 404].contains(&response.status().as_u16()),
                "unexpected download origin response"
            );
            Ok(())
        })();
        if verified.is_ok() {
            endpoints.push(json!({"ip":ip,"latency_ms":start.elapsed().as_millis() as u64}));
        }
    }
    endpoints.sort_by_key(|e| e["latency_ms"].as_u64().unwrap_or(u64::MAX));
    ensure!(
        !endpoints.is_empty(),
        "no verified direct endpoint; check network or provide candidates"
    );
    Ok(json!({"endpoints":endpoints}))
}
