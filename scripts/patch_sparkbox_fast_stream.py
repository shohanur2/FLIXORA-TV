from pathlib import Path

root = Path('/tmp/SparkBoxCore')
h5 = root / 'sparkbox-core/src/h5.rs'
client = root / 'sparkbox-core/src/client.rs'
ffi = root / 'sparkbox-ffi/src/lib.rs'

source = h5.read_text()
anchor = '    /// Resolve playable streams for'
if 'pub(crate) async fn streams_fast_impl' not in source:
    fast = '''    /// Resolve only Original and inline captions for immediate playback.
    pub(crate) async fn streams_fast_impl(
        &self, d: &crate::models::Detail, se: i64, ep: i64, is_series: bool,
    ) -> Result<StreamsResult> {
        *self.last_note.lock().unwrap() = String::new();
        let mut subtitles: Vec<SubtitleLink> = Vec::new();
        let mut cap_keys: Vec<(String, String, i64, i64, String)> = Vec::new();
        let attempts: &[(i64, i64)] = if is_series { &[(se, ep)] } else { &[(0, 0), (1, 1)] };
        let mut links: Vec<StreamLink> = Vec::new();
        for (season, episode) in attempts {
            links = self.play_once(d, "Original", &d.id, &d.detail_path, *season, *episode,
                &mut subtitles, &mut cap_keys).await;
            if !links.is_empty() { break; }
        }
        if links.is_empty() {
            let mut msg = format!("No Original stream (se={se} ep={ep})");
            if d.detail_path.is_empty() { msg.push_str(&format!(" | no detailPath, {}", d.note)); }
            let note = self.last_note.lock().unwrap().clone();
            if !note.is_empty() { msg.push_str(&format!(" | {note}")); }
            return Err(CoreError::Api(msg));
        }
        links.sort_by(|a, b| b.quality.cmp(&a.quality));
        Ok(StreamsResult { links, subtitles })
    }

'''
    if anchor not in source: raise SystemExit('h5 streams anchor missing')
    source = source.replace(anchor, fast + anchor, 1); h5.write_text(source)

source = client.read_text()
anchor = '    pub async fn streams(\n'
if 'pub async fn streams_fast(' not in source:
    method = '''    /// Fast first-play path: Original links only; enrichment is deferred.
    pub async fn streams_fast(&self, d: &Detail, se: i64, ep: i64, is_series: bool) -> Result<StreamsResult> {
        self.streams_fast_impl(d, se, ep, is_series).await
    }

'''
    if anchor not in source: raise SystemExit('client streams anchor missing')
    source = source.replace(anchor, method + anchor, 1); client.write_text(source)

source = ffi.read_text()
anchor = '/// `subjectType` →'
if 'pub extern "C" fn sparkbox_streams_fast(' not in source:
    method = '''/// Fast first-play stream resolution: Original variant and inline captions only.
#[no_mangle]
pub extern "C" fn sparkbox_streams_fast(detail_json: *const c_char, se: c_int, ep: c_int, is_series: c_int) -> *mut c_char {
    guard(|| {
        let d: sparkbox_core::Detail = match arg_json(detail_json, "Detail") { Ok(v) => v, Err(e) => return err(&e) };
        match rt().block_on(client().streams_fast(&d, se as i64, ep as i64, is_series != 0)) {
            Ok(res) => ok(&res), Err(e) => err(&e),
        }
    })
}

'''
    if anchor not in source: raise SystemExit('ffi type label anchor missing')
    source = source.replace(anchor, method + anchor, 1); ffi.write_text(source)

print('Added fast Original-first stream endpoint; full streams endpoint remains unchanged.')
