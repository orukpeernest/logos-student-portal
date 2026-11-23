const fs = require("node:fs");
const assert = require("node:assert/strict");

const config = fs.readFileSync("supabase-config.js", "utf8");
const studentJs = fs.readFileSync("portal.js", "utf8");
const adminJs = fs.readFileSync("admin-portal.js", "utf8");
const studentHtml = fs.readFileSync("student-portal.html", "utf8");
const adminHtml = fs.readFileSync("admin-portal.html", "utf8");

const stagingUrl = "https://rxuusshnsrpegwwktvii.supabase.co";
const productionRef = "olfvvqokqjkxizmrwlhb";

assert.ok(config.includes(stagingUrl), "public config must target the staging project");
assert.match(config, /sb_publishable_[A-Za-z0-9_-]+/, "config must use a publishable key");
assert.doesNotMatch(config, /service_role|sb_secret_/i, "privileged keys must never be in browser config");

for (const [name, source] of [["student portal", studentJs], ["admin portal", adminJs]]) {
  assert.ok(source.includes("window.LOGOS_SUPABASE_CONFIG"), name + " must consume shared config");
  assert.ok(!source.includes(productionRef), name + " must not reference production");
}
assert.ok(adminJs.includes("valid staging configuration is required"), "admin portal must fail closed on invalid config");
assert.ok(studentJs.includes('SUPABASE_URL === STAGING_SUPABASE_URL'), "student portal must validate the exact staging URL");

for (const [name, html, appScript] of [
  ["student", studentHtml, "portal.js"],
  ["admin", adminHtml, "admin-portal.js"]
]) {
  const cdn = html.indexOf("supabase-js");
  const configTag = html.indexOf("supabase-config.js");
  const app = html.indexOf(appScript);
  assert.ok(cdn >= 0 && configTag > cdn && app > configTag, name + " page must load config after Supabase and before app script");
  assert.ok(!html.includes(productionRef), name + " page must not reference production");
}
console.log("Staging configuration isolation checks passed.");
