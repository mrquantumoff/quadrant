//! RSS/news fetching for the Quadrant blog.

use crate::{Result, models::Article};
use anyhow::anyhow;
use chrono::{DateTime, Days, Utc};

/// Fetches the Quadrant RSS feed and converts it into typed articles.
pub async fn get_news() -> Result<Vec<Article>> {
    log::info!("Fetching RSS news feed");
    let new_qualifier = Utc::now().checked_sub_days(Days::new(14)).unwrap();
    let content = reqwest::get("https://blog.mrquantumoff.dev/rss/")
        .await
        .map_err(|error| anyhow!(error))?
        .bytes()
        .await
        .map_err(|error| anyhow!(error))?;
    let rss = rss::Channel::read_from(&content[..]).map_err(|error| anyhow!(error))?;

    let mut articles = Vec::new();
    for item in rss.items {
        let Some(date) = item
            .pub_date
            .as_deref()
            .and_then(|date| DateTime::parse_from_rfc2822(date).ok())
            .map(|date| date.to_utc())
        else {
            log::warn!("Skipping RSS item with an invalid or missing publication date");
            continue;
        };
        let link = item.link.unwrap_or_default();
        let guid = item
            .guid
            .map(|guid| guid.value)
            .unwrap_or_else(|| link.clone());
        articles.push(Article {
            title: item.title.unwrap_or_default(),
            link,
            summary: item.description.unwrap_or_default(),
            new: date > new_qualifier,
            date,
            guid,
        });
    }
    log::info!("Fetched {} article(s) from RSS feed", articles.len());
    Ok(articles)
}
