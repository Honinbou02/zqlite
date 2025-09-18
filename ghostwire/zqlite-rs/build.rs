use std::env;
use std::path::PathBuf;

fn main() {
    // Get the path to the ZQLite library
    let zqlite_dir = env::var("ZQLITE_DIR")
        .unwrap_or_else(|_| "../../".to_string());

    // Build ZQLite C library
    let zqlite_lib_path = format!("{}/zig-out/lib", zqlite_dir);
    let zqlite_include_path = format!("{}/include", zqlite_dir);

    // Build the ZQLite library if it doesn't exist
    if !std::path::Path::new(&format!("{}/libzqlite_c.a", zqlite_lib_path)).exists() {
        println!("cargo:warning=Building ZQLite C library...");
        let output = std::process::Command::new("zig")
            .args(&["build"])
            .current_dir(&zqlite_dir)
            .output()
            .expect("Failed to build ZQLite");

        if !output.status.success() {
            panic!(
                "Failed to build ZQLite: {}",
                String::from_utf8_lossy(&output.stderr)
            );
        }
    }

    // Link to the ZQLite library
    println!("cargo:rustc-link-search=native={}", zqlite_lib_path);
    println!("cargo:rustc-link-lib=static=zqlite_c");

    // Generate bindings
    let bindings = bindgen::Builder::default()
        .header(&format!("{}/zqlite.h", zqlite_include_path))
        .parse_callbacks(Box::new(bindgen::CargoCallbacks::new()))
        .derive_debug(true)
        .derive_default(true)
        .derive_copy(true)
        .derive_eq(true)
        .derive_partialeq(true)
        .generate()
        .expect("Unable to generate bindings");

    // Write the bindings to src/bindings.rs
    let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());
    bindings
        .write_to_file(out_path.join("bindings.rs"))
        .expect("Couldn't write bindings!");

    // Tell cargo to invalidate the built crate whenever the wrapper changes
    println!("cargo:rerun-if-changed={}/zqlite.h", zqlite_include_path);
    println!("cargo:rerun-if-changed={}", zqlite_dir);
}