function d(n,r){if(!n||n.length===0){alert("Tidak ada data untuk diekspor.");return}const o=Object.keys(n[0]),i=t=>{if(t==null)return"";const e=String(t);return e.includes(",")||e.includes('"')||e.includes(`
`)?`"${e.replace(/"/g,'""')}"`:e},l=[o.join(","),...n.map(t=>o.map(e=>i(t[e])).join(","))].join(`
`),u=new Blob(["\uFEFF"+l],{type:"text/csv;charset=utf-8"}),s=URL.createObjectURL(u),c=document.createElement("a");c.href=s,c.download=`${r}_${new Date().toISOString().slice(0,10)}.csv`,c.click(),URL.revokeObjectURL(s)}export{d};
