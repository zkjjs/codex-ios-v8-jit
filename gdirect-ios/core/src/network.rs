use crate::{Progress, field, token, valid_endpoint};
use anyhow::{Result, bail, ensure};
use reqwest::blocking::Client;
use serde_json::{Value, json};
use std::{
    collections::{BTreeSet, VecDeque},
    io::Read,
    net::{IpAddr, SocketAddr, ToSocketAddrs},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
        mpsc,
    },
    thread,
    time::{Duration, Instant},
};

pub(crate) fn client(ip: Option<&str>) -> Result<Client> {
    client_with_timeout(ip, Duration::from_secs(20))
}
fn client_with_timeout(ip: Option<&str>, timeout: Duration) -> Result<Client> {
    let mut builder = Client::builder()
        .no_proxy()
        .redirect(reqwest::redirect::Policy::none())
        .connect_timeout(Duration::from_secs(4))
        .timeout(timeout);
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
pub fn builtin_candidates() -> Vec<String> {
    let data: Value = serde_json::from_str(include_str!("../default-endpoints.json"))
        .expect("bundled endpoint catalog");
    data["candidates"]
        .as_array()
        .expect("candidate array")
        .iter()
        .filter_map(|v| v.as_str().map(str::to_owned))
        .collect()
}
fn verify_api(status: u16, body: &Value) -> Result<()> {
    ensure!(
        status == 401 && body["error"]["code"] == 401,
        "Google API 探测响应异常（HTTP {status}）"
    );
    Ok(())
}
fn verify_download(status: u16, bytes: &[u8]) -> Result<()> {
    ensure!((200..300).contains(&status), "测试文件返回 HTTP {status}");
    ensure!(bytes == b"spam\n", "测试文件内容不匹配");
    Ok(())
}
fn probe(ip: &str) -> Result<(u64, bool)> {
    let client = client_with_timeout(Some(ip), Duration::from_secs(6))?;
    let started = Instant::now();
    let response = client
        .get("https://www.googleapis.com/drive/v3/about?fields=user")
        .send()
        .map_err(|error| anyhow::anyhow!("Google API 连接失败：{}", error.without_url()))?;
    let status = response.status().as_u16();
    let body: Value = response
        .json()
        .map_err(|_| anyhow::anyhow!("Google API 返回无效内容"))?;
    verify_api(status, &body)?;
    // Preserve upstream's real-download check, but distinguish origin reachability from content verification.
    let verified = (|| -> Result<()> {
        let response = client.get("https://drive.usercontent.google.com/download?id=0B9P1L--7Wd2vU3VUVlFnbTgtS2c&export=download&confirm=t").send()?;
        let status = response.status().as_u16();
        let mut bytes = vec![];
        response.take(32).read_to_end(&mut bytes)?;
        verify_download(status, &bytes)
    })().is_ok();
    if !verified {
        let response = client.get("https://drive.usercontent.google.com/download?id=gdirect-probe-invalid&export=download").send()
            .map_err(|error| anyhow::anyhow!("下载域名连接失败：{}", error.without_url()))?;
        let status = response.status().as_u16();
        ensure!(
            [400, 403, 404].contains(&status),
            "下载域名探测未通过（HTTP {status}），可能受重定向、网络或测试文件状态影响"
        );
    }
    Ok((started.elapsed().as_millis() as u64, verified))
}
pub fn scan(value: &Value, progress: Option<Progress>) -> Result<Value> {
    let mut candidates = BTreeSet::new();
    if let Some(ips) = value["candidates"].as_array() {
        ensure!(ips.len() <= 256, "每次最多检测 256 个 IP");
        for ip in ips {
            let ip = ip
                .as_str()
                .ok_or_else(|| anyhow::anyhow!("候选 IP 格式无效"))?;
            ensure!(valid_endpoint(ip), "候选 IP 必须是有效的公网地址：{ip}");
            candidates.insert(ip.to_owned());
        }
    }
    if value["include_defaults"].as_bool().unwrap_or(true) {
        for ip in builtin_candidates() {
            if candidates.len() < 256 {
                candidates.insert(ip);
            }
        }
        for host in [
            "www.googleapis.com",
            "drive.usercontent.google.com",
            "drive.google.com",
        ] {
            if let Ok(addresses) = (host, 443).to_socket_addrs() {
                for ip in addresses
                    .map(|a| a.ip().to_string())
                    .filter(|ip| valid_endpoint(ip))
                {
                    if candidates.len() >= 256 {
                        break;
                    }
                    candidates.insert(ip);
                }
            }
        }
    }
    ensure!(
        !candidates.is_empty() && candidates.len() <= 256,
        "每次需要 1–256 个候选 IP"
    );
    let total = candidates.len() as i64;
    if progress.is_some_and(|p| p.emit(0, total, 0, 0)) {
        bail!("已取消检测");
    }
    let queue = Arc::new(Mutex::new(VecDeque::from_iter(candidates)));
    let cancelled = Arc::new(AtomicBool::new(false));
    let mut endpoints = vec![];
    thread::scope(|scope| {
        let (tx, rx) = mpsc::channel();
        for _ in 0..4 {
            let (queue, cancelled, tx) = (Arc::clone(&queue), Arc::clone(&cancelled), tx.clone());
            scope.spawn(move || {
                while !cancelled.load(Ordering::Relaxed) {
                    let Some(ip) = queue.lock().expect("candidate queue").pop_front() else {
                        break;
                    };
                    let result = probe(&ip).map_err(|e| e.to_string());
                    if tx.send((ip, result)).is_err() {
                        break;
                    }
                }
            });
        }
        drop(tx);
        for (ip, result) in rx {
            let entry = match result {
                Ok((latency, verified)) => {
                    json!({"ip":ip,"available":true,"download_verified":verified,"latency_ms":latency})
                }
                Err(error) => {
                    json!({"ip":ip,"available":false,"download_verified":false,"error":error})
                }
            };
            endpoints.push(entry);
            if !cancelled.load(Ordering::Relaxed)
                && progress.is_some_and(|p| p.emit(endpoints.len() as i64, total, 0, 0))
            {
                cancelled.store(true, Ordering::Relaxed);
            }
        }
    });
    ensure!(!cancelled.load(Ordering::Relaxed), "已取消检测");
    endpoints.sort_by_key(|e| {
        (
            !e["available"].as_bool().unwrap_or(false),
            !e["download_verified"].as_bool().unwrap_or(false),
            e["latency_ms"].as_u64().unwrap_or(u64::MAX),
        )
    });
    let best = endpoints
        .iter()
        .find(|e| e["available"] == true)
        .and_then(|e| e["ip"].as_str());
    // Return failed probes too. The UI must show diagnostics rather than discard the entire scan.
    Ok(json!({"endpoints":endpoints,"best_ip":best,"total":total}))
}

#[cfg(test)]
mod probe_tests {
    use super::*;
    #[test]
    fn api_probe_requires_expected_google_unauthorized_response() {
        assert!(verify_api(401, &json!({"error":{"code":401}})).is_ok());
        assert!(verify_api(200, &json!({"error":{"code":401}})).is_err());
        assert!(verify_api(401, &json!({"message":"not Google API"})).is_err());
    }
    #[test]
    fn download_probe_requires_exact_known_test_content() {
        assert!(verify_download(200, b"spam\n").is_ok());
        assert!(verify_download(403, b"spam\n").is_err());
        assert!(verify_download(200, b"<html>blocked</html>").is_err());
    }
}
