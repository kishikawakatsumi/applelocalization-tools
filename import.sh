#!/bin/sh
set -ex

deno run --allow-env --allow-net --allow-read --allow-write import.ts
