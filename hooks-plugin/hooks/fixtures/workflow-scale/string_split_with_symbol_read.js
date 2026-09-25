// a Symbol read anywhere makes a split unbounded, but not below the 20 pieces the string rules give
const tag = Symbol("t");
for (const p of 'a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t'.split(',')) agent(p);
