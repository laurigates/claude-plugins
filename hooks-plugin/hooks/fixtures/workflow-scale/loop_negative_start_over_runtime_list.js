// a negative start over a runtime list: ASSUMED 8 items from -4 is 12 passes
for (let i = -4; i < args.units.length; i++) await agent("x" + i);
