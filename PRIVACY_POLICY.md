# Privacy Policy

- This app modifies your minecraft folder
- By default this app does not collect your data. You can optionally let the app to collect analytics and diagnostics from your PC by going to the settings and explicitly enabling analytics and diagnostics. Meanwhile my [website (versions pre 7.16.0)](https://mrquantumoff.dev) and my [API](https://api.mrquantumoff.dev) are proprietary, I can 100% guarantee that your personal info (e.g your hardware id or when did your device sent the diagnostics/analytics report) will not be sold to third parties.
- Why does the app need "hardwareId" and "date" fields? In order to not duplicate the same machine 100 times across the database and in order to remove super old data in the future.

```rust
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AppInfo {
    version: String,
    os: String,
    modrinth_usage: i32,
    curseforge_usage: i32,
    reference_file_usage: i32,
    manual_input_usage: i32,
    hardware_id: String,
    date: String,
    country: String,
}
```

This an example of which data is being collected by the app and can be accessed with https://api.mrquantumoff.dev/api/v2/get/quadrantusageinfo?hardware_id=YOURHARDWAREID.

However, when someone is asking for general usage info (https://api.mrquantumoff.dev/api/v2/get/quadrantusageinfo) without any query params, they can only get this struct

```rust
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AppInfoAnonymous {
    version: String,
    os: String,
    modrinth_usage: i32,
    curseforge_usage: i32,
    reference_file_usage: i32,
    manual_input_usage: i32,
    country: String,
}
```

The Quadrant Share feature in Quadrant v12+ requires optional data collection enabled (hardware id), in order not to have the database spammed with hundreds of codes.
