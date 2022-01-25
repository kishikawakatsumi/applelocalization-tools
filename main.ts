import { path, Pool } from "./deps.ts";

const POOL_CONNECTIONS = 4;
const dbPool = new Pool({
  hostname: "127.0.0.1",
  port: 5432,
  user: Deno.env.get("POSTGRES_USER"),
  password: Deno.env.get("POSTGRES_PASSWORD"),
  database: Deno.env.get("POSTGRES_DB"),
}, POOL_CONNECTIONS);

const client = await dbPool.connect();

let counter = 0;
let groupId = 1;
const groupIds: { [key: string]: number } = {};
const rootDir = "data";
for await (const directory of Deno.readDir(rootDir)) {
  const localizable: Localizable = JSON.parse(
    await Deno.readTextFile(path.join(rootDir, directory.name)),
  );
  for (const key of Object.keys(localizable.localizations)) {
    const localizations: [Localization] = localizable.localizations[key];
    for (const localization of localizations) {
      if (!key) {
        continue;
      }
      if (!localization.target) {
        continue;
      }

      const k = `${localizable.bundlePath}:${key}`;
      let gid = groupIds[k];
      if (!gid) {
        gid = groupId;
        groupIds[k] = gid;
        groupId++;
      }

      await client.queryArray(
        `INSERT INTO localizations (group_id, source, target, language, file_name, bundle_name, bundle_path, platform) VALUES($1, $2, $3, $4, $5, $6, $7, $8);`,
        [
          gid,
          key,
          localization.target,
          localization.language,
          localization.filename,
          localizable.framework,
          localizable.bundlePath,
          "iOS",
        ],
      );

      counter++;
    }
  }
}

console.log(counter);
client.release();

interface Localizable {
  localizations: { [key: string]: [Localization] };
  bundlePath: string;
  framework: string;
}

interface Localization {
  language: string;
  target: string;
  filename: string;
}
