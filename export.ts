import * as path from "https://deno.land/std/path/mod.ts";

const file = "./data.sql";

await writeln(
  "CREATE EXTENSION IF NOT EXISTS pgroonga;",
);

const tables = [
  "macos12",
  "macos13",
  "macos14",
  "macos15",
  "macos26",
  "ios15",
  "ios16",
  "ios17",
  "ios18",
  "ios26",
];

for (const table of tables) {
  await writeln(
    `CREATE TABLE ${table} (id integer NOT NULL, group_id integer NOT NULL, source text NOT NULL, target text NOT NULL, language text NOT NULL, file_name text NOT NULL, bundle_name text NOT NULL, bundle_path text NOT NULL, platform text NOT NULL);`,
  );
}

for (const table of tables) {
  let counter = 1;
  let groupId = 1;
  const groupIds: { [key: string]: number } = {};
  const rootDir = {
    macos12: "data/macos/12.6",
    macos13: "data/macos/13.5.2",
    macos14: "data/macos/14.6",
    macos15: "data/macos/15.2",
    macos26: "data/macos/26.1",
    ios15: "data/ios/15.7",
    ios16: "data/ios/16.6",
    ios17: "data/ios/17.7",
    ios18: "data/ios/18.3",
    ios26: "data/ios/26.1",
  }[table];
  const platform = {
    macos12: "macOS",
    macos13: "macOS",
    macos14: "macOS",
    macos15: "macOS",
    macos26: "macOS",
    ios15: "iOS",
    ios16: "iOS",
    ios17: "iOS",
    ios18: "iOS",
    ios26: "iOS",
  }[table];

  await writeln(
    `COPY ${table} (id, group_id, source, target, language, file_name, bundle_name, bundle_path, platform) FROM stdin;`,
  );

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

        const source = escape(key);
        const target = escape(localization.target);

        await writeln(
          `${counter}\t${gid}\t${source}\t${target}\t${localization.language}\t${localization.filename}\t${localizable.framework}\t${localizable.bundlePath}\t${platform}`,
        );

        counter++;
      }
    }
  }

  console.log(counter - 1);

  await writeln("\\.");
}

for (const table of tables) {
  await writeln(
    `ALTER TABLE ${table} ADD PRIMARY KEY (id);`,
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

async function writeln(line: string) {
  await Deno.writeTextFile(file, line + "\n", { append: true });
}

function escape(str: string) {
  return str
    .replace(/\\/g, "\\\\")
    .replace(/\t/g, " ")
    .replace(/\r/g, "\\r")
    .replace(/\n/g, "\\n")
    .replace(/\0/g, "\\0");
}
