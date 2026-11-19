use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;
use url::Url;

const CORE_VERSION: &str = "0.1.0";

fn read_string(value: *const c_char) -> Option<String> {
    if value.is_null() { return None; }
    unsafe { CStr::from_ptr(value).to_str().ok().map(str::to_owned) }
}

fn into_c_string(value: String) -> *mut c_char {
    CString::new(value.replace('\0', "")).map(CString::into_raw).unwrap_or(ptr::null_mut())
}

fn media_path(value: &str) -> String {
    Url::parse(value)
        .map(|url| url.path().to_ascii_lowercase())
        .unwrap_or_else(|_| value.split('?').next().unwrap_or(value).to_ascii_lowercase())
}

#[no_mangle]
pub extern "C" fn flixora_core_version() -> *mut c_char {
    into_c_string(CORE_VERSION.to_owned())
}

/// IDs: 0 unknown, 1 HLS, 2 DASH, 3 MP4, 4 MKV, 5 WebM,
/// 6 MOV, 7 AVI, 8 M4V, 9 MPEG-TS.
#[no_mangle]
pub extern "C" fn flixora_detect_stream_kind(raw: *const c_char) -> i32 {
    let Some(value) = read_string(raw) else { return 0; };
    let path = media_path(&value);
    if path.ends_with(".m3u8") { return 1; }
    if path.ends_with(".mpd") { return 2; }
    if path.ends_with(".mp4") { return 3; }
    if path.ends_with(".mkv") { return 4; }
    if path.ends_with(".webm") { return 5; }
    if path.ends_with(".mov") { return 6; }
    if path.ends_with(".avi") { return 7; }
    if path.ends_with(".m4v") { return 8; }
    if path.ends_with(".ts") { return 9; }
    0
}

#[no_mangle]
pub extern "C" fn flixora_quality_rank(raw: *const c_char) -> i32 {
    let Some(value) = read_string(raw) else { return 0; };
    let normalized = value.trim().to_ascii_lowercase();
    match normalized.as_str() {
        "4k" | "uhd" | "2160" | "2160p" => return 2160,
        "2k" | "qhd" | "1440" | "1440p" => return 1440,
        "1080" | "1080p" | "fhd" => return 1080,
        "720" | "720p" | "hd" => return 720,
        "480" | "480p" | "sd" => return 480,
        "360" | "360p" => return 360,
        "240" | "240p" => return 240,
        _ => {}
    }
    let digits: String = normalized.chars().take_while(|c| c.is_ascii_digit()).collect();
    digits.parse::<i32>().unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn flixora_validate_http_url(raw: *const c_char) -> i32 {
    let Some(value) = read_string(raw) else { return 0; };
    match Url::parse(value.trim()) {
        Ok(url) => {
            let scheme_ok = url.scheme() == "http" || url.scheme() == "https";
            let host_ok = url.host_str().map(|host| !host.is_empty()).unwrap_or(false);
            let credentials_ok = url.username().is_empty() && url.password().is_none();
            if scheme_ok && host_ok && credentials_ok { 1 } else { 0 }
        }
        Err(_) => 0,
    }
}

#[no_mangle]
pub extern "C" fn flixora_playback_error(code: i32) -> *mut c_char {
    let message = match code {
        1 => "Unsupported media format",
        2 => "The video source is unavailable",
        3 => "The connection timed out",
        4 => "The stream was interrupted",
        5 => "The video could not be decoded",
        6 => "The server rejected the request",
        7 => "The selected subtitle could not be loaded",
        _ => "Playback failed. Please try another source",
    };
    into_c_string(message.to_owned())
}

#[no_mangle]
pub extern "C" fn flixora_free_string(value: *mut c_char) {
    if !value.is_null() {
        unsafe { drop(CString::from_raw(value)); }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_common_stream_formats() {
        let hls = CString::new("https://cdn.example/video/master.m3u8?token=x").unwrap();
        let mp4 = CString::new("https://cdn.example/video/movie.mp4").unwrap();
        assert_eq!(flixora_detect_stream_kind(hls.as_ptr()), 1);
        assert_eq!(flixora_detect_stream_kind(mp4.as_ptr()), 3);
    }

    #[test]
    fn ranks_quality_labels() {
        let quality = CString::new("1080p").unwrap();
        assert_eq!(flixora_quality_rank(quality.as_ptr()), 1080);
    }

    #[test]
    fn rejects_credentials_in_media_urls() {
        let url = CString::new("https://user:pass@example.com/movie.mp4").unwrap();
        assert_eq!(flixora_validate_http_url(url.as_ptr()), 0);
    }
}
