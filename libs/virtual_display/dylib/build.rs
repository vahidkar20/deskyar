use cc;

fn build_c_impl() {
    let mut build = cc::Build::new();

    #[cfg(target_os = "windows")]
    build.file("src/win10/IddController.c");

    build.flag_if_supported("-Wno-c++0x-extensions");
    build.flag_if_supported("-Wno-return-type-c-linkage");
    build.flag_if_supported("-Wno-invalid-offsetof");
    build.flag_if_supported("-Wno-unused-parameter");

    if build.get_compiler().is_like_msvc() {
        build.define("WIN32", "");
        build.flag("-Z7");
        build.flag("-GR-");
        // build.flag("-std:c++11");
    } else {
        build.flag("-fPIC");
        // build.flag("-std=c++11");
        // build.flag("-include");
        // build.flag(&confdefs_path.to_string_lossy());
    }

    #[cfg(target_os = "windows")]
    build.compile("win_virtual_display");

    #[cfg(target_os = "windows")]
    println!("cargo:rerun-if-changed=src/win10/IddController.c");
}

// VERSIONINFO for the shipped DLL.
//
// Without this the file reached the payload with no resource section at all:
// Windows showed a blank Details tab and no company, product or version string.
// For a DLL that a remote-access payload loads at runtime that is a strong
// heuristic signal on its own, and code-signing review requires every shipped
// binary to carry consistent product metadata.
//
// The version and the string fields both come from the manifest - `version`
// for the numeric FILEVERSION/PRODUCTVERSION pair and
// `[package.metadata.winres]` for the rest - so there is no second source of
// truth to keep in step here.
//
// No manifest is embedded: a DLL has no activation context of its own, and
// NexDesk.exe supplies one from Runner.rc.
#[cfg(windows)]
fn build_version_info() {
    use std::io::Write;
    if std::env::var("PROFILE").unwrap() == "release" {
        let mut res = winres::WindowsResource::new();
        res.set_language(winapi::um::winnt::MAKELANGID(
            winapi::um::winnt::LANG_ENGLISH,
            winapi::um::winnt::SUBLANG_ENGLISH_US,
        ));
        match res.compile() {
            Err(e) => {
                write!(std::io::stderr(), "{}", e).unwrap();
                std::process::exit(1);
            }
            Ok(_) => {}
        }
    }
}

fn main() {
    build_c_impl();
    #[cfg(windows)]
    build_version_info();
}
