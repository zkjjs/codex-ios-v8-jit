use std::{env, path::PathBuf};
fn main() {
    println!("cargo:rerun-if-env-changed=GDIRECT_ARIA2_PREFIX");
    if env::var_os("CARGO_FEATURE_ARIA2").is_none() {
        return;
    }
    let prefix = PathBuf::from(
        env::var("GDIRECT_ARIA2_PREFIX").expect("GDIRECT_ARIA2_PREFIX is required with aria2"),
    );
    cc::Build::new()
        .cpp(true)
        .std("c++11")
        .file("../native/bridge.cc")
        .include(prefix.join("include"))
        .compile("gdirect_bridge");
    println!(
        "cargo:rustc-link-search=native={}",
        prefix.join("lib").display()
    );
    println!("cargo:rustc-link-lib=static=aria2");
    if env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("ios") {
        for framework in ["Security", "CoreFoundation", "SystemConfiguration"] {
            println!("cargo:rustc-link-lib=framework={framework}");
        }
    }
    println!("cargo:rerun-if-changed=../native/bridge.cc");
}
