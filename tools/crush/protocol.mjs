// Crush 0.98.1 emits message snapshots; only run_complete ends an agent turn.
export class CrushStream {
  constructor(session,run,previous=[]){this.session=session;this.run=run;this.previous=new Set(previous);this.cursors=new Map();this.texts=new Map();this.tools=new Set();}
  message(message){
    if(message.session_id!==this.session || message.role!=='assistant' || this.previous.has(message.id) || message.is_summary_message)return [];
    const records=[];let text='';
    for(const [index,part] of (message.parts || []).entries()){
      const data=part.data || {},kind=part.type==='text' && !data.hidden ? 'assistant' : part.type==='reasoning' ? 'thinking' : '';
      if(kind){
        const value=kind==='assistant' ? data.text || '' : data.thinking || '',key=message.id+':'+index;
        const previous=this.cursors.get(key) || '';
        if(value.startsWith(previous) && value.length>previous.length)records.push({type:'delta',kind,text:value.slice(previous.length)});
        this.cursors.set(key,value);if(kind==='assistant')text+=value;
      }
      if(part.type==='tool_call' && data.name && !this.tools.has(data.id)){this.tools.add(data.id);records.push({type:'tool',name:data.name,description:data.name});}
    }
    this.texts.set(message.id,text);return records;
  }
  complete(result){
    if(result.session_id!==this.session || result.run_id!==this.run)return null;
    const records=[],previous=this.texts.get(result.message_id) || '',text=result.text || '';
    if(text.startsWith(previous) && text.length>previous.length)records.push({type:'delta',kind:'assistant',text:text.slice(previous.length)});
    this.texts.set(result.message_id,text);
    return {ok:!result.error && !result.cancelled,text:[...this.texts.values()].join(''),error:result.error || (result.cancelled ? 'Crush cancelled the turn.' : ''),records};
  }
}
