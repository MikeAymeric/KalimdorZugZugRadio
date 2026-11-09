// Controllo sintassi Lua 5.1 di tutti i file dell'addon (non c'è un interprete Lua locale).
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
