import { normalizeFrame } from './protocol.mjs';

// Native SSE sends text separately from part snapshots. Keep per-part cursors
// so final snapshots fill missing text without replaying streamed content.
export function createEventNormalizer(session) {
  const parts=new Map(), roles=new Map(), seen=new Set();
  function text(record,delta) {
    if (!delta) return [];
    record.text+=delta;
    const kind=record.type==='reasoning' ? 'thinking' : 'assistant';
    return [{type:'delta',kind,text:delta},...(kind==='assistant' ? [{type:'assistant_text',text:delta}] : [])];
  }
  return event=>{
    const properties=event.properties || {};
    if (event.type==='message.updated') {
      if (properties.info?.sessionID===session) roles.set(properties.info.id,properties.info.role);
      return [];
    }
    if (event.type==='session.error' && properties.sessionID===session) return normalizeFrame({type:'error',error:properties.error});
    if (event.type==='session.status' && properties.sessionID===session && properties.status?.type==='retry')
      return [{type:'status',text:`OpenCode is retrying the provider request (attempt ${properties.status.attempt || 1})...`}];
    if (event.type==='message.part.delta') {
      const record=parts.get(properties.partID);
      if (properties.sessionID!==session || properties.field!=='text' || !record || !['text','reasoning'].includes(record.type)) return [];
      return text(record,properties.delta || '');
    }
    const part=properties.part;
    if (event.type!=='message.part.updated' || part?.sessionID!==session || roles.get(part.messageID)==='user') return [];
    if (['text','reasoning'].includes(part.type)) {
      // Player text has no generation time; never echo it as assistant text.
      if (!part.time && roles.get(part.messageID)!=='assistant') return [];
      let record=parts.get(part.id);
      if (!record) {record={type:part.type,text:''};parts.set(part.id,record);}
      const delta=(part.text || '').slice(record.text.length);
      const result=text(record,delta);
      if (part.type==='reasoning' && !part.time?.end && !delta) return [{type:'status',text:'OpenCode is thinking...'}];
      return result;
    }
    const type={'step-start':'step_start','step-finish':'step_finish',tool:'tool_use'}[part.type];
    if (!type || (type==='tool_use' && !['running','completed','error'].includes(part.state?.status))) return [];
    const key=part.id+':'+type+':'+(part.state?.status || '');
    if (seen.has(key)) return [];seen.add(key);
    return normalizeFrame({type,part});
  };
}
