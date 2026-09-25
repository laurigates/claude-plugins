// agent() inside a ${...} interpolation, which the text scans blanked
for (let i = 0; i < 12; i++) log(`${await agent("x")}`);
