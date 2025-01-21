use anyhow::anyhow;
use chrono::{prelude::*, Days};
use rss;
use serde::{Deserialize, Serialize};
use tauri_plugin_http::reqwest;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Article {
    pub title: String,
    pub link: String,
    pub summary: String,
    pub date: DateTime<Utc>,
    pub guid: String,
    pub new: bool,
}

#[tauri::command]
pub async fn get_news() -> Result<Vec<Article>, tauri::Error> {
    let new_qualifier = Utc::now().checked_sub_days(Days::new(14)).unwrap();

    let content = reqwest::get("https://blog.mrquantumoff.dev/rss/")
        .await
        .map_err(|e| anyhow!(e))?
        .bytes()
        .await
        .map_err(|e| anyhow!(e))?;
    let rss = rss::Channel::read_from(&content[..]).map_err(|e| anyhow!(e))?;
    let mut articles: Vec<Article> = Vec::new();
    for item in rss.items {
        let title = item.title.unwrap_or_default();
        let link = item.link.unwrap_or_default();
        let summary = item.description.unwrap_or_default();
        let date = item.pub_date.unwrap_or_default();
        let date = DateTime::parse_from_rfc2822(&date)
            .map_err(|e| anyhow!(e))?
            .to_utc();
        let guid = item.guid.unwrap_or_default().value;
        articles.push(Article {
            title,
            link,
            summary,
            new: date > new_qualifier,
            date,
            guid,
        });
    }
    Ok(articles)
}
