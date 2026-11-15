// Runs check_import_strings.py with the first Python found (py launcher on Windows, else python3/python).
const { spawnSync } = require("child_process");
const path = require("path");

const script = path.join(__dirname, "check_import_strings.py");
for (const cmd of ["py", "python3", "python"]) {
  const r = spawnSync(cmd, [script], { stdio: "inherit" });
  if (!r.error && r.status !== 9009) process.exit(r.status); // 9009: Windows "command not found"
}
console.error("Python not found: install it to check the import window's translations.");
process.exit(1);
