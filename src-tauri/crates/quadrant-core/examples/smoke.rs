use quadrant_core::{
    Result,
    config::ensure_default_app_config,
    events::BackendEvent,
    modpacks,
    ports::{EventSink, SettingsStore},
};
use serde_json::Value;
use std::{cell::RefCell, collections::HashMap, env, path::PathBuf};

#[derive(Default)]
struct MemoryStore {
    values: RefCell<HashMap<String, Value>>,
}

impl SettingsStore for MemoryStore {
    fn get_value(&self, key: &str) -> Result<Option<Value>> {
        Ok(self.values.borrow().get(key).cloned())
    }

    fn set_value(&self, key: &str, value: Value) -> Result<()> {
        self.values.borrow_mut().insert(key.to_string(), value);
        Ok(())
    }
}

struct LoggingEvents;

impl EventSink for LoggingEvents {
    fn publish(&self, event: BackendEvent) -> Result<()> {
        println!("{event:?}");
        Ok(())
    }
}

fn main() -> Result<()> {
    let args: Vec<_> = env::args().collect();
    if args.len() < 3 {
        eprintln!(
            "usage: cargo run -p quadrant-core --example smoke -- <mc-folder> <list|apply|export> [modpack]"
        );
        std::process::exit(1);
    }

    let mc_folder = PathBuf::from(&args[1]);
    let command = &args[2];
    let store = MemoryStore::default();
    ensure_default_app_config(&store)?;
    let events = LoggingEvents;

    match command.as_str() {
        "list" => {
            for modpack in modpacks::get_modpacks(&mc_folder, false)? {
                println!(
                    "{} {} {}",
                    modpack.name, modpack.version, modpack.mod_loader
                );
            }
        }
        "apply" => {
            let name = args.get(3).expect("modpack name required for apply");
            modpacks::apply_modpack(&mc_folder, name)?;
            println!("applied {name}");
        }
        "export" => {
            let name = args.get(3).expect("modpack name required for export");
            let target = mc_folder.join(format!("{name}.quadrantExport.zip"));
            modpacks::export_modpack_to(&mc_folder, name, &target, &events)?;
            println!("{}", target.display());
        }
        other => {
            eprintln!("unsupported command: {other}");
            std::process::exit(1);
        }
    }

    Ok(())
}
