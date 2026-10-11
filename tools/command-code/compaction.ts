// Observe the native /compact outcome, including no-op/failure, without changing it.
export default function (cmd) {
  if (process.env.GAMESMITH_COMPACTION_OBSERVER !== 'gamesmith-v2') return;
  for (const type of ['compaction_start','compaction_outcome']) {
    cmd.on(type, event => process.stdout.write(JSON.stringify({type:'gamesmith_compaction',event}) + '\n'));
  }
}
