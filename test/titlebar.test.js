const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

test("native floating window hides the macOS title text", () => {
  const source = fs.readFileSync(
    path.join(__dirname, "..", "FloatingWindow", "main.swift"),
    "utf8",
  );

  assert.match(source, /panel\.titleVisibility\s*=\s*\.hidden/);
});
