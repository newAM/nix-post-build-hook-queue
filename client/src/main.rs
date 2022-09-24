use anyhow::{anyhow, Context};
use nix_post_build_hook_queue_shared::SOCK_PATH;
use std::os::unix::{net::UnixDatagram, prelude::OsStringExt};

fn main() {
    // Never return errors
    // Signing and uploading store paths is not critical
    if let Err(e) = fallible_main() {
        eprintln!("{e:?}")
    }
}

fn fallible_main() -> anyhow::Result<()> {
    let sock: UnixDatagram = UnixDatagram::unbound()?;
    sock.connect(SOCK_PATH)
        .with_context(|| format!("Failed to connect to socket at {SOCK_PATH}"))?;

    let out_paths: Vec<u8> = std::env::var_os("OUT_PATHS")
        .context("OUT_PATHS environment variable not set")?
        .into_vec();

    for store_path in out_paths.split(|ch| *ch == b' ') {
        let store_path_utf8 = String::from_utf8_lossy(store_path);
        println!("Sending to daemon: {store_path_utf8}");
        let n_bytes: usize = sock
            .send(store_path)
            .with_context(|| format!("Failed to write store path '{store_path_utf8}' to socket"))?;
        let len: usize = store_path.len();
        if n_bytes != len {
            return Err(anyhow!("Incomplete write, wrote {n_bytes} / {len} bytes"));
        }
    }

    Ok(())
}
