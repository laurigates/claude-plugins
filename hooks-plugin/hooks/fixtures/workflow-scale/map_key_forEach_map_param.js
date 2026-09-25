// Map.forEach hands the Map itself third: a key reached through it is charged too
const m = new Map([[() => agent("a"), 1]]);
for (let i = 0; i < 20; i++) m.forEach((v, k, mm) => { for (const kk of mm.keys()) kk() });
