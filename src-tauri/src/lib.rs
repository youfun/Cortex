use std::fs::OpenOptions;
use std::io::Write;

const PRODUCT_NAME: &str = "Cortex";

#[cfg(target_os = "windows")]
use std::os::windows::process::CommandExt;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use tauri::{
    menu::{Menu, MenuItem},
    tray::TrayIconBuilder,
    Manager, WebviewUrl, WebviewWindowBuilder, WindowEvent,
};
#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    // Initialize logging
    let log_file = setup_logging();
    log_to_file(&log_file, "========================================");
    log_to_file(&log_file, "Tauri Application Starting");
    log_to_file(&log_file, &format!("Platform: {}", std::env::consts::OS));
    log_to_file(
        &log_file,
        &format!("Architecture: {}", std::env::consts::ARCH),
    );
    log_to_file(&log_file, &format!("Start time: {}", chrono::Local::now()));
    log_to_file(&log_file, "========================================");
    // Shared state for backend process handle
    let backend_child: Arc<Mutex<Option<tauri_plugin_shell::process::CommandChild>>> =
        Arc::new(Mutex::new(None));
    let backend_child_clone = backend_child.clone();
    let log_file_clone = log_file.clone();
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            let _ = app
                .get_webview_window("main")
                .expect("no main window")
                .set_focus();
        }))
        .setup(move |app| {
            // Get an available port
            let port = get_free_port();
            println!("Selected dynamic port: {}", port);
            // System Tray Setup
            let quit_i = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
            let show_i = MenuItem::with_id(app, "show", "Show", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&show_i, &quit_i])?;
            let backend_child_for_tray = backend_child.clone();
            let _tray = TrayIconBuilder::new()
                .icon(app.default_window_icon().unwrap().clone())
                .menu(&menu)
                .show_menu_on_left_click(true)
                .on_menu_event(move |app, event| match event.id.as_ref() {
                    "quit" => {
                        let app_handle = app.clone();
                        let backend_child_inner = backend_child_for_tray.clone();
                        let log_file_inner = log_file_clone.clone();
                        // Capture port variable
                        let shutdown_url = format!("http://localhost:{}/api/system/shutdown", port);
                        tauri::async_runtime::spawn(async move {
                            log_to_file(
                                &log_file_inner,
                                "========================================",
                            );
                            log_to_file(&log_file_inner, "User triggered shutdown from tray");
                            log_to_file(
                                &log_file_inner,
                                &format!("Shutdown time: {}", chrono::Local::now()),
                            );
                            let client = reqwest::Client::builder()
                                .timeout(std::time::Duration::from_secs(2))
                                .build()
                                .unwrap();
                            
                            // Send graceful shutdown via HTTP API
                            log_to_file(&log_file_inner, "Sending shutdown signal to backend...");
                            println!("Sending shutdown signal to backend...");
                            let _ = client.post(&shutdown_url).send().await;
                            log_to_file(&log_file_inner, "Shutdown signal sent");
                            
                            // Wait 300ms for backend to respond (reduced from 500ms)
                            log_to_file(&log_file_inner, "Waiting for backend to respond (300ms)...");
                            tokio::time::sleep(tokio::time::Duration::from_millis(300)).await;
                            // Force kill backend process tree as backup
                            log_to_file(&log_file_inner, "Force killing backend process tree...");
                            if let Ok(mut child_guard) = backend_child_inner.lock() {
                                if let Some(child) = child_guard.take() {
                                    let pid = child.pid();
                                    log_to_file(&log_file_inner, &format!("Killing PID: {}", pid));
                                    
                                    // Windows: Use taskkill /F /T to kill process tree
                                    #[cfg(target_os = "windows")]
                                    {
                                        let _ = std::process::Command::new("taskkill")
                                            .args(&["/F", "/T", "/PID", &pid.to_string()])
                                            .creation_flags(0x08000000) // CREATE_NO_WINDOW
                                            .output();
                                    }
                                    
                                    // Unix: Use kill -9 to kill process group
                                    #[cfg(not(target_os = "windows"))]
                                    {
                                        let _ = std::process::Command::new("kill")
                                            .args(&["-9", &format!("-{}", pid)])
                                            .output();
                                    }
                                    
                                    log_to_file(&log_file_inner, "Process tree killed");
                                }
                            }
                            log_to_file(&log_file_inner, "Tauri application exiting...");
                            log_to_file(
                                &log_file_inner,
                                "========================================",
                            );
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
            // Async start Phoenix backend
            tauri::async_runtime::spawn(async move {
                if let Err(e) = start_backend(&handle, port, backend_child_clone).await {
                    eprintln!("Failed to start {} backend: {}", PRODUCT_NAME, e);
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
fn setup_logging() -> Arc<Mutex<PathBuf>> {
    // Get executable directory
    let exe_path = std::env::current_exe().unwrap_or_else(|_| PathBuf::from("."));
    let exe_dir = exe_path.parent().unwrap_or(std::path::Path::new("."));
    // Create logs directory
    let log_dir = exe_dir.join("logs");
    let _ = std::fs::create_dir_all(&log_dir);
    // Create log file path (with timestamp)
    let log_file = log_dir.join("tauri.log");
    Arc::new(Mutex::new(log_file))
}
fn log_to_file(log_file: &Arc<Mutex<PathBuf>>, message: &str) {
    if let Ok(path) = log_file.lock() {
        if let Ok(mut file) = OpenOptions::new()
            .create(true)
            .append(true)
            .open(path.as_path())
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
    backend_child: Arc<Mutex<Option<tauri_plugin_shell::process::CommandChild>>>,
) -> Result<(), Box<dyn std::error::Error>> {
    use tauri_plugin_shell::ShellExt;
    println!("Starting {} backend on port {}...", PRODUCT_NAME, port);
    println!("Platform: {}", std::env::consts::OS);
    println!("Architecture: {}", std::env::consts::ARCH);
    // Start Phoenix backend (Tauri will auto-select platform binary)
    // Set key environment variables for desktop mode
    let sidecar_command = handle
        .shell()
        .sidecar("cortex_backend")?
        .env("PORT", port.to_string())
        .env("MIX_ENV", "prod")
        .env("RELEASE_NAME", "cortex") // Ensure desktop mode
        .env("PHX_SERVER", "true"); // Enable Phoenix server
    let (_rx, child) = sidecar_command.spawn()?;
    // Save child process handle for later termination
    if let Ok(mut child_guard) = backend_child.lock() {
        *child_guard = Some(child);
    }
    println!("Backend process started, waiting for it to be ready...");
    // Poll to check backend readiness
    let mut attempts = 0;
    let max_attempts = 60;
    let base_url = format!("http://localhost:{}", port);
    loop {
        attempts += 1;
        if attempts > max_attempts {
            return Err(format!("Backend failed to start after {} attempts", max_attempts).into());
        }
        match reqwest::get(&base_url).await {
            Ok(response) if response.status().is_success() => {
                println!("Backend is ready after {} attempts!", attempts);
                break;
            }
            Ok(response) => {
                println!(
                    "Backend responded with status: {} (attempt {})",
                    response.status(),
                    attempts
                );
                tokio::time::sleep(tokio::time::Duration::from_secs(1)).await;
            }
            Err(e) => {
                if attempts % 5 == 0 {
                    println!(
                        "Waiting for backend... (attempt {}/{}): {}",
                        attempts, max_attempts, e
                    );
                }
                tokio::time::sleep(tokio::time::Duration::from_secs(1)).await;
            }
        }
    }
    // Open main window
    WebviewWindowBuilder::new(
        handle,
        "main",
        WebviewUrl::External(base_url.parse().unwrap()),
    )
    .title(PRODUCT_NAME)
    .inner_size(1200.0, 800.0)
    .center()
    .build()?;
    println!("Main window opened successfully");
    Ok(())
}
