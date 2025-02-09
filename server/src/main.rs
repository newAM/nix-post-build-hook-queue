use anyhow::Context;
use log::LevelFilter;
use nix_post_build_hook_queue_shared::SOCK_PATH;
use std::{
    ffi::OsStr,
    fs::{self},
    io::{self, ErrorKind},
    os::unix::{net::UnixDatagram, prelude::OsStrExt},
    process::{Child, Command},
    time::{Duration, Instant},
};

const SIGNING_TIMEOUT: Duration = Duration::from_secs(60);

// 10 minutes seems reasonable
const UPLOAD_TIMEOUT: Duration = Duration::from_secs(600);

fn run_timeout(child: io::Result<Child>, timeout: Duration) -> anyhow::Result<Option<i32>> {
    let start: Instant = Instant::now();
    let mut child: Child = child.context("Failed to spawn child process")?;

    loop {
        let elapsed: Duration = Instant::now().duration_since(start);
        if let Some(status) = child
            .try_wait()
            .context("Error attempting to wait for child process")?
        {
            if status.success() {
                log::debug!("Child exited in {elapsed:?}");
            } else if let Some(code) = status.code() {
                log::error!("Child exited with {code} in {elapsed:?}");
            } else {
                log::error!("Child exited without a return code in {elapsed:?}");
            }
            return Ok(status.code());
        } else if elapsed > timeout {
            log::error!("Timeout of {timeout:?} exceeded, killing child");
            if let Err(e) = child.kill() {
                if !matches!(e.kind(), ErrorKind::InvalidInput) {
                    anyhow::bail!("Failed to kill child process: {e:?}")
                }
            }
            return Ok(None);
        }
    }
}

fn main() -> anyhow::Result<()> {
    systemd_journal_logger::JournalLog::new()
        .context("Failed to create logger")?
        .install()
        .context("Failed to install logger")?;
    log::set_max_level(LevelFilter::Debug);

    let _ = fs::remove_file(SOCK_PATH);
    let sock: UnixDatagram = UnixDatagram::bind(SOCK_PATH)
        .with_context(|| format!("Failed to bind socket at {SOCK_PATH}"))?;

    log::debug!("Bound socket at {SOCK_PATH}");

    // A store path over 4096 characters would be insane, right?
    let mut buf: Vec<u8> = vec![0; 4096];
    loop {
        let n_bytes: usize = sock.recv(&mut buf).context("Failed to recv from socket")?;
        if n_bytes == buf.len() {
            log::error!("Used the complete buffer, {n_bytes} bytes, path may be truncated");
        }
        let path: &OsStr = OsStr::from_bytes(&buf[..n_bytes]);

        if let Some(key_path) = std::env::var_os("NPBHQ_SIGNING_PRIVATE_KEY_PATH") {
            log::info!("Signing {path:?}");
            let child: io::Result<Child> = Command::new("nix")
                .arg("store")
                .arg("sign")
                .arg("--key-file")
                .arg(key_path)
                .arg(path)
                .spawn();

            let signed: bool = run_timeout(child, SIGNING_TIMEOUT)? == Some(0);
            if !signed {
                log::warn!("Path is not signed, skipping all other actions");
                continue;
            }
        }

        if let Some(dst) = std::env::var_os("NPBHQ_UPLOAD_TO") {
            log::info!("Uploading {path:?}");

            let child: io::Result<Child> = Command::new("nix")
                .arg("copy")
                .arg("--to")
                .arg(dst)
                .arg(path)
                .spawn();

            run_timeout(child, UPLOAD_TIMEOUT)?;
        }
    }
}
