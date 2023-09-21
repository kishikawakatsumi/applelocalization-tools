import * as path from "https://deno.land/std/path/mod.ts";

String.prototype.escape = function () {
  return this.replace(/\\/g, "\\\\").replace(/'/g, "\\'").replace(/\n/g, "\\n");
};

const file = "./data.sql";

await writeln(
  "CREATE EXTENSION IF NOT EXISTS pgroonga;",
);

const tables = ["macos12", "macos13", "ios15", "ios16"];

for (const table of tables) {
  await writeln(
    `CREATE SEQUENCE ${table}_id_seq AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;`,
  );
  await writeln(
    `CREATE TABLE ${table} ( id integer DEFAULT nextval('${table}_id_seq') PRIMARY KEY NOT NULL, group_id integer NOT NULL, source text NOT NULL, target text NOT NULL, language text NOT NULL, file_name text NOT NULL, bundle_name text NOT NULL, bundle_path text NOT NULL, platform text NOT NULL );`,
  );
  await writeln(
    `CREATE INDEX ${table}_bundle_name_index ON ${table} USING btree (bundle_name);`,
  );
  await writeln(
    `CREATE INDEX ${table}_bundle_path_index ON ${table} USING btree (bundle_path);`,
  );
  await writeln(
    `CREATE INDEX ${table}_file_name_index ON ${table} USING btree (file_name);`,
  );
  await writeln(
    `CREATE INDEX ${table}_group_id_index ON ${table} USING btree (group_id);`,
  );
  await writeln(
    `CREATE INDEX ${table}_group_id_language_index ON ${table} USING btree (group_id, language);`,
  );
  await writeln(
    `CREATE INDEX ${table}_language_group_id_index ON ${table} USING btree (language, group_id);`,
  );
  await writeln(
    `CREATE INDEX ${table}_language_index ON ${table} USING btree (language);`,
  );
  await writeln(
    `CREATE INDEX ${table}_platform_index ON ${table} USING btree (platform);`,
  );
  await writeln(
    `CREATE INDEX ${table}_source_index ON ${table} USING pgroonga (source);`,
  );
  await writeln(
    `CREATE INDEX ${table}_target_index ON ${table} USING pgroonga (target);`,
  );
}

for (const table of tables) {
  let counter = 0;
  let groupId = 1;
  const groupIds: { [key: string]: number } = {};
  const rootDir = {
    macos12: "data/macos/12.6",
    macos13: "data/macos/13.5.2",
    ios15: "data/ios/15.7",
    ios16: "data/ios/16.6",
  }[table];
  const platform = {
    macos12: "macOS",
    macos13: "macOS",
    ios15: "iOS",
    ios16: "iOS",
  }[table];

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

        await writeQuery(
          table,
          gid,
          key,
          localization.target,
          localization.language,
          localization.filename,
          localizable.framework,
          localizable.bundlePath,
          platform,
        );

        counter++;
      }
    }
  }

  console.log(counter);
}

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

async function writeQuery(
  table: string,
  gid: number,
  key: string,
  target: string,
  language: string,
  filename: string,
  bundleName: string,
  bundlePath: string,
  platform: string,
) {
  await writeln(
    `INSERT INTO ${table} (group_id, source, target, language, file_name, bundle_name, bundle_path, platform) VALUES(${gid}, E'${key.escape()}', E'${target.escape()}', E'${language.escape()}', E'${filename.escape()}', E'${bundleName.escape()}', E'${bundlePath.escape()}', E'${platform.escape()}');`,
  );
}

async function writeln(line: string) {
  await Deno.writeTextFile(file, line + "\n", { append: true });
}
