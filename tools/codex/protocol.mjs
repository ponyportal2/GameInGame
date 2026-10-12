import { toolSpecs } from './tools.mjs';

export function threadParams(config,instructions) {
  const params={cwd:config.workspace,developerInstructions:instructions,sandbox:'read-only',approvalPolicy:'on-request',
    config:{features:{shell_tool:false,multi_agent:false,apps:false,plugins:false,view_image:false,browser_use:false,browser_use_external:false,computer_use:false,code_mode:false},web_search:'disabled'}};
  if (config.session) params.threadId=config.session;
  else params.dynamicTools=toolSpecs();
  return params;
}

// Track each assistant item separately: commentary and final answers are both
// displayed, while completed item snapshots are canonical for persistence.
export function createEventNormalizer(threadId,turnId) {
  const items=new Map();
  let error='';
  function reconcile(item) {
    if (item.type!=='agentMessage') return [];
    const old=items.get(item.id) || {text:'',shown:''};
    const text=item.text ?? old.text;
    const records=[];
    if (text.startsWith(old.shown)) {
      if (text.length>old.shown.length) records.push({type:'delta',kind:'assistant',text:(items.size && !items.has(item.id) ? '\n\n' : '')+text.slice(old.shown.length)});
    } else old.corrected=true;
    items.set(item.id,{...old,text,shown:text});return records;
  }
  return (method,p={})=>{
    if (p.threadId && p.threadId!==threadId) return [];
    if ((p.turnId || p.turn?.id) && (p.turnId || p.turn.id)!==turnId) return [];
    switch (method) {
      case 'thread/tokenUsage/updated': return [{type:'context',tokens:p.tokenUsage?.last?.totalTokens ?? null}];
      case 'item/agentMessage/delta': {
        const item=items.get(p.itemId) || {text:'',shown:''};
        const separator=items.size && !items.has(p.itemId) ? '\n\n' : '';
        item.text+=p.delta;item.shown+=p.delta;items.set(p.itemId,item);
        return [{type:'delta',kind:'assistant',text:separator+p.delta}];
      }
      case 'item/reasoning/summaryTextDelta':
      case 'item/reasoning/textDelta': return [{type:'delta',kind:'thinking',text:p.delta}];
      case 'item/started':
        return p.item?.type==='dynamicToolCall' ? [{type:'tool',name:p.item.tool,description:JSON.stringify(p.item.arguments ?? {})}] : [];
      case 'item/completed': return p.item?.type==='dynamicToolCall' ? [{type:'status',text:'Codex is working…'}] : reconcile(p.item || {});
      case 'error': if (!p.willRetry) error=p.error?.message || 'Codex request failed.'; return [];
      case 'turn/completed': {
        const records=(p.turn.items || []).flatMap(reconcile);
        const text=[...items.values()].map(i=>i.text).filter(Boolean).join('\n\n');
        const ok=p.turn.status==='completed' && !error;
        records.push({type:'complete',ok,text,corrected:[...items.values()].some(i=>i.corrected),
          error:ok ? '' : p.turn.error?.message || error || `Codex turn ${p.turn.status || 'did not complete'}.`});
        return records;
      }
      default: return [];
    }
  };
}
