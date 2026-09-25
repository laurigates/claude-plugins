// a literal split on a literal separator: 12 pieces
await Promise.all("a,b,c,d,e,f,g,h,i,j,k,l".split(",").map((c) => agent(c)));
