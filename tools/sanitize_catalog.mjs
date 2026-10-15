// Pure evidence normalization. Never used to modify runtime database definitions.
export function sanitizeCatalog(value) {
 const visit=x=>typeof x==='string'?x.replace(/https?:\/\/[a-z0-9-]+\.supabase\.(?:co|in)\b/gi,'https://<project-ref>.supabase.co'):Array.isArray(x)?x.map(visit):x&&typeof x==='object'?Object.fromEntries(Object.entries(x).map(([k,v])=>[k,visit(v)])):x;
 const result=visit(value);
 // Capture clock and database build identify runtime, not catalog contracts.
 delete result.captured_at; delete result.version;
 return result;
}
