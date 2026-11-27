// runs the real Code.gs behind http; Google services mocked, bytes are SIGNED like in Apps Script
const fs=require('fs'),vm=require('vm'),http=require('http'),crypto=require('crypto');
const all={},made={},cache=new Map(),props={},drive=[],mails=[];let mode='',n=0,delay=0;
const signed=b=>Array.from(b,x=>x>127?x-256:x), buf=a=>Buffer.from(a.map(x=>x&255));
const mk=rows=>({appendRow(r){if(mode==='rowfail')throw new Error('row');rows.push(r.map(x=>typeof x==='string'&&x[0]==="'"?x.slice(1):x))},setFrozenRows(){},getLastRow:()=>rows.length,
 getRange:(r,c,h=1,w=1)=>({getValues:()=>Array.from({length:h},(_,i)=>rows[r-1+i].slice(c-1,c-1+w))})});
const ss={getSheetByName:k=>made[k]||null,insertSheet:k=>made[k]=mk(all[k]=[])};
const folder={getId:()=>'F',isTrashed:()=>false,getUrl:()=>'u',createFile(b){const f={name:b.name,bytes:mode==='corrupt'?b.bytes.slice(1):b.bytes,trashed:false,getBlob(){return{getBytes:()=>this.bytes}},getUrl:()=>'https://drive/'+b.name,setTrashed(v){this.trashed=v}};drive.push(f);return f}};
const ctx={console:{error(){}},LockService:{getScriptLock:()=>({tryLock:()=>true,releaseLock(){}})},SpreadsheetApp:{flush(){},getActiveSpreadsheet:()=>ss},
 CacheService:{getScriptCache:()=>({get:k=>cache.has(k)?cache.get(k):null,put:(k,v)=>cache.set(k,v),remove:k=>cache.delete(k)})},
 MailApp:{getRemainingDailyQuota:()=>100,sendEmail:m=>mails.push(m)},
 PropertiesService:{getScriptProperties:()=>({getProperty:k=>props[k]||null,setProperty:(k,v)=>props[k]=v})},
 DriveApp:{getStorageLimit:()=>15e9,getStorageUsed:()=>mode==='full'?14.9e9:0,createFolder:()=>{n++;return folder},getFolderById:()=>folder},
 Utilities:{computeDigest:(a,s)=>signed(crypto.createHash('sha256').update(Array.isArray(s)?buf(s):s).digest()),base64EncodeWebSafe:b=>buf(b).toString('base64url'),
  base64Decode:s=>signed(Buffer.from(s,'base64')),newBlob:(b,t,name)=>({bytes:b,name,getDataAsString:()=>buf(b).toString('utf8')}),formatDate:()=>'261124',getUuid:()=>crypto.randomUUID(),DigestAlgorithm:{SHA_256:1},Charset:{}},
 ContentService:{createTextOutput:t=>({t,setMimeType(){return this}}),MimeType:{}},Logger:{log(){}}};
vm.createContext(ctx);vm.runInContext(fs.readFileSync(require('path').join(__dirname,'../register/Code.gs'),'utf8'),ctx);
const res=new Map();let id=0;
http.createServer((q,s)=>{const u=new URL(q.url,'http://x');
 if(u.pathname==='/state'){s.setHeader('content-type','application/json; charset=utf-8');return s.end(JSON.stringify({rows:all.SkillGoi||[],folders:n,drive:drive.map(f=>({name:f.name,trashed:f.trashed,zip:buf(f.bytes).toString('base64')}))}))}
 if(u.pathname==='/feat'){s.setHeader('content-type','application/json; charset=utf-8');return s.end(JSON.stringify(all.YeuCau||[]))}
 if(u.pathname==='/mail'){s.setHeader('content-type','application/json; charset=utf-8');const m=mails[mails.length-1];return s.end(JSON.stringify(m?{to:m.to,code:(m.subject.match(/(\d{6})$/)||[])[1]}:{}))}
 if(u.pathname==='/reg'){s.setHeader('content-type','application/json; charset=utf-8');return s.end(JSON.stringify(Object.keys(all).filter(k=>!/YeuCau|SkillGoi|SkillGopY|Loi/.test(k)).map(k=>all[k])))}
 if(u.pathname==='/mode'){mode=u.searchParams.get('m');return s.end('ok')}
 if(u.pathname==='/reset'){cache.clear();return s.end('ok')}
 if(u.pathname==='/echo')return s.end(res.get(u.searchParams.get('i')));
 let b=[];q.on('data',d=>b.push(d));q.on('end',()=>{let t=ctx.doPost({postData:{contents:Buffer.concat(b).toString()}}).t;
  if(mode==='drop'){mode='';return s.destroy()}          // stored, but the answer is lost
  if(mode==='noreceipt')t='{"ok":true}';
  res.set(String(++id),t);s.writeHead(302,{Location:'/echo?i='+id});s.end()});
}).listen(8767,'127.0.0.1');
