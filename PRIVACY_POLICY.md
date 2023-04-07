# Privacy Policy

- This app modifies your minecraft folder
- By default this app does not collect your data. You can optionally let the app to collect analytics and diagnostics from your PC by going to the settings and explicitly enabling analytics and diagnostics. Meanwhile my [website](https://mrquantumoff.dev) is closed-source I can 100% guarantee that your data will not be sold to third parties. In the near future I will implement an API to view general analytics (they will not feature "date" and "hardwareId" fields) and diagnostics and your own analytics.
- Why does the app need "hardwareId" and "date" fields? In order to not duplicate the same machine 100 times across the database and in order to remove super old data in the future.

```typescript
interface IAppInfo {
  version: string;
  os: string;
  modrinthUsage: number;
  curseforgeUsage: number;
  referenceFileUsage: number;
  manualInputUsage: number;
  hardwareId: string;
  date: string;
  country: string;
}
```

This an example of which data is being collected.
