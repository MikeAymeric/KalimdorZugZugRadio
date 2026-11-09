const path = require("path"), fs = require("fs");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");
const dir = path.join(__dirname, "..", "KalimdorZugZugRadio");
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
lua.lua_newtable(L);
for (const f of ["Locales", "Core", "Player", "Rules", "UI", "LibraryUI", "Settings", "Minimap"]) {
  lua.lua_pushstring(L, to_luastring(fs.readFileSync(path.join(dir, f + ".lua"), "utf8")));
  lua.lua_setfield(L, -2, to_luastring(f));
}
lua.lua_setglobal(L, to_luastring("SRC"));
const code = fs.readFileSync(path.join(__dirname, "harness.lua"), "utf8");
if (lauxlib.luaL_dostring(L, to_luastring(code)) !== 0) {
  console.log("ERROR:", lua.lua_tojsstring(L, -1));
  process.exit(1);
}
