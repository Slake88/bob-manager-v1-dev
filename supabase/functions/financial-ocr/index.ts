import { createClient } from 'npm:@supabase/supabase-js@2';

const H={
  'Content-Type':'application/json',
  'Access-Control-Allow-Origin':'*',
  'Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods':'POST, OPTIONS',
  'Access-Control-Max-Age':'86400',
};
const PROVIDER='google_cloud_vision';
const MODEL='DOCUMENT_TEXT_DETECTION';
const MAX_BYTES=7_000_000;
type J=Record<string,unknown>;

function b64(bytes:Uint8Array){
  let s=''; const n=0x8000;
  for(let i=0;i<bytes.length;i+=n)s+=String.fromCharCode(...bytes.subarray(i,Math.min(i+n,bytes.length)));
  return btoa(s);
}
function line(s:string){return s.replace(/\s+/g,' ').trim();}
function num(s:string):number|null{
  let v=s.trim().replace(/[€$£\s]/g,'').replace(/[^\d,.\-]/g,'');
  if(!v||!/\d/.test(v))return null;
  const c=v.lastIndexOf(','),d=v.lastIndexOf('.');
  if(c>=0&&d>=0)v=c>d?v.replace(/\./g,'').replace(',','.'):v.replace(/,/g,'');
  else if(c>=0)v=(v.length-c-1)<=2?v.replace(/\./g,'').replace(',','.'):v.replace(/,/g,'');
  else if(d>=0&&(v.length-d-1)>2)v=v.replace(/\./g,'');
  const x=Number(v); return Number.isFinite(x)?x:null;
}
function vals(s:string){
  return (s.match(/-?\d+(?:[.\s]\d{3})*(?:,\d{1,2})|-?\d+(?:\.\d{1,2})/g)??[])
    .map(num).filter((x):x is number=>x!==null);
}
function money(s:string){const a=vals(s);return a.length?a[a.length-1]:null;}
function amountOnly(s:string){
  return /^\s*(?:EUR\s*)?€?\s*-?\d+(?:[.\s]\d{3})*(?:,\d{1,2}|\.\d{1,2})?\s*€?\s*$/i.test(s);
}
function byLabel(lines:string[],rx:RegExp[]){
  for(let i=lines.length-1;i>=0;i--){
    const u=lines[i].toUpperCase();
    if(!rx.some(r=>r.test(u)))continue;
    const same=money(lines[i]);
    if(same!==null && !/^\s*(?:TOTAL|SUBTOTAL|SUB-TOTAL|IVA|I\.V\.A)\s*(?:EUR)?\s*$/i.test(lines[i]))return same;
    for(let j=i+1;j<=Math.min(i+2,lines.length-1);j++){
      if(amountOnly(lines[j])){
        const next=money(lines[j]);
        if(next!==null)return next;
      }
    }
  }
  return null;
}
function date(s:string):string|null{
  let m=s.match(/\b(20\d{2}|19\d{2})[-/.](\d{1,2})[-/.](\d{1,2})\b/);
  let y:number,mo:number,da:number;
  if(m){y=+m[1];mo=+m[2];da=+m[3];}
  else{
    m=s.match(/\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})\b/); if(!m)return null;
    da=+m[1];mo=+m[2];y=+m[3]; if(y<100)y+=y>=70?1900:2000;
  }
  if(mo<1||mo>12||da<1||da>31)return null;
  return `${String(y).padStart(4,'0')}-${String(mo).padStart(2,'0')}-${String(da).padStart(2,'0')}`;
}
function supplier(lines:string[]){
  for(const s of lines.slice(0,12)){
    if(s.length<3||s.length>100||!/[A-Za-zÀ-ÿ]/.test(s))continue;
    if(/^(NIF|NIPC|VAT|CONTRIBUINTE|FATURA|FACTURA|RECIBO|TAL[AÃ]O|DATA|HORA|TEL|WWW\.|HTTP)/i.test(s))continue;
    if((s.match(/\d/g)??[]).length>Math.floor(s.length*.45))continue;
    return s;
  } return null;
}
function taxId(t:string){
  const normalize=(v:string|null|undefined)=>{const d=(v??'').replace(/\D/g,'');return d.length===9?d:null;};
  const a=t.match(/(?:NIF|NIPC|CONTRIBUINTE|VAT(?:\s*NO)?)[^\d]{0,12}(?:PT\s*)?(\d(?:[\s.\-]*\d){8})/i);
  const b=t.match(/\bPT\s*(\d(?:[\s.\-]*\d){8})\b/i);
  return normalize(a?.[1])??normalize(b?.[1]);
}
function docNo(lines:string[]){
  const code=/^\s*((?:FT|FR|FS|VD|NC|ND)\s+[A-Z0-9][A-Z0-9./_-]*\d[A-Z0-9./_-]*)\s*$/i;
  for(let i=0;i<Math.min(lines.length,35);i++){
    const direct=lines[i].match(code);
    if(direct)return line(direct[1]);
    if(/(?:FATURA[- ]?RECIBO|FATURA|FACTURA|RECIBO|DOCUMENTO).*N[º°]?\s*$/i.test(lines[i])){
      for(let j=i+1;j<=Math.min(i+2,lines.length-1);j++){
        const next=lines[j].match(code);
        if(next)return line(next[1]);
      }
    }
  }
  const labeled=/(?:TAL[AÃ]O|DOCUMENTO|DOC\.?|N[ÚU]MERO|N[º°])\s*[:#-]?\s*([A-Z0-9][A-Z0-9 ./_-]{2,30})/i;
  for(const s of lines.slice(0,35)){
    const m=s.match(labeled);
    if(m && /\d/.test(m[1]))return line(m[1]);
  }
  return null;
}
function payment(t:string){
  const u=t.toUpperCase();
  if(/\bMB\s*WAY\b/.test(u))return'mbway';
  if(/MULTIBANCO|CART[AÃ]O|VISA|MASTERCARD|T\.?P\.?A\.?/.test(u))return'card';
  if(/TRANSFER[EÊ]NCIA|IBAN/.test(u))return'bank_transfer';
  if(/NUMER[AÁ]RIO|DINHEIRO|CASH/.test(u))return'cash';
  return null;
}
function nonItem(s:string){
  const u=s.toUpperCase();
  return /^(TOTAL|SUBTOTAL|SUB-TOTAL|IVA|I\.V\.A|TAXA|BASE|TROCO|PAGO|PAGAMENTO|MULTIBANCO|MB WAY|NIF|NIPC|CONTRIBUINTE|DATA|HORA|DOCUMENTO|FATURA|FACTURA|RECIBO|TAL[AÃ]O)/.test(u)
    ||/OBRIGAD|WWW\.|HTTP|CAE|CAPITAL SOCIAL|CERTIFICAD|PROCESSADO/.test(u);
}
function items(lines:string[]):J[]{
  const out:J[]=[];
  for(const s of lines){
    if(s.length<4||s.length>180||nonItem(s)||!/[A-Za-zÀ-ÿ]/.test(s))continue;
    const q=s.match(/^(.+?)\s+(\d+(?:[.,]\d+)?)\s*[xX*]\s*(\d+(?:[.,]\d{1,2}))\s+(\d+(?:[.,]\d{1,2}))\s*€?$/);
    if(q){
      const a=num(q[2]),b=num(q[3]),c=num(q[4]);
      if(a!==null&&b!==null&&c!==null){out.push({description:line(q[1]),quantity:a,unit_price:b,line_total:c,tax_rate:null,sku:null});continue;}
    }
    const m=s.match(/^(.*?)(-?\d+(?:[.\s]\d{3})*(?:,\d{1,2})|-?\d+(?:\.\d{1,2}))\s*€?\s*$/);
    if(!m)continue; const d=line(m[1].replace(/[\s.:;-]+$/,''));
    const total=num(m[2]); if(d.length<2||total===null)continue;
    out.push({description:d,quantity:null,unit_price:null,line_total:total,tax_rate:null,sku:null});
  }
  const seen=new Set<string>();
  return out.filter(x=>{const k=`${String(x.description).toLowerCase()}|${String(x.line_total)}`;if(seen.has(k))return false;seen.add(k);return true;}).slice(0,80);
}
function conf(a:J){
  const f=a.fullTextAnnotation as J|undefined,p=Array.isArray(f?.pages)?f!.pages as unknown[]:[];
  const v:number[]=[];
  for(const pg of p){if(!pg||typeof pg!=='object')continue;
    const bs=Array.isArray((pg as J).blocks)?(pg as J).blocks as unknown[]:[];
    for(const b of bs){const c=b&&typeof b==='object'?(b as J).confidence:null;if(typeof c==='number'&&Number.isFinite(c))v.push(c);}
  }
  return v.length?v.reduce((x,y)=>x+y,0)/v.length:null;
}
function visionText(root:J,pdf:boolean){
  const ann:J[]=[];
  if(pdf){
    for(const f of (Array.isArray(root.responses)?root.responses:[])){
      if(!f||typeof f!=='object')continue;
      for(const p of (Array.isArray((f as J).responses)?(f as J).responses as unknown[]:[]))
        if(p&&typeof p==='object')ann.push(p as J);
    }
  } else for(const a of (Array.isArray(root.responses)?root.responses:[]))if(a&&typeof a==='object')ann.push(a as J);
  const t:string[]=[],c:number[]=[];
  for(const a of ann){
    const e=a.error as J|undefined;if(typeof e?.message==='string')throw new Error(`Google Vision: ${e.message}`);
    const f=a.fullTextAnnotation as J|undefined;
    if(typeof f?.text==='string')t.push(f.text);
    else{
      const ta=Array.isArray(a.textAnnotations)?a.textAnnotations as unknown[]:[];
      if(ta[0]&&typeof ta[0]==='object'&&typeof(ta[0] as J).description==='string')t.push(String((ta[0] as J).description));
    }
    const x=conf(a);if(x!==null)c.push(x);
  }
  const text=t.join('\n').trim(),confidence=c.length?c.reduce((x,y)=>x+y,0)/c.length:(text?.75:0);
  return{text,confidence:Math.max(0,Math.min(1,confidence)),units:Math.max(1,ann.length)};
}
function structure(text:string,confidence:number,pdf:boolean){
  const l=text.split(/\r?\n/).map(line).filter(Boolean);
  const total=byLabel(l,[/^TOTAL(?:\s|$)/,/TOTAL\s+A\s+PAGAR/,/VALOR\s+TOTAL/,/TOTAL\s+EUR/,/A\s+PAGAR/]);
  const subtotal=byLabel(l,[/^SUBTOTAL(?:\s|$)/,/^SUB-TOTAL(?:\s|$)/,/TOTAL\s+S\/?\s*IVA/,/TOTAL\s+SEM\s+IVA/]);
  const tax=byLabel(l,[/TOTAL\s+IVA/,/IVA\s+TOTAL/,/^IVA(?:\s|$)/]);
  const its=items(l),warnings=['Campos estruturados inferidos por regras automáticas do BOB Manager; confirmar antes de lançar.'];
  if(confidence<.70)warnings.push('A confiança da leitura é baixa; confirmar visualmente.');
  if(total===null)warnings.push('Não foi possível identificar o total com segurança.');
  if(!its.length)warnings.push('Não foram identificadas linhas de artigos com segurança.');
  if(pdf)warnings.push('PDF analisado em modo síncrono até às primeiras 5 páginas.');
  return{
    supplier_name:supplier(l),supplier_tax_id:taxId(text),document_number:docNo(l),
    document_date:l.map(date).find(x=>x!==null)??null,currency:/€|\bEUR\b/i.test(text)?'EUR':null,
    subtotal,tax_total:tax,total,payment_method:payment(text),confidence,
    raw_text:text.slice(0,20000),line_items:its,warnings
  };
}

Deno.serve(async(req:Request)=>{
  if(req.method==='OPTIONS')return new Response('ok',{status:200,headers:H});
  if(req.method!=='POST')return new Response(JSON.stringify({error:'method_not_allowed'}),{status:405,headers:H});
  const auth=req.headers.get('Authorization')??'',url=Deno.env.get('SUPABASE_URL')??'',anon=Deno.env.get('SUPABASE_ANON_KEY')??'';
  let service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')??'';
  try{const k=JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS')??'{}') as Record<string,string>;service=k.default??service;}catch(_){}
  if(!auth||!url||!anon||!service)return new Response(JSON.stringify({error:'supabase_server_config_missing'}),{status:500,headers:H});
  const user=createClient(url,anon,{auth:{persistSession:false,autoRefreshToken:false},global:{headers:{Authorization:auth}}});
  const admin=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
  let id='';
  try{
    const body=await req.json();id=String(body?.job_id??'');if(!id)return new Response(JSON.stringify({error:'job_id_required'}),{status:400,headers:H});
    const{data:j,error:je}=await user.from('financial_ocr_jobs').select('id,status,storage_path,mime_type').eq('id',id).single();
    if(je||!j)return new Response(JSON.stringify({error:'ocr_job_not_accessible'}),{status:403,headers:H});
    const st=String(j.status??'');
    if(['ready','reviewed','confirmed'].includes(st))return new Response(JSON.stringify({status:st,job_id:id}),{status:200,headers:H});
    if(st==='processing')return new Response(JSON.stringify({status:st,job_id:id}),{status:202,headers:H});
    if(st!=='pending')return new Response(JSON.stringify({error:'ocr_job_not_pending',status:st}),{status:409,headers:H});
    const{data:claim,error:ce}=await admin.from('financial_ocr_jobs').update({status:'processing',started_at:new Date().toISOString(),completed_at:null,error_message:null})
      .eq('id',id).eq('status','pending').select('storage_path,mime_type').maybeSingle();
    if(ce)throw ce;if(!claim)return new Response(JSON.stringify({status:'already_claimed',job_id:id}),{status:202,headers:H});
    const path=String(claim.storage_path??''),mime=String(claim.mime_type??'').toLowerCase(),pdf=mime==='application/pdf';
    if(!path)throw new Error('Pedido OCR sem ficheiro.');
    if(!['image/jpeg','image/png','image/webp','application/pdf'].includes(mime))throw new Error('Formato OCR não suportado.');
    const key=Deno.env.get('GOOGLE_VISION_API_KEY')??'',project=Deno.env.get('GOOGLE_CLOUD_PROJECT_ID')??'';
    if(!key||!project){
      await admin.from('financial_ocr_jobs').update({status:'unconfigured',provider:PROVIDER,model:MODEL,error_message:'Falta configurar GOOGLE_VISION_API_KEY e GOOGLE_CLOUD_PROJECT_ID nos secrets do Supabase.',completed_at:new Date().toISOString()}).eq('id',id);
      return new Response(JSON.stringify({status:'unconfigured',reason:'google_vision_not_configured',job_id:id}),{status:503,headers:H});
    }
    const{data:file,error:de}=await admin.storage.from('financial-documents').download(path);
    if(de||!file)throw new Error(`Não foi possível obter o documento: ${de?.message??'ficheiro indisponível'}`);
    const bytes=new Uint8Array(await file.arrayBuffer());if(!bytes.length)throw new Error('O documento está vazio.');
    if(bytes.length>MAX_BYTES)throw new Error('Para OCR Google Vision direto, comprima o ficheiro para menos de 7 MB.');
    const content=b64(bytes),base=`https://eu-vision.googleapis.com/v1/projects/${encodeURIComponent(project)}/locations/eu`;
    const endpoint=pdf?`${base}/files:annotate`:`${base}/images:annotate`;
    const payload=pdf?{requests:[{inputConfig:{content,mimeType:'application/pdf'},features:[{type:MODEL}],imageContext:{languageHints:['pt','en']},pages:[1,2,3,4,5]}]}
      :{requests:[{image:{content},features:[{type:MODEL}],imageContext:{languageHints:['pt','en']}}]};
    const r=await fetch(`${endpoint}?key=${encodeURIComponent(key)}`,{method:'POST',headers:H,body:JSON.stringify(payload)});
    const raw=await r.text();let vr:J={};try{vr=raw?JSON.parse(raw) as J:{};}catch(_){vr={raw};}
    if(!r.ok)throw new Error(`Google Vision ${r.status}: ${raw.slice(0,1200)}`);
    const v=visionText(vr,pdf);if(!v.text)throw new Error('O Google Cloud Vision não encontrou texto legível no documento.');
    const x=structure(v.text,v.confidence,pdf);
    const{error:ue}=await admin.from('financial_ocr_jobs').update({status:'ready',provider:PROVIDER,model:MODEL,provider_response_id:null,...x,
      usage:{vision_units:v.units,vision_region:'eu',parser:'bob_rules_v2',openai_enhancement:false},error_message:null,completed_at:new Date().toISOString()}).eq('id',id);
    if(ue)throw ue;
    return new Response(JSON.stringify({status:'ready',job_id:id,provider:PROVIDER,model:MODEL,confidence:x.confidence,line_count:x.line_items.length,vision_units:v.units,openai_enhancement:false}),{status:200,headers:H});
  }catch(e){
    const m=e instanceof Error?e.message:String(e);
    if(id)try{await admin.from('financial_ocr_jobs').update({status:'failed',error_message:m.slice(0,4000),completed_at:new Date().toISOString()}).eq('id',id).neq('status','confirmed');}catch(_){}
    return new Response(JSON.stringify({error:m,job_id:id||null}),{status:500,headers:H});
  }
});
