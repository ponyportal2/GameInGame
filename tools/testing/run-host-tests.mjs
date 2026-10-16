// Compatibility entrypoint. The unified runner owns isolation and evidence.
import {parseArgs,runVerification} from './verify.mjs';
const [godot,...scripts]=process.argv.slice(2);
if(!godot)throw new Error('Usage: run-host-tests.mjs <godot> [runner.gd ...]');
const args=['--godot',godot,'--suite','host','--output',process.env.GAMESMITH_VERIFY_OUTPUT||'summary'];
if(scripts.length===1&&scripts[0].endsWith('_integration_runner.gd'))args.push('--live',scripts[0].replace('_integration_runner.gd','').replaceAll('_','-'));
else if(scripts.length)args.push('--test',scripts.map(s=>'host:'+s.replace('_runner.gd','')).join(','));
process.exitCode=(await runVerification(parseArgs(args))).status==='passed'?0:1;
