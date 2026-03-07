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
        let date = DateTime::parse_from_rfc2822(&item.pub_date.unwrap_or_default())
            .map_err(|error| anyhow!(error))?
            .to_utc();
        articles.push(Article {
            title: item.title.unwrap_or_default(),
            link: item.link.unwrap_or_default(),
            summary: item.description.unwrap_or_default(),
            new: date > new_qualifier,
            date,
            guid: item.guid.unwrap_or_default().value,
        });
    }
    log::info!("Fetched {} article(s) from RSS feed", articles.len());
    Ok(articles)
}
