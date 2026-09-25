// a counted loop tested with !==: the literal states 12
for (let i = 0; i !== 12; i++) await agent("x" + i);
