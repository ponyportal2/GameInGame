import {toolSpecs} from './workspace-tools.mjs';
const tools=new Set(toolSpecs().map(t=>t.name.slice(10)));
export function permissionDecision(payload,state) {
  const call=payload?.toolCall,args=call?.args;
  const valid=state?.active===true && !!state.session && payload.conversationId===state.session;
  if(valid && call?.name==='finish')return {decision:'auto_approve'};
  if(valid && call?.name==='call_mcp_tool' && args?.ServerName==='gamesmith' && tools.has(args.ToolName)
    && args.Arguments && typeof args.Arguments==='object' && !Array.isArray(args.Arguments))
    return {decision:'auto_approve'};
  return {decision:'deny',reason:'Use only the gamesmith MCP server during the current GameSmith request. Native shell, filesystem, browser, delegation and external MCP tools are unavailable.'};
}
export function normalizeRecord(record) {
  const s=record.event==='step_update' ? record.step_update : undefined;
  if(!s)return [];
  if(s.step_type==='agent_response' && typeof s.text_delta==='string' && s.text_delta)
    return [{type:'delta',kind:'assistant',text:s.text_delta}];
  if(s.step_type==='tool' && ['ACTIVE','DONE'].includes(s.state)) {
    const name=s.tool_name || s.tool_info?.name || 'AGY tool';
    const args=s.tool_info?.parameters;
    return [{type:'tool',name:name==='call_mcp_tool' && args?.ServerName==='gamesmith' ? args.ToolName || name : name,description:''}];
  }
  // result.usage is cumulative for the conversation, not current context usage.
  return [];
}
export function reconcileText(streamed,final) {
  const text=typeof final==='string' ? final : streamed;
  return {text,suffix:text.startsWith(streamed) ? text.slice(streamed.length) : '',corrected:!text.startsWith(streamed)};
}
