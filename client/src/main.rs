use anyhow::{anyhow, Context};
use nix_post_build_hook_queue_shared::SOCK_PATH;
use std::os::unix::net::UnixDatagram;

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

    for store_path in std::env::args().skip(1) {
        println!("Sending {} to daemon for upload", store_path);
        let n_bytes: usize = sock
            .send(store_path.as_bytes())
            .with_context(|| format!("Failed to write store path '{store_path}' to socket"))?;
        let len: usize = store_path.as_bytes().len();
        if n_bytes != len {
            return Err(anyhow!("Incomplete write, wrote {n_bytes} / {len} bytes"));
        }
    }

    Ok(())
}
