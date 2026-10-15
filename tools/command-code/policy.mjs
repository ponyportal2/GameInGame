export const POLICY_VERSION = 1;
export const TOOL_NAMES = ['read_file','write_file','edit_file','grep','glob','read_directory',
  'reload_game','read_runtime_log','start_test_game','read_test_log','stop_test_game','test_game_action',
  'git_status','git_diff','git_log','git_commit','delete_path','move_path','blender'];
export function validReady(record, nonce, phase) {
  return record?.nonce === nonce && record.policy === 'gamesmith' && record.version === POLICY_VERSION && record.phase === phase &&
    (phase === 'loaded' || (Array.isArray(record.tools) && record.tools.length === TOOL_NAMES.length &&
      new Set(record.tools).size === TOOL_NAMES.length && record.tools.every(name=>TOOL_NAMES.includes(name))));
}
