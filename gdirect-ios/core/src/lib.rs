//! GPL-2.0-or-later. Mobile extraction of mizorewww/gdirect (d260f5d).
mod drive;
mod network;
mod transfer;

use anyhow::{Result, bail, ensure};
use serde::Serialize;
use serde_json::{Value, json};
use std::ffi::{CStr, CString, c_char, c_void};
use url::Url;

pub type ProgressFn = extern "C" fn(i64, i64, i32, i32, *mut c_void) -> i32;
#[derive(Clone, Copy)]
pub struct Progress {
    pub callback: ProgressFn,
    pub context: *mut c_void,
}
impl Progress {
    pub fn emit(self, done: i64, total: i64, speed: i32, connections: i32) -> bool {
        (self.callback)(done, total, speed, connections, self.context) != 0
    }
}

pub fn allowed_url(url: &Url) -> bool {
    let host = url.host_str().unwrap_or_default();
    url.scheme() == "https"
        && url.username().is_empty()
        && url.password().is_none()
        && url.port_or_known_default() == Some(443)
        && (matches!(
            host,
            "drive.google.com"
                | "drive.usercontent.google.com"
                | "www.googleapis.com"
                | "content.googleapis.com"
                | "drive.googleapis.com"
        ) || host.ends_with(".googleusercontent.com"))
}

pub fn valid_endpoint(input: &str) -> bool {
    use std::net::IpAddr;
    match input.parse::<IpAddr>() {
        Ok(IpAddr::V4(ip)) => {
            let octets = ip.octets();
            !ip.is_private()
                && !ip.is_loopback()
                && !ip.is_link_local()
                && !ip.is_unspecified()
                && !ip.is_multicast()
                && !ip.is_broadcast()
                && !ip.is_documentation()
                && octets[0] != 0
                && octets[0] < 240
                && !(octets[0] == 198 && matches!(octets[1], 18 | 19))
                && !(octets[0] == 100 && (64..=127).contains(&octets[1]))
        }
        Ok(IpAddr::V6(ip)) => {
            if let Some(v4) = ip.to_ipv4_mapped() {
                return valid_endpoint(&v4.to_string());
            }
            !ip.is_loopback()
                && !ip.is_unspecified()
                && !ip.is_multicast()
                && !ip.is_unique_local()
                && !ip.is_unicast_link_local()
                && (ip.segments()[0] & 0xe000) == 0x2000
                && !(ip.segments()[0] == 0x2001 && ip.segments()[1] == 0x0db8)
        }
        Err(_) => false,
    }
}

#[derive(Serialize)]
pub struct Resolved {
    pub file_id: String,
    pub url: String,
}
pub fn resolve(input: &str, authenticated: bool, export: Option<&str>) -> Result<Resolved> {
    let file = drive::FileRef::parse(input)?;
    Ok(Resolved {
        url: file.url(authenticated, export)?.into(),
        file_id: file.id,
    })
}

pub(crate) fn field<'a>(value: &'a Value, key: &str) -> Result<&'a str> {
    value[key]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("missing required field: {key}"))
}
pub(crate) fn token(value: &Value) -> Result<Option<&str>> {
    let token = value["token"].as_str().filter(|s| !s.is_empty());
    if let Some(token) = token {
        ensure!(
            token.bytes().all(|b| b.is_ascii_graphic()),
            "invalid access token"
        );
    }
    Ok(token)
}

pub fn execute(input: &str, progress: Option<Progress>) -> String {
    let result = (|| -> Result<Value> {
        let value: Value =
            serde_json::from_str(input).map_err(|_| anyhow::anyhow!("invalid JSON request"))?;
        let result = match field(&value, "command")? {
            "resolve" => serde_json::to_value(resolve(
                field(&value, "input")?,
                value["authenticated"].as_bool().unwrap_or(false),
                value["export"].as_str(),
            )?)?,
            "confirmation" => {
                let base = Url::parse(field(&value, "base")?)?;
                ensure!(allowed_url(&base), "untrusted download URL");
                json!({"url":drive::confirmation(field(&value, "html")?, &base)?.as_str()})
            }
            "candidates" => json!({"candidates":network::builtin_candidates()}),
            "scan" => network::scan(&value, progress)?,
            "list" => network::list(&value)?,
            "metadata" => network::metadata(&value)?,
            "download" => transfer::download(&value, progress)?,
            _ => bail!("unsupported command"),
        };
        Ok(json!({"ok":result}))
    })();
    match result {
        Ok(value) => value.to_string(),
        Err(error) => json!({"error":error.to_string()}).to_string(),
    }
}

/// # Safety
/// request must be a valid NUL-terminated string; context remains valid until return.
/// The callback must not unwind or retain context past the call. Free the result with gd_free.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_execute(
    request: *const c_char,
    callback: Option<ProgressFn>,
    context: *mut c_void,
) -> *mut c_char {
    let response = std::panic::catch_unwind(|| {
        if request.is_null() {
            return json!({"error":"missing request"}).to_string();
        }
        let input = unsafe { CStr::from_ptr(request) }
            .to_str()
            .unwrap_or_default();
        execute(
            input,
            callback.map(|callback| Progress { callback, context }),
        )
    })
    .unwrap_or_else(|_| json!({"error":"native core failed"}).to_string());
    CString::new(response)
        .expect("JSON has no NUL bytes")
        .into_raw()
}

/// # Safety
/// response must be returned by gd_execute and not already freed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_free(response: *mut c_char) {
    if !response.is_null() {
        drop(unsafe { CString::from_raw(response) });
    }
}
