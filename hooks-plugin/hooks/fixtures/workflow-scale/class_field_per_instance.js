// a class field initializer runs once per instance: 20 instances, 20 agents
class Worker {
  result = agent("w");
}
const ws = [];
for (let i = 0; i < 20; i++) ws.push(new Worker());
await Promise.all(ws.map((w) => w.result));
