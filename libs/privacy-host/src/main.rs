//! NexDesk privacy-mode overlay host.
//!
//! Privacy mode needs one opaque, topmost window per monitor, owned by a process
//! other than the one being captured, so the local screen can be blanked while
//! the remote session keeps streaming the real desktop.
//!
//! Upstream implemented that by copying `C:\Windows\System32\RuntimeBroker.exe`
//! next to the application and injecting a DLL into the copy with
//! `VirtualAllocEx` / `WriteProcessMemory` / `QueueUserAPC`. That is process
//! hollowing into a copy of a system binary, and it was by far the strongest
//! malware heuristic the application carried - it outweighed every metadata fix
//! we could make. It also bought nothing: the thing privacy mode actually needs
//! is a top-level window that capture APIs skip, and any process can create one.
//!
//! So this binary creates those windows itself and marks them with
//! `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)`. No system binary is
//! copied, no memory is written into another process, and the process that owns
//! the overlay is a normal signed-able part of the product.
//!
//! Protocol with the application (see `src/privacy_mode/win_topmost_window.rs`):
//!
//! * one window per monitor, class `NexDeskPrivacyWindowClass`, title
//!   `NexDeskPrivacyWindow`;
//! * `WM_APP + 3` shows them, `WM_APP + 4` hides them;
//! * the application finds them with `FindWindowExW` and posts those messages,
//!   so nothing here needs a command channel or shared state;
//! * the application owns this process and terminates it when privacy mode ends.

#[cfg(not(windows))]
fn main() {}

#[cfg(windows)]
fn main() {
    std::process::exit(overlay::run());
}

#[cfg(windows)]
mod overlay {
    use std::ptr::{null, null_mut};
    use std::sync::atomic::{AtomicBool, Ordering};

    use winapi::shared::minwindef::{BOOL, DWORD, LPARAM, LRESULT, TRUE, UINT, WPARAM};
    use winapi::shared::windef::{HBRUSH, HDC, HMONITOR, HWND, RECT};
    use winapi::um::libloaderapi::GetModuleHandleW;
    use winapi::um::wingdi::{GetStockObject, BLACK_BRUSH};
    use winapi::um::winuser::{
        CreateWindowExW, DefWindowProcW, DestroyWindow, DispatchMessageW, EnumDisplayMonitors,
        FindWindowExW, GetMessageW, GetMonitorInfoW, RegisterClassW, SetWindowDisplayAffinity,
        SetWindowPos, ShowWindow, TranslateMessage, HWND_TOPMOST, MONITORINFO, MSG, SWP_NOACTIVATE,
        SWP_NOMOVE, SWP_NOSIZE, SW_HIDE, SW_SHOWNOACTIVATE, WM_APP, WM_DESTROY, WM_DISPLAYCHANGE,
        WNDCLASSW, WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW, WS_EX_TOPMOST, WS_POPUP,
    };

    // Must match PRIVACY_WINDOW_CLASS / PRIVACY_WINDOW_NAME in
    // src/privacy_mode/win_topmost_window.rs. The application locates these
    // windows by class *and* title, so changing one side alone silently breaks
    // privacy mode: it would find nothing and refuse to turn on.
    const WINDOW_CLASS: &str = "NexDeskPrivacyWindowClass";
    const WINDOW_TITLE: &str = "NexDeskPrivacyWindow";

    // Must match WM_RUSTDESK_SHOW_WINDOWS / WM_RUSTDESK_HIDE_WINDOWS.
    const WM_SHOW_WINDOWS: UINT = WM_APP + 3;
    const WM_HIDE_WINDOWS: UINT = WM_APP + 4;

    const WDA_MONITOR: DWORD = 0x0000_0001;
    const WDA_EXCLUDEFROMCAPTURE: DWORD = 0x0000_0011;

    /// Whether the overlays are meant to be on screen right now.
    ///
    /// Replayed when a monitor appears while privacy mode is already on, so the
    /// new overlay starts out shown instead of blank.
    static SHOWN: AtomicBool = AtomicBool::new(false);

    /// Set by `WM_DISPLAYCHANGE`, acted on by the message loop. Rebuilding from
    /// inside the window procedure would destroy the window whose procedure is
    /// still running.
    static REBUILD: AtomicBool = AtomicBool::new(false);

    fn wide(s: &str) -> Vec<u16> {
        s.encode_utf16().chain(std::iter::once(0)).collect()
    }

    pub fn run() -> i32 {
        unsafe {
            let class = wide(WINDOW_CLASS);
            let hinstance = GetModuleHandleW(null());
            let wc = WNDCLASSW {
                style: 0,
                lpfnWndProc: Some(wnd_proc),
                cbClsExtra: 0,
                cbWndExtra: 0,
                hInstance: hinstance,
                hIcon: null_mut(),
                hCursor: null_mut(),
                hbrBackground: GetStockObject(BLACK_BRUSH as i32) as HBRUSH,
                lpszMenuName: null(),
                lpszClassName: class.as_ptr(),
            };
            if RegisterClassW(&wc) == 0 {
                return 1;
            }
            if create_overlays() == 0 {
                return 2;
            }

            let mut msg: MSG = std::mem::zeroed();
            while GetMessageW(&mut msg, null_mut(), 0, 0) > 0 {
                TranslateMessage(&msg);
                DispatchMessageW(&msg);
                if REBUILD.swap(false, Ordering::SeqCst) {
                    destroy_overlays();
                    create_overlays();
                }
            }
            0
        }
    }

    /// Creates one overlay per monitor. Returns how many were created, so the
    /// caller can tell "no monitors" apart from "creation failed".
    unsafe fn create_overlays() -> usize {
        let mut rects: Vec<RECT> = Vec::new();
        if EnumDisplayMonitors(
            null_mut(),
            null(),
            Some(collect_monitor),
            &mut rects as *mut Vec<RECT> as LPARAM,
        ) == 0
        {
            return 0;
        }

        let class = wide(WINDOW_CLASS);
        let title = wide(WINDOW_TITLE);
        let hinstance = GetModuleHandleW(null());
        let mut created = 0;

        for rect in rects {
            let hwnd = CreateWindowExW(
                WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
                class.as_ptr(),
                title.as_ptr(),
                WS_POPUP,
                rect.left,
                rect.top,
                rect.right - rect.left,
                rect.bottom - rect.top,
                null_mut(),
                null_mut(),
                hinstance,
                null_mut(),
            );
            if hwnd.is_null() {
                continue;
            }

            // Visible to the person in front of the screen, absent from every
            // capture API. WDA_EXCLUDEFROMCAPTURE needs Windows 10 2004; on
            // anything older the window is at least painted black in captures,
            // which still hides the desktop.
            if SetWindowDisplayAffinity(hwnd, WDA_EXCLUDEFROMCAPTURE) == 0 {
                SetWindowDisplayAffinity(hwnd, WDA_MONITOR);
            }

            if SHOWN.load(Ordering::SeqCst) {
                ShowWindow(hwnd, SW_SHOWNOACTIVATE);
            }
            created += 1;
        }

        created
    }

    unsafe fn destroy_overlays() {
        for hwnd in find_overlays() {
            DestroyWindow(hwnd);
        }
    }

    unsafe fn find_overlays() -> Vec<HWND> {
        let class = wide(WINDOW_CLASS);
        let title = wide(WINDOW_TITLE);
        let mut found = Vec::new();
        let mut after: HWND = null_mut();
        loop {
            let hwnd = FindWindowExW(null_mut(), after, class.as_ptr(), title.as_ptr());
            if hwnd.is_null() {
                break;
            }
            found.push(hwnd);
            after = hwnd;
        }
        found
    }

    unsafe extern "system" fn collect_monitor(
        monitor: HMONITOR,
        _hdc: HDC,
        _rect: *mut RECT,
        lparam: LPARAM,
    ) -> BOOL {
        let rects = &mut *(lparam as *mut Vec<RECT>);
        let mut info: MONITORINFO = std::mem::zeroed();
        info.cbSize = std::mem::size_of::<MONITORINFO>() as DWORD;
        // rcMonitor, not rcWork: the overlay has to cover the taskbar too.
        if GetMonitorInfoW(monitor, &mut info) != 0 {
            rects.push(info.rcMonitor);
        }
        TRUE
    }

    unsafe extern "system" fn wnd_proc(
        hwnd: HWND,
        msg: UINT,
        wparam: WPARAM,
        lparam: LPARAM,
    ) -> LRESULT {
        match msg {
            WM_SHOW_WINDOWS => {
                SHOWN.store(true, Ordering::SeqCst);
                ShowWindow(hwnd, SW_SHOWNOACTIVATE);
                // Re-assert the topmost band: another topmost window may have
                // been raised above us while the overlay was hidden.
                SetWindowPos(
                    hwnd,
                    HWND_TOPMOST,
                    0,
                    0,
                    0,
                    0,
                    SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE,
                );
                0
            }
            WM_HIDE_WINDOWS => {
                SHOWN.store(false, Ordering::SeqCst);
                ShowWindow(hwnd, SW_HIDE);
                0
            }
            WM_DISPLAYCHANGE => {
                REBUILD.store(true, Ordering::SeqCst);
                0
            }
            // Never quit here. These windows are destroyed and recreated on a
            // display change, and this process is stopped by the application
            // that spawned it, not by its own windows going away.
            WM_DESTROY => 0,
            _ => DefWindowProcW(hwnd, msg, wparam, lparam),
        }
    }
}
