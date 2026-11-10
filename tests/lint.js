// Lua 5.1 syntax check of every addon file (there is no local Lua interpreter).
const luaparse = require("luaparse"), fs = require("fs"), path = require("path");
let bad = 0;
for (const dir of ["KalimdorZugZugRadio", "RadioProbe"]) {
  const abs = path.join(__dirname, "..", dir);
  if (!fs.existsSync(abs)) continue;
  for (const f of fs.readdirSync(abs).filter((f) => f.endsWith(".lua"))) {
    try {
      luaparse.parse(fs.readFileSync(path.join(abs, f), "utf8"), { luaVersion: "5.1" });
      console.log("OK  ", `${dir}/${f}`);
    } catch (e) {
      bad = 1;
      console.log("ERR ", `${dir}/${f}`, e.message);
    }
  }
}
process.exit(bad);
