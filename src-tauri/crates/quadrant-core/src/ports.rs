use crate::{Result, events::BackendEvent};
use serde_json::Value;
use std::path::{Path, PathBuf};

pub trait SettingsStore {
    fn get_value(&self, key: &str) -> Result<Option<Value>>;
    fn set_value(&self, key: &str, value: Value) -> Result<()>;
    fn entries(&self) -> Result<Vec<(String, Value)>>;

    fn get_bool(&self, key: &str) -> Result<Option<bool>> {
        Ok(self.get_value(key)?.and_then(|value| value.as_bool()))
    }

    fn get_i64(&self, key: &str) -> Result<Option<i64>> {
        Ok(self.get_value(key)?.and_then(|value| value.as_i64()))
    }

    fn get_string(&self, key: &str) -> Result<Option<String>> {
        Ok(self
            .get_value(key)?
            .and_then(|value| value.as_str().map(ToOwned::to_owned)))
    }

    fn set_bool(&self, key: &str, value: bool) -> Result<()> {
        self.set_value(key, Value::Bool(value))
    }

    fn set_i64(&self, key: &str, value: i64) -> Result<()> {
        self.set_value(key, Value::Number(value.into()))
    }

    fn set_string(&self, key: &str, value: impl Into<String>) -> Result<()> {
        self.set_value(key, Value::String(value.into()))
    }
}

pub trait SecretStore {
    fn get_secret(&self, key: &str) -> Result<Option<String>>;
    fn set_secret(&self, key: &str, value: &str) -> Result<()>;
    fn delete_secret(&self, key: &str) -> Result<()>;
}

pub trait EventSink {
    fn publish(&self, event: BackendEvent) -> Result<()>;
}

pub trait Shell {
    fn open_url(&self, url: &str) -> Result<()>;
    fn open_path(&self, path: &Path) -> Result<()>;
    fn choose_export_path(&self, suggested_name: &str) -> Result<Option<PathBuf>>;
}

pub trait Notifier {
    fn notify(&self, title: &str, body: &str) -> Result<()>;
}

pub trait RuntimeState {
    fn get_value(&self, key: &str) -> Result<Option<Value>>;
    fn set_value(&self, key: &str, value: Value) -> Result<()>;
}
