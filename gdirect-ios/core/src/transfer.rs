use crate::{Progress, allowed_url, field, token, valid_endpoint};
use anyhow::{Result, ensure};
use serde_json::{Value, json};
use url::Url;

pub fn download(value: &Value, progress: Option<Progress>) -> Result<Value> {
    let url =
        Url::parse(field(value, "url")?).map_err(|_| anyhow::anyhow!("invalid download URL"))?;
    ensure!(allowed_url(&url), "untrusted download URL");
    let ip = field(value, "ip")?;
    ensure!(valid_endpoint(ip), "endpoint must be a public IP");
    let name = field(value, "name")?;
    ensure!(
        !name.is_empty()
            && name != "."
            && name != ".."
            && !name.contains(['/', '\\', '\0'])
            && name.len() <= 240,
        "invalid output filename"
    );
    let directory = field(value, "directory")?;
    ensure!(
        std::path::Path::new(directory).is_absolute(),
        "output directory must be absolute"
    );
    let auth = token(value)?;
    ensure!(
        auth.is_none() || url.host_str() == Some("www.googleapis.com"),
        "token requires Drive API origin"
    );
    let connections = value["connections"].as_u64().unwrap_or(4).clamp(1, 16) as i32;
    native_download(
        url.as_str(),
        directory,
        name,
        ip,
        auth,
        connections,
        progress,
    )?;
    Ok(json!({"completed":true}))
}

#[cfg(not(feature = "aria2"))]
fn native_download(
    _: &str,
    _: &str,
    _: &str,
    _: &str,
    _: Option<&str>,
    _: i32,
    _: Option<Progress>,
) -> Result<()> {
    anyhow::bail!("native aria2 engine not linked in this build")
}

#[cfg(feature = "aria2")]
fn native_download(
    url: &str,
    directory: &str,
    name: &str,
    ip: &str,
    auth: Option<&str>,
    connections: i32,
    progress: Option<Progress>,
) -> Result<()> {
    use std::{
        ffi::{CString, c_char, c_void},
        sync::Mutex,
    };
    static ENGINE: Mutex<()> = Mutex::new(());
    unsafe extern "C" {
        fn gdirect_download_ex(
            url: *const c_char,
            directory: *const c_char,
            name: *const c_char,
            ip: *const c_char,
            sni: *const c_char,
            token: *const c_char,
            ca: *const c_char,
            connections: i32,
            callback: Option<crate::ProgressFn>,
            context: *mut c_void,
            signals: bool,
        ) -> i32;
    }
    let _guard = ENGINE
        .lock()
        .map_err(|_| anyhow::anyhow!("download engine unavailable"))?;
    if progress.is_some_and(|p| p.emit(0, 0, 0, 0)) {
        anyhow::bail!("cancelled");
    }
    std::fs::create_dir_all(directory)?;
    let url = CString::new(url)?;
    let directory = CString::new(directory)?;
    let name = CString::new(name)?;
    let ip = CString::new(ip)?;
    let auth = CString::new(auth.unwrap_or_default())?;
    // Null SNI preserves the original URL's hostname. AppleTLS uses system trust.
    let code = unsafe {
        gdirect_download_ex(
            url.as_ptr(),
            directory.as_ptr(),
            name.as_ptr(),
            ip.as_ptr(),
            std::ptr::null(),
            auth.as_ptr(),
            std::ptr::null(),
            connections,
            progress.map(|p| p.callback),
            progress.map_or(std::ptr::null_mut(), |p| p.context),
            false,
        )
    };
    ensure!(code == 0, "download stopped (aria2 code {code})");
    Ok(())
}
