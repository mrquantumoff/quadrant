use http_cache_reqwest::{Cache, CacheMode, HttpCache, HttpCacheOptions, MokaManager};
use moka::future::Cache as MokaCache;
use once_cell::sync::Lazy;
use reqwest_middleware::{ClientBuilder, ClientWithMiddleware};

use super::get_user_agent;

static PROVIDER_HTTP_CLIENT: Lazy<reqwest::Client> = Lazy::new(|| {
    reqwest::Client::builder()
        .user_agent(get_user_agent())
        .build()
        .expect("failed to build shared provider HTTP client")
});

static PROVIDER_HTTP_CACHE_MANAGER: Lazy<MokaManager> =
    Lazy::new(|| MokaManager::new(MokaCache::new(512)));

static PROVIDER_CACHED_CLIENT: Lazy<ClientWithMiddleware> = Lazy::new(|| {
    ClientBuilder::new(provider_http_client().clone())
        .with(Cache(HttpCache {
            mode: CacheMode::Default,
            manager: PROVIDER_HTTP_CACHE_MANAGER.clone(),
            options: HttpCacheOptions::default(),
        }))
        .build()
});

pub(crate) fn provider_http_client() -> &'static reqwest::Client {
    &PROVIDER_HTTP_CLIENT
}

pub(crate) fn provider_cached_client() -> &'static ClientWithMiddleware {
    &PROVIDER_CACHED_CLIENT
}

#[cfg(test)]
pub(crate) static PROVIDER_HTTP_TEST_MUTEX: Lazy<tokio::sync::Mutex<()>> =
    Lazy::new(|| tokio::sync::Mutex::new(()));

#[cfg(test)]
pub(crate) async fn clear_provider_http_cache() {
    PROVIDER_HTTP_CACHE_MANAGER
        .clear()
        .await
        .expect("failed to clear provider HTTP cache");
}
