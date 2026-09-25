// agent reached through a comma expression, (0, agent)(...), in a 12-pass loop
for (let i = 0; i < 12; i++) await (0, agent)("x" + i);
