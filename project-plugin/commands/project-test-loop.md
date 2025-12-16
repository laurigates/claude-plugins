---
description: "Run test → fix → refactor loop with TDD workflow"
allowed_tools: [Read, Edit, Bash]
---

Run automated TDD cycle: test → fix → refactor.

**Note**: This is a generic template. Run `/blueprint:generate-commands` to create a project-specific version with correct test commands.

**Steps**:

1. **Detect test command** (if not already configured):
   - Check `package.json` for `scripts.test` (Node.js)
   - Check for `pytest` or `python -m unittest` (Python)
   - Check for `cargo test` (Rust)
   - Check for `go test ./...` (Go)
   - Check `Makefile` for test target
   - If not found, ask user how to run tests

2. **Run test suite**:
   ```bash
   # Run detected test command
   [test_command]
   ```

3. **Analyze results**:

   **If tests FAIL**:
   - Parse failure output
   - Identify failing tests:
     * Which tests failed?
     * What assertions failed?
     * What was expected vs actual?
   - Identify root cause:
     * Bug in implementation?
     * Missing implementation?
     * Incorrect test?
   - Make minimal fix:
     * Fix only what's needed to pass the failing test
     * Don't add extra functionality
     * Don't fix tests (fix code instead)
   - Re-run tests to confirm fix
   - Loop back to step 2

   **If tests PASS**:
   - Check for refactoring opportunities:
     * Code duplication?
     * Unclear naming?
     * Long functions?
     * Complex logic that can be simplified?
     * Magic numbers/strings to extract?
   - If refactoring identified:
     * Refactor while keeping tests green
     * Re-run tests after each refactoring
     * Ensure tests still pass
   - If no refactoring needed:
     * Report success
     * Stop loop

4. **Repeat until**:
   - All tests pass AND
   - No obvious refactoring opportunities

   **OR stop if**:
   - User intervention needed
   - Blocked by external dependency
   - Unclear how to fix failure

5. **Report results**:
   ```
   🧪 Test Loop Results:

   Cycles: [N] iterations

   Fixes Applied:
   - [Fix 1]: [Brief description]
   - [Fix 2]: [Brief description]

   Refactorings Performed:
   - [Refactor 1]: [Brief description]
   - [Refactor 2]: [Brief description]

   Current Status:
   ✅ All tests pass
   ✅ Code refactored
   📝 Ready for commit

   OR

   ⚠️ Blocked: [Reason]
   📝 Next steps: [Recommendation]
   ```

**TDD Cycle Details**:

### RED Phase (If starting new feature)
1. Write failing test describing desired behavior
2. Run tests → Should FAIL (expected)
3. This command picks up from here

### GREEN Phase (This command handles)
1. Run tests
2. If fail → Make minimal fix
3. Re-run tests → Should PASS
4. Loop until all pass

### REFACTOR Phase (This command handles)
1. Tests pass
2. Look for improvements
3. Refactor
4. Re-run tests → Should STILL PASS
5. Loop until no improvements

**Common Failure Patterns**:

**Pattern: Missing Implementation**
- **Symptom**: `undefined is not a function`, `NameError`, etc.
- **Fix**: Implement the missing function/class/method
- **Minimal**: Just the signature, return dummy value

**Pattern: Wrong Return Value**
- **Symptom**: `Expected X but got Y`
- **Fix**: Update implementation to return correct value
- **Minimal**: Don't add extra logic, just fix the return

**Pattern: Missing Edge Case**
- **Symptom**: Test fails for specific input
- **Fix**: Handle the edge case
- **Minimal**: Add condition for this case only

**Pattern: Integration Issue**
- **Symptom**: Test fails when components interact
- **Fix**: Fix the integration point
- **Minimal**: Fix just the integration, not entire components

**Refactoring Opportunities**:

**Look for**:
- Duplicated code → Extract to function
- Magic numbers → Extract to constants
- Long functions → Break into smaller functions
- Complex conditionals → Extract to well-named functions
- Unclear names → Rename to be descriptive
- Comments explaining code → Refactor code to be self-explanatory

**Don't**:
- Change behavior
- Add new functionality
- Skip test runs
- Make tests pass by changing tests

**Auto-Stop Conditions**:

Stop and report if:
- All tests pass + no refactoring needed (SUCCESS)
- Same test fails 3 times in a row (STUCK)
- Error in test command itself (TEST SETUP ISSUE)
- External dependency unavailable (BLOCKED)
- Unclear how to fix (NEEDS USER INPUT)

**Integration with Blueprint Development**:

This command applies project-specific skills:
- **Testing strategies**: Knows how to structure tests
- **Implementation guides**: Knows how to implement fixes
- **Quality standards**: Knows what to refactor
- **Architecture patterns**: Knows where code should go
