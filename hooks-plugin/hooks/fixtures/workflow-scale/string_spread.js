// a spread string holds one item per character: 12
await Promise.all([..."abcdefghijkl"].map((c) => agent(c)));
