// Shared persistence and wire records; harness admission/cancellation policy stays native.
import {writeFileSync, renameSync, rmSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
export function atomicSaveSession(file, value) {
  const temporary=file+'.'+randomUUID()+'.tmp';
  try {writeFileSync(temporary,JSON.stringify(value));renameSync(temporary,file);}
  finally {rmSync(temporary,{force:true});}
}
export function failureRecord(operation,error,{requestPreserved}={}) {
  const details={error:error.message,initialization_failed:!!error.initializationFailed,runtime_failed:!!error.runtimeFailed};
  if(requestPreserved!==undefined)details.request_preserved=requestPreserved;
  return operation.accepted ? {type:'complete',ok:false,text:operation.text,...details} : {type:'response',id:operation.request.id,success:false,...details};
}
