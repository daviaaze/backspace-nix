'use strict';
const fs = require('node:fs');
const path = require('node:path');
const asar = require(process.env.ASAR_MODULE);

async function main() {
  const [first, second, third] = process.argv.slice(2);
  if (first === '--pack') {
    await asar.createPackageWithOptions(second, third, {
      unpackDir: '{node_modules/@vencord/venmic,node_modules/uiohook-napi}',
    });
    return;
  }
  const archive = first;
  const destination = second;
  // Upstream's Linux afterPack removes other platforms' uiohook binaries,
  // but leaves their unpacked entries in the ASAR index. Do not synthesize
  // those files; omit only these known, non-Linux entries when rebuilding.
  const removedForeignBinary = /^node_modules\/uiohook-napi\/prebuilds\/(darwin-(arm64|x64)|win32-(arm64|x64))\/uiohook-napi\.node$/;
  function extract(files, prefix = '') {
    for (const [name, entry] of Object.entries(files)) {
      const relative = prefix + name;
      const target = path.join(destination, relative);
      if (entry.files) {
        fs.mkdirSync(target, { recursive: true });
        extract(entry.files, relative + '/');
      } else if (entry.link) {
        fs.symlinkSync(path.relative(path.dirname(target), path.join(destination, entry.link)), target);
      } else {
        if (entry.unpacked && !fs.existsSync(archive + '.unpacked/' + relative)) {
          if (removedForeignBinary.test(relative)) continue;
          throw new Error('Missing upstream unpacked file: ' + relative);
        }
        fs.writeFileSync(target, asar.extractFile(archive, relative), { mode: entry.executable ? 0o755 : 0o644 });
      }
    }
  }
  fs.mkdirSync(destination, { recursive: true });
  extract(asar.getRawHeader(archive).header.files);
}
main().catch(error => { console.error(error); process.exitCode = 1; });
