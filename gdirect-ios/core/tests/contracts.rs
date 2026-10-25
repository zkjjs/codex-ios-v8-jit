use gdirect_core::{allowed_url, execute, resolve, valid_endpoint};
use url::Url;

#[test]
fn link_resource_key_and_authenticated_export_survive_resolution() {
    let value = resolve(
        "https://drive.google.com/file/d/abc_123/view?resourcekey=key-1",
        true,
        Some("application/pdf"),
    )
    .unwrap();
    let url = Url::parse(&value.url).unwrap();
    assert_eq!(value.file_id, "abc_123");
    assert_eq!(url.path(), "/drive/v3/files/abc_123/export");
    assert!(
        url.query_pairs()
            .any(|(k, v)| k == "resourcekey" && v == "key-1")
    );
}

#[test]
fn refuses_credentials_ports_and_lookalike_hosts() {
    for input in [
        "http://drive.google.com/file/d/abc/view",
        "https://drive.google.com.evil.test/file/d/abc/view",
        "https://user@drive.google.com/file/d/abc/view",
        "https://drive.google.com:444/file/d/abc/view",
        "https://evil.test/?id=abc",
    ] {
        assert!(resolve(input, false, None).is_err(), "{input}");
    }
    assert!(!allowed_url(
        &Url::parse("https://drive.google.com:444/a").unwrap()
    ));
}

#[test]
fn endpoints_must_be_public_ip_literals() {
    for input in [
        "127.0.0.1",
        "10.1.2.3",
        "198.18.0.1",
        "169.254.1.2",
        "::1",
        "::ffff:127.0.0.1",
        "224.0.0.1",
        "example.com",
        "fc00::1",
    ] {
        assert!(!valid_endpoint(input), "{input}");
    }
    assert!(valid_endpoint("8.8.8.8"));
    assert!(valid_endpoint("2001:4860:4860::8888"));
}

#[test]
fn ffi_protocol_never_echoes_secrets_on_errors() {
    let result = execute(r#"{"command":"unsupported","token":"secret-token"}"#, None);
    assert!(result.contains("error"));
    assert!(!result.contains("secret-token"));
    assert!(execute("not-json", None).contains("error"));
}

#[test]
fn direct_download_requires_public_ip_and_safe_filename() {
    for (ip, name) in [
        ("127.0.0.1", "file"),
        ("8.8.8.8", "../escape"),
        ("8.8.8.8", "/escape"),
    ] {
        let input = serde_json::json!({"command":"download", "url":"https://www.googleapis.com/drive/v3/files/abc?alt=media", "ip":ip, "directory":"/tmp", "name":name});
        assert!(execute(&input.to_string(), None).contains("error"));
    }
}
