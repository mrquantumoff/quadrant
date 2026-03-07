pub use quadrant_core::models::Article;

#[tauri::command]
pub async fn get_news() -> Result<Vec<Article>, tauri::Error> {
    quadrant_core::rss::get_news()
        .await
        .map_err(tauri::Error::from)
}
