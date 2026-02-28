// Prevents additional console window on Windows in release
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::fs::OpenOptions;
use std::io::Write;
use std::path::PathBuf;
use std::sync::Mutex;
use std::time::Duration;
use tauri::{
    menu::{Menu, MenuItem},
    tray::TrayIconBuilder,
    Manager, WebviewUrl, WebviewWindowBuilder, WindowEvent,
};
use tauri_plugin_shell::process::CommandEvent;
use tauri_plugin_shell::ShellExt;

const PRODUCT_NAME: &str = "Cortex";

struct AppState {
    sidecar_child: Mutex<Option<SidecarProcess>>,
}

struct SidecarProcess {
    child: Option<tauri_plugin_shell::process::CommandChild>,
    pid: Option<u32>,
}

impl Drop for SidecarProcess {
    fn drop(&mut self) {
        if let Some(child) = self.child.take() {
            let _ = child.kill();
        }
    }
}

fn kill_sidecar(app: &tauri::AppHandle) {
    if let Some(state) = app.try_state::<AppState>() {
        if let Ok(mut guard) = state.sidecar_child.lock() {
            if let Some(mut process) = guard.take() {
                if let Some(pid) = process.pid {
                    println!("Attempting graceful shutdown of sidecar (PID: {})...", pid);

                    #[cfg(unix)]
                    {
                        use std::process::Command;
                        let _ = Command::new("kill")
                            .args(["-TERM", &pid.to_string()])
                            .output();

                        let timeout = Duration::from_millis(2000);
                        let start = std::time::Instant::now();

                        while start.elapsed() < timeout {
                            let status = Command::new("kill")
                                .args(["-0", &pid.to_string()])
                                .output();

                            if let Ok(output) = status {
                                if !output.status.success() {
                                    println!("Sidecar shut down gracefully");
                                    return;
                                }
                            }

                            std::thread::sleep(Duration::from_millis(100));
                        }

                        println!("Graceful shutdown timeout, forcing kill...");
                    }

                    #[cfg(windows)]
                    {
                        std::thread::sleep(Duration::from_millis(2000));
                    }
                }

                if let Some(child) = process.child.take() {
                    println!("Sending SIGKILL to sidecar...");
                    let _ = child.kill();
                }
            }
        }
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let log_file = setup_logging();
    log_to_file(&log_file, "========================================");
    log_to_file(&log_file, &format!("{} Application Starting", PRODUCT_NAME));
    log_to_file(&log_file, &format!("Platform: {}", std::env::consts::OS));
    log_to_file(&log_file, &format!("Start time: {}", chrono::Local::now()));
    log_to_file(&log_file, "========================================");

    let log_file_clone = log_file.clone();

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            let _ = app
                .get_webview_window("main")
                .expect("no main window")
                .set_focus();
        }))
        .manage(AppState {
            sidecar_child: Mutex::new(None),
        })
        .setup(move |app| {
            log_to_file(&log_file, "Entered setup function");

            let port = get_free_port();
            log_to_file(&log_file, &format!("Selected dynamic port: {}", port));

            // System Tray Setup
            let quit_i = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
            let show_i = MenuItem::with_id(app, "show", "Show", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&show_i, &quit_i])?;

            let _tray = TrayIconBuilder::new()
                .icon(app.default_window_icon().unwrap().clone())
                .menu(&menu)
                .show_menu_on_left_click(true)
                .on_menu_event(move |app, event| match event.id.as_ref() {
                    "quit" => {
                        let app_handle = app.clone();
                        let log_file_inner = log_file_clone.clone();
                        tauri::async_runtime::spawn(async move {
                            log_to_file(&log_file_inner, "User triggered shutdown from tray");
                            kill_sidecar(&app_handle);
                            log_to_file(&log_file_inner, "Tauri application exiting...");
                            app_handle.exit(0);
                        });
                    }
                    "show" => {
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.set_focus();
                        }
                    }
                    _ => {}
                })
                .build(app)?;

            let handle = app.handle().clone();
            let log_file_for_backend = log_file.clone();

            tauri::async_runtime::spawn(async move {
                match start_backend(&handle, port, &log_file_for_backend).await {
                    Ok(_) => log_to_file(&log_file_for_backend, "Backend started successfully"),
                    Err(e) => {
                        let error_msg = format!("FATAL: Failed to start backend: {}", e);
                        log_to_file(&log_file_for_backend, &error_msg);
                        eprintln!("{}", error_msg);
                    }
                }
            });

            Ok(())
        })
        .on_window_event(|window, event| {
            if let WindowEvent::CloseRequested { api, .. } = event {
                window.hide().unwrap();
                api.prevent_close();
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

fn setup_logging() -> std::sync::Arc<Mutex<PathBuf>> {
    let exe_path = std::env::current_exe().unwrap_or_else(|_| PathBuf::from("."));
    let exe_dir = exe_path.parent().unwrap_or(std::path::Path::new("."));
    let log_dir = exe_dir.join("logs");
    let _ = std::fs::create_dir_all(&log_dir);
    let log_file = log_dir.join("tauri.log");
    std::sync::Arc::new(Mutex::new(log_file))
}

fn log_to_file(log_file: &std::sync::Arc<Mutex<PathBuf>>, message: &str) {
    if let Ok(path) = log_file.lock() {
        if let Ok(mut file) = OpenOptions::new()
            .create(true)
            .append(true)
            .open(path.as_ref())
        {
            let timestamp = chrono::Local::now().format("%Y-%m-%d %H:%M:%S%.3f");
            let _ = writeln!(file, "[{}] {}", timestamp, message);
        }
    }
}

fn get_free_port() -> u16 {
    std::net::TcpListener::bind("127.0.0.1:0")
        .and_then(|l| l.local_addr())
        .map(|a| a.port())
        .unwrap_or(4000)
}

async fn start_backend(
    handle: &tauri::AppHandle,
    port: u16,
    log_file: &std::sync::Arc<Mutex<PathBuf>>,
) -> Result<(), Box<dyn std::error::Error>> {
    log_to_file(log_file, &format!("Starting backend on port {}...", port));

    let sidecar_command = handle
        .shell()
        .sidecar("cortex_backend")
        .expect("failed to setup `cortex_backend` sidecar");

    let sidecar_command = sidecar_command
        .env("PORT", port.to_string())
        .env("MIX_ENV", "prod")
        .env("RELEASE_NAME", "desktop")
        .env("PHX_SERVER", "true")
        .env("DESKTOP_MODE", "true");

    log_to_file(log_file, "Spawning backend process...");
    let (mut rx, child) = sidecar_command
        .spawn()
        .expect("Failed to spawn cortex_backend sidecar");

    let pid = child.pid();
    log_to_file(log_file, &format!("Backend spawned with PID: {}", pid));

    // Store child process handle
    if let Some(state) = handle.try_state::<AppState>() {
        if let Ok(mut guard) = state.sidecar_child.lock() {
            *guard = Some(SidecarProcess {
                child: Some(child),
                pid: Some(pid),
            });
        }
    }

    // Capture backend output
    let log_file_clone = log_file.clone();
    tauri::async_runtime::spawn(async move {
        while let Some(event) = rx.recv().await {
            if let CommandEvent::Stdout(line_bytes) = event {
                let line = String::from_utf8_lossy(&line_bytes);
                log_to_file(&log_file_clone, &format!("[BACKEND] {}", line));
            }
        }
    });

    // Start heartbeat
    start_heartbeat(log_file);

    // Wait for server to be ready
    check_server_started(port, log_file).await;

    // Open main window
    let base_url = format!("http://localhost:{}", port);
    log_to_file(log_file, &format!("Opening window: {}", base_url));

    WebviewWindowBuilder::new(
        handle,
        "main",
        WebviewUrl::External(base_url.parse().unwrap()),
    )
    .title(PRODUCT_NAME)
    .inner_size(1200.0, 800.0)
    .center()
    .build()?;

    log_to_file(log_file, "Window opened successfully");
    Ok(())
}

fn start_heartbeat(log_file: &std::sync::Arc<Mutex<PathBuf>>) {
    log_to_file(log_file, "Starting heartbeat to Phoenix sidecar...");

    std::thread::spawn(|| {
        use std::os::unix::net::UnixStream;

        let socket_path = "/tmp/tauri_heartbeat_cortex.sock";
        let interval = Duration::from_millis(100);

        // Wait for socket to be ready
        let mut stream = loop {
            match UnixStream::connect(socket_path) {
                Ok(s) => break s,
                Err(_) => std::thread::sleep(Duration::from_millis(100)),
            }
        };

        println!("Connected to heartbeat socket");

        loop {
            match stream.write_all(b"h") {
                Ok(_) => {}
                Err(_) => break,
            }
            std::thread::sleep(interval);
        }
    });
}

async fn check_server_started(port: u16, log_file: &std::sync::Arc<Mutex<PathBuf>>) {
    let addr = format!("localhost:{}", port);
    log_to_file(log_file, &format!("Waiting for Phoenix to start on {}...", addr));

    loop {
        if std::net::TcpStream::connect(&addr).is_ok() {
            log_to_file(log_file, "Phoenix is ready!");
            break;
        }
        tokio::time::sleep(Duration::from_millis(200)).await;
    }
}
