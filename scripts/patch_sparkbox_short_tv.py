from pathlib import Path
import sys

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/tmp/SparkBoxCore")


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    source = path.read_text()
    if new in source:
        return
    if old not in source:
        raise SystemExit(f"{label}: expected upstream source anchor was not found")
    path.write_text(source.replace(old, new, 1))


client_path = ROOT / "sparkbox-core/src/client.rs"
mobile_path = ROOT / "sparkbox-core/src/mobile.rs"
h5_path = ROOT / "sparkbox-core/src/h5.rs"
parse_path = ROOT / "sparkbox-core/src/parse.rs"
ffi_path = ROOT / "sparkbox-ffi/src/lib.rs"

replace_once(
    client_path,
    "    // ---------------------------------------------------------------- search",
    """    // -------------------------------------------------------------- shorts

    /// Paginated Short TV catalogue from the dedicated WeFeed endpoint.
    pub async fn shorts_catalog(&self, max_pages: i64, per_page: i64) -> Result<SearchResult> {
        self.shorts_catalog_impl(max_pages, per_page).await
    }

    // ---------------------------------------------------------------- search""",
    "Short TV client method",
)

replace_once(
    mobile_path,
    "use crate::models::{HomeSection, SearchItem, Season};",
    "use crate::models::{HomeSection, MediaItem, SearchItem, SearchResult, Season};",
    "Short TV model imports",
)

helper = """fn parse_short_subject(raw: &Map<String, Value>, block_adult: bool) -> Option<MediaItem> {
    let mut subject = raw.clone();
    if !subject.contains_key("stills") {
        if let Some(pre_video_cover) = subject.get("preVideoCover").cloned() {
            subject.insert("stills".into(), pre_video_cover);
        }
    }
    let mut item = parse_subject(&subject, "", block_adult)?;
    item.is_series = item.is_series
        || item.subject_type == 3
        || item.subject_type == 7
        || raw.get("isSeries").and_then(Value::as_bool).unwrap_or(false);
    Some(item)
}

"""
replace_once(mobile_path, "impl MovieBoxClient {\n", helper + "impl MovieBoxClient {\n", "Short TV subject parser")

shorts_method = """    /// Dedicated Short TV catalogue. Fetches multiple pages in one signed session.
    pub(crate) async fn shorts_catalog_impl(
        &self,
        max_pages: i64,
        per_page: i64,
    ) -> Result<SearchResult> {
        let base = self.config.mobile_base.trim_end_matches('/');
        let host = base
            .trim_start_matches("https://")
            .trim_start_matches("http://")
            .trim_end_matches('/');
        let token = self.guest_token().await?;

        let filter_url = format!(
            "{base}/wefeed-fm-bff/shorts/subject/filter-items?host={host}&tabId=7&filterItemVer=v3"
        );
        let mut filter_headers =
            self.mobile_headers("GET", &filter_url, None, false, token.as_deref());
        ins(&mut filter_headers, "x-play-mode", "2".into());
        let filter_response = self.http.get(&filter_url).headers(filter_headers).send().await?;
        if !filter_response.status().is_success() {
            return Err(CoreError::Api(format!(
                "Short TV filter request failed ({})",
                filter_response.status()
            )));
        }
        let filter_text = filter_response.text().await?;
        let filter_root = try_json(&filter_text)
            .ok_or_else(|| CoreError::Api("Short TV filters returned invalid JSON".into()))?;
        let filter_data = filter_root
            .get("data")
            .and_then(Value::as_object)
            .ok_or_else(|| CoreError::Api("Short TV filters are unavailable".into()))?;
        let channel = get_arr(filter_data.get("typeList"))
            .into_iter()
            .next()
            .ok_or_else(|| CoreError::Api("Short TV has no available channel".into()))?;
        let channel_id = s(channel, "channelId");
        if channel_id.is_empty() {
            return Err(CoreError::Api("Short TV channel id is missing".into()));
        }

        let mut default_filters = Map::new();
        for filter in get_arr(channel.get("items")) {
            let filter_type = s(filter, "filterType");
            if filter_type.is_empty() {
                continue;
            }
            if let Some(range) = filter.get("rangeVals").and_then(Value::as_object) {
                let min = as_i64(range.get("minVal")).unwrap_or(0);
                let max = as_i64(range.get("maxVal")).unwrap_or(0);
                default_filters.insert(
                    filter_type,
                    Value::Array(vec![
                        Value::String(min.to_string()),
                        Value::String(max.to_string()),
                    ]),
                );
            } else if let Some(first) =
                get_arr(filter.get("filterValsV2")).into_iter().next()
            {
                if let Some(id) = first.get("id") {
                    default_filters.insert(filter_type, id.clone());
                }
            }
        }

        let safe_per_page = per_page.clamp(1, 50);
        let safe_max_pages = max_pages.clamp(1, 12);
        let list_url = format!("{base}/wefeed-fm-bff/shorts/subject/list?host={host}");
        let block_adult = self.block_adult();
        let mut all_items = Vec::new();
        let mut has_more = false;

        for page in 1..=safe_max_pages {
            let mut payload = Map::new();
            payload.insert("page".into(), Value::from(page));
            payload.insert("perPage".into(), Value::from(safe_per_page));
            payload.insert("channelId".into(), Value::String(channel_id.clone()));
            for (key, value) in &default_filters {
                payload.insert(key.clone(), value.clone());
            }
            let body = Value::Object(payload).to_string();
            let mut headers =
                self.mobile_headers("POST", &list_url, Some(&body), false, token.as_deref());
            ins(&mut headers, "x-play-mode", "2".into());
            let response = self
                .http
                .post(&list_url)
                .headers(headers)
                .body(body)
                .send()
                .await?;
            if !response.status().is_success() {
                return Err(CoreError::Api(format!(
                    "Short TV page {page} failed ({})",
                    response.status()
                )));
            }
            let text = response.text().await?;
            let root = try_json(&text)
                .ok_or_else(|| CoreError::Api("Short TV page returned invalid JSON".into()))?;
            let data = root
                .get("data")
                .and_then(Value::as_object)
                .ok_or_else(|| CoreError::Api("Short TV catalogue is unavailable".into()))?;
            let raw_items = get_arr(data.get("items"));
            let item_count = raw_items.len();
            for raw in raw_items {
                if let Some(item) = parse_short_subject(raw, block_adult) {
                    all_items.push(item);
                }
            }
            has_more = data
                .get("pager")
                .and_then(Value::as_object)
                .and_then(|pager| pager.get("hasMore"))
                .and_then(Value::as_bool)
                .unwrap_or(item_count as i64 >= safe_per_page);
            if item_count == 0 || !has_more {
                break;
            }
        }

        Ok(SearchResult {
            items: all_items,
            has_more,
        })
    }

"""
replace_once(
    mobile_path,
    "    /// Mobile detail call: gives detailPath/detailUrl and the guest token used\n",
    shorts_method + "    /// Mobile detail call: gives detailPath/detailUrl and the guest token used\n",
    "Short TV paginated endpoint",
)

replace_once(
    mobile_path,
    """        let url = format!(
            "{}/wefeed-mobile-bff/subject-api/season-info?subjectId={}",
            self.config.mobile_base, subject_id
        );""",
    """        let base = self.config.mobile_base.trim_end_matches('/');
                let host = base
                    .trim_start_matches("https://")
                    .trim_start_matches("http://")
                    .trim_end_matches('/');
                let url = format!(
                    "{base}/wefeed-mobile-bff/subject-api/season-info?host={host}&subjectId={subject_id}"
                );""",
    "Short TV season URL",
)

replace_once(
    mobile_path,
    """        let text = self
            .http
            .get(&url)
            .headers(self.mobile_headers("GET", &url, None, false, token.as_deref()))
            .send()
            .await?
            .text()
            .await?;""",
    """        let mut headers =
                    self.mobile_headers("GET", &url, None, false, token.as_deref());
                ins(&mut headers, "x-play-mode", "2".into());
                let text = self
                    .http
                    .get(&url)
                    .headers(headers)
                    .send()
                    .await?
                    .text()
                    .await?;""",
    "Short TV season headers",
)

replace_once(
    mobile_path,
    """    pub(crate) async fn detail_mobile(
        &self,
        id: &str,
        path_hint: &str,
    ) -> Result<crate::models::Detail> {""",
    """    pub(crate) async fn detail_mobile(
                &self,
                id: &str,
                path_hint: &str,
                subject_type: i64,
            ) -> Result<crate::models::Detail> {""",
    "Short TV detail signature",
)

replace_once(
    mobile_path,
    """        let url = format!(
            "{}/wefeed-mobile-bff/subject-api/get?subjectId={}",
            self.config.mobile_base, id
        );""",
    """        let base = self.config.mobile_base.trim_end_matches('/');
                let host = base
                    .trim_start_matches("https://")
                    .trim_start_matches("http://")
                    .trim_end_matches('/');
                let url = format!(
                    "{base}/wefeed-mobile-bff/subject-api/get?host={host}&subjectId={id}&subjectType={subject_type}"
                );""",
    "Short TV detail URL",
)

replace_once(
    client_path,
    'self.detail_mobile(item.id.as_str(), "").await',
    'self.detail_mobile(item.id.as_str(), "", item.subject_type).await',
    "Short TV client detail call",
)
replace_once(
    h5_path,
    'self.detail_mobile(&item.id, "").await',
    'self.detail_mobile(&item.id, "", item.subject_type).await',
    "Short TV H5 detail call",
)

old_parse_season = """pub fn parse_season(o: &Map<String, Value>) -> Option<Season> {
    let se = as_i64(o.get("se"))?;
    if se < 0 {
        return None;
    }
    let mut listed: Vec<i64> = s(o, "allEp")
        .split([',', ';', ' '])
        .filter_map(|t| t.trim().parse::<i64>().ok())
        .collect();
    listed.sort_unstable();
    listed.dedup();
    let max_ep = as_i64(o.get("maxEp")).unwrap_or(0);
    let episodes = if !listed.is_empty() {
        listed
    } else {
        (1..=max_ep.max(0)).collect()
    };
    if episodes.is_empty() {
        return None;
    }
    let max = *episodes.iter().max().unwrap();
    Some(Season {
        se,
        max_ep: max,
        episodes,
    })
}"""
new_parse_season = """pub fn parse_season(o: &Map<String, Value>) -> Option<Season> {
    let se = as_i64(o.get("se"))
        .or_else(|| as_i64(o.get("season")))
        .or_else(|| as_i64(o.get("seasonNumber")))?;
    if se < 0 {
        return None;
    }
    let mut listed: Vec<i64> = s(o, "allEp")
        .split([',', ';', ' '])
        .filter_map(|t| t.trim().parse::<i64>().ok())
        .collect();
    if listed.is_empty() {
        if let Some(raw_episodes) = o.get("episodes").and_then(Value::as_array) {
            for raw in raw_episodes {
                let episode = as_i64(Some(raw))
                    .or_else(|| as_i64(raw.get("ep")))
                    .or_else(|| as_i64(raw.get("episode")))
                    .or_else(|| as_i64(raw.get("episodeNumber")))
                    .or_else(|| as_i64(raw.get("number")));
                if let Some(number) = episode {
                    if number > 0 {
                        listed.push(number);
                    }
                }
            }
        }
    }
    listed.sort_unstable();
    listed.dedup();
    let max_ep = as_i64(o.get("maxEp"))
        .or_else(|| as_i64(o.get("totalEpisode")))
        .unwrap_or(0);
    let episodes = if !listed.is_empty() {
        listed
    } else {
        (1..=max_ep.max(0)).collect()
    };
    if episodes.is_empty() {
        return None;
    }
    let max = *episodes.iter().max().unwrap();
    Some(Season {
        se,
        max_ep: max,
        episodes,
    })
}"""
replace_once(parse_path, old_parse_season, new_parse_season, "Short TV season parser")

parse_test = """#[cfg(test)]
mod short_tv_season_tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn parses_short_tv_episode_object_lists() {
        let raw = json!({
            "seasonNumber": 2,
            "episodes": [
                { "ep": 3 },
                { "episodeNumber": 1 },
                2
            ]
        });
        let season = parse_season(raw.as_object().unwrap()).expect("season parses");
        assert_eq!(season.se, 2);
        assert_eq!(season.episodes, vec![1, 2, 3]);
    }
}

"""
parse_source = parse_path.read_text()
if "mod short_tv_season_tests" not in parse_source:
    parse_path.write_text(parse_source + "\n" + parse_test)

mobile = mobile_path.read_text()
mobile_test = """#[cfg(test)]
mod shorts_catalog_tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn short_tv_subject_type_three_is_episode_based_series() {
        let raw = json!({
            "subjectId": "short-series-1",
            "title": "Example Short Series",
            "subjectType": 3,
            "releaseDate": "2026-01-01",
            "cover": { "url": "https://cdn.example.test/poster.jpg" },
            "preVideoCover": { "url": "https://cdn.example.test/backdrop.jpg" }
        });
        let item = parse_short_subject(raw.as_object().unwrap(), false)
            .expect("short TV item parses");
        assert!(item.is_series);
        assert_eq!(item.subject_type, 3);
        assert_eq!(item.backdrop, "https://cdn.example.test/backdrop.jpg");
    }

    #[test]
    fn short_tv_subject_type_seven_is_episode_based_series() {
        let raw = json!({
            "subjectId": "short-series-7",
            "title": "Example Short Series 7",
            "subjectType": 7,
            "cover": { "url": "https://cdn.example.test/poster.jpg" }
        });
        let item = parse_short_subject(raw.as_object().unwrap(), false)
            .expect("short TV item parses");
        assert!(item.is_series);
        assert_eq!(item.subject_type, 7);
    }
}

"""
if "mod shorts_catalog_tests" not in mobile:
    mobile_path.write_text(mobile + "\n" + mobile_test)

ffi_function = """/// Dedicated Short TV catalogue returning items and a hasMore flag.
#[no_mangle]
pub extern "C" fn sparkbox_shorts(per_page: c_int, max_pages: c_int) -> *mut c_char {
    guard(|| match rt().block_on(client().shorts_catalog(max_pages as i64, per_page as i64)) {
        Ok(res) => ok(&res),
        Err(e) => err(&e),
    })
}

"""
replace_once(
    ffi_path,
    "/// Search suggestions",
    ffi_function + "/// Search suggestions",
    "Short TV FFI export",
)

print("SparkBoxCore Short TV pagination and episode support patched.")
