// a helper that calls its parameter twice, once per finding
const twice = async (fn) => {
  await fn();
  await fn();
};
for (const f of args.findings) await twice(() => agent(f));
