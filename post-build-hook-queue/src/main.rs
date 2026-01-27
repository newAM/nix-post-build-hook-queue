use anyhow::Context;
use log::LevelFilter;
use std::{
    ffi::{OsStr, OsString},
    fs::create_dir_all,
    io::{self, ErrorKind},
    os::{
        fd::AsFd as _,
        unix::{net::UnixDatagram, prelude::OsStrExt},
    },
    path::PathBuf,
    process::{Child, Command},
    sync::{Arc, Mutex},
    thread::JoinHandle,
    time::{Duration, Instant},
};
use wait_timeout::ChildExt;

// created by systemd service
const UPLOAD_STATUS_DIR: &str = "/run/nix-post-build-hook-queue/uploading";

const SIGNING_TIMEOUT: Duration = Duration::from_secs(60);

// 10 minutes seems reasonable
const UPLOAD_TIMEOUT: Duration = Duration::from_secs(600);

fn run_timeout(child: io::Result<Child>, timeout: Duration) -> anyhow::Result<Option<i32>> {
    let start: Instant = Instant::now();
    let mut child: Child = child.context("Failed to spawn child process")?;

    if let Some(status) = child
        .wait_timeout(timeout)
        .context("Error attempting to wait for child process")?
    {
        let elapsed: Duration = Instant::now().duration_since(start);
        if status.success() {
            log::debug!("Child exited in {elapsed:?}");
        } else if let Some(code) = status.code() {
            log::error!("Child exited with {code} in {elapsed:?}");
        } else {
            log::error!("Child exited without a return code in {elapsed:?}");
        }
        Ok(status.code())
    } else {
        log::error!("Timeout of {timeout:?} exceeded, killing child");
        if let Err(e) = child.kill()
            && !matches!(e.kind(), ErrorKind::InvalidInput)
        {
            anyhow::bail!("Failed to kill child process: {e:?}")
        }
        Ok(None)
    }
}

fn main() -> anyhow::Result<()> {
    systemd_journal_logger::JournalLog::new()
        .context("Failed to create logger")?
        .install()
        .context("Failed to install logger")?;
    log::set_max_level(LevelFilter::Debug);

    create_dir_all(UPLOAD_STATUS_DIR).expect("Failed to create upload status directory");

    let stdin_fd = std::io::stdin()
        .as_fd()
        .try_clone_to_owned()
        .context("Failed to convert stdin to an owned fd")?;

    let workers: usize = std::env::var("NPBHQ_WORKERS")
        .as_deref()
        .unwrap_or("4")
        .parse()
        .context("NPBHQ_WORKERS is not an unsigned integer")?;
    let queue_size: usize = std::env::var("NPBHQ_QUEUE_SIZE")
        .as_deref()
        .unwrap_or("64")
        .parse()
        .context("NPBHQ_QUEUE_SIZE is not an unsigned integer")?;

    let (sender, receiver) = std::sync::mpsc::sync_channel::<OsString>(queue_size);
    let receiver = Arc::new(Mutex::new(receiver));

    let mut worker_threads = Vec::<JoinHandle<()>>::new();
    for _ in 0..workers {
        let receiver = receiver.clone();
        worker_threads.push(std::thread::spawn(move || {
            while let Ok(path) = {
                let receiver = receiver.lock().unwrap();
                receiver.recv()
            } {
                if let Err(e) = try_push_path(&path) {
                    log::error!(
                        "Push path failed for path {}: {}",
                        String::from_utf8_lossy(path.as_bytes()),
                        e
                    );
                }
            }
        }));
    }

    let sock: UnixDatagram = UnixDatagram::from(stdin_fd);
    // A store path over 4096 characters would be insane, right?
    let mut buf: Vec<u8> = vec![0; 4096];
    loop {
        let n_bytes: usize = match sock.recv(&mut buf) {
            Ok(n_bytes) => n_bytes,
            Err(e) => {
                let code = match e.kind() {
                    ErrorKind::WouldBlock => {
                        // service will be started by systemd when there is more data
                        0
                    }
                    _ => {
                        log::error!("Failed to recv from socket: {e:?}");
                        1
                    }
                };
                drop(sock);
                drop(sender);
                log::info!("Waiting for worker threads to exit");
                for thread in worker_threads {
                    if thread.join().is_err() {
                        log::error!("Worker thread panicked");
                    }
                }
                std::process::exit(code);
            }
        };
        if n_bytes == buf.len() {
            log::error!("Used the complete buffer, {n_bytes} bytes, path may be truncated");
        }
        let path: OsString = OsStr::from_bytes(&buf[..n_bytes]).to_owned();

        sender.send(path)?;
    }
}

fn try_push_path(path: &OsStr) -> anyhow::Result<()> {
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
            anyhow::bail!("Path is not signed, skipping all other actions")
        }
    }

    if let Some(dst) = std::env::var_os("NPBHQ_UPLOAD_TO") {
        log::info!("Uploading {path:?}");

        // TODO: create file
        let filename = OsStr::from_bytes(&path.as_bytes()[11..]);
        let mut filepath = PathBuf::from(UPLOAD_STATUS_DIR);
        filepath.push(filename);
        std::fs::File::create(&filepath).context("Failed to create upload status file")?;

        let child: io::Result<Child> = Command::new("nix")
            .arg("copy")
            .arg("--to")
            .arg(dst)
            .arg(path)
            .spawn();

        let result = run_timeout(child, UPLOAD_TIMEOUT);

        if let Err(e) = std::fs::remove_file(&filepath) {
            log::error!("Failed to remove upload status file: {e}");
        }

        result?;
    }

    Ok(())
}
