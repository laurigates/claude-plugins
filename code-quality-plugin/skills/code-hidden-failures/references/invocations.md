# Hidden-Failure Scanner — Example Invocations

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Default scan (both tracks) | `/code:hidden-failures .` |
| Errors only, shell, high severity | `/code:hidden-failures . --track errors --lang shell --severity high` |
| Degradation only, with fixes | `/code:hidden-failures src/ --track degradation --fix` |
| Review-ready error patch | `/code:hidden-failures src/ --track errors --emit-patch > /tmp/fix.patch` |
