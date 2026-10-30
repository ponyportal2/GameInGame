import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
// Every file that tells a player, a CI job or a test which Pi release this
// repository supports. Historical notes (docs/todos, .plan, BUILD_REPORT) are
// deliberately absent: they record what was true then and must not be rewritten.
const SITES=['README.md','GameSmith-Windows/README.txt','tools/testing/README.md','THIRD_PARTY_NOTICES.md','GameSmith-Windows/THIRD_PARTY_NOTICES.md','src/pi/pi_rpc_session.gd','tests/pi_integration_runner.gd','tools/windows-bootstrap/main.go','tools/windows-bootstrap/main_test.go','.github/workflows/build-windows-package.yml','.github/workflows/verify-windows.yml'];
// A sentence may end right after the version ("...@1.4.0. If Pi is installed"),
// so each dot has to be followed by a digit to stay part of the number.
const PIN=/pi-coding-agent@(\d+(?:\.\d+)+)/g;
const versions=text=>[...text.matchAll(PIN)].map(match=>match[1]);

test('every current Pi pin names the README integration target',()=>{
  const canonical=[...new Set(versions(readFileSync(resolve(root,'README.md'),'utf8')))];
  assert.equal(canonical.length,1,'README.md should name exactly one Pi integration target');
  const [want]=canonical;
  for(const site of SITES){
    const found=versions(readFileSync(resolve(root,site),'utf8'));
    assert(found.length>0,site+' should name the pinned Pi install');
    assert.deepEqual(found.filter(version=>version!==want),[],[site,'names a Pi release other than',want,'(found',found.join(', '),')'].join(' '));
  }
});

test('the tracked Windows launcher carries the current pin and no stale one',()=>{
  const [want]=[...new Set(versions(readFileSync(resolve(root,'README.md'),'utf8')))];
  // The launcher ships its guidance inside the executable, so a corrected source
  // tree still hands players a stale install command until it is rebuilt.
  const found=versions(readFileSync(resolve(root,'GameSmith-Windows/GameSmith.exe')).toString('latin1'));
  assert(found.length>0,'GameSmith.exe should carry the Pi install guidance');
  assert(found.includes(want),'GameSmith.exe does not carry the current Pi pin; rebuild the launcher');
  assert.deepEqual(found.filter(version=>version!==want),[],[...new Set(found.filter(version=>version!==want))].join(', ')+' is still embedded in GameSmith.exe');
});
