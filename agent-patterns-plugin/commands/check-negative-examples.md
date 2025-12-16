---
description: "Check skills/commands for negative framing and suggest positive alternatives"
allowed_tools: [Bash, Grep, Read, Edit, AskUserQuestion]
---

Check Claude skills, commands, and subagent prompts for negative examples and convert them to positive framing.

**Background**: Anthropic's prompt engineering best practice recommends positive framing instead of negative instructions to avoid the "pink elephant problem" - telling Claude "don't do X" can actually increase the likelihood of X happening because it primes that concept.

**What to detect:**
- Negative instructions: "don't", "do not", "never", "avoid", "must not", "cannot", "can't"
- Prohibitive language: "do NOT", "NEVER", "AVOID" (emphasis versions)
- Exception: Some negative framing is acceptable when:
  - Used sparingly with light touch
  - Explaining what something is NOT as clarification
  - In examples showing what to avoid
  - In security contexts where explicit prohibitions are necessary

**Steps:**

1. **Scan for negative patterns**:
   ```bash
   # Search in skills
   grep -rn -E "(don't|do not|doesn't|do NOT|never|NEVER|avoid|Avoid|AVOID|must not|shouldn't|should not|can't|cannot)" \
     ~/.claude/skills/ \
     --include="*.md" \
     -A 1 -B 1

   # Search in commands
   grep -rn -E "(don't|do not|doesn't|do NOT|never|NEVER|avoid|Avoid|AVOID|must not|shouldn't|should not|can't|cannot)" \
     ~/.claude/commands/ \
     --include="*.md" \
     -A 1 -B 1
   ```

2. **Analyze findings**:
   - Group by file and pattern
   - Count total occurrences
   - Identify high-frequency offenders
   - Filter out acceptable uses (e.g., in examples, security contexts)

3. **Generate positive alternatives**:
   For each negative instruction found, suggest positive reframing:

   **Common transformations:**
   - "Don't use X" → "Use Y instead" or "Prefer Y for this task"
   - "Never do X" → "Always do Y" or "Use Y as the standard approach"
   - "Avoid X" → "Prefer Y" or "Use Y for better results"
   - "Don't forget to X" → "Remember to X" or "Always X"
   - "Do not create new files" → "Edit existing files whenever possible"
   - "Don't use emojis" → "Use plain text formatting" or "Keep responses professional"
   - "Never edit manually" → "Use automated workflows for updates"

   **Examples from real scenarios:**
   - ❌ "Do not use markdown" → ✅ "Your response should be composed of smoothly flowing prose paragraphs"
   - ❌ "Do not make new versions" → ✅ "Make all updates in current files whenever possible"
   - ❌ "Never manually edit CHANGELOG.md" → ✅ "Use conventional commits to automatically generate CHANGELOG entries"
   - ❌ "Don't batch completions" → ✅ "Mark tasks complete immediately after finishing each one"

4. **Present findings report**:
   ```
   🔍 Negative Framing Analysis
   =============================

   Scanned locations:
   - ~/.claude/skills/ (XX files)
   - ~/.claude/commands/ (XX files)

   Total negative patterns found: XX

   📊 Breakdown by pattern:
   - "don't"/"do not": XX occurrences
   - "never": XX occurrences
   - "avoid": XX occurrences
   - Other: XX occurrences

   📁 Files with most negative framing:
   1. path/to/file.md (XX instances)
   2. path/to/file2.md (XX instances)

   🔧 Suggested rewrites:

   File: ~/.claude/skills/example/SKILL.md:42
   ❌ Current: "Don't use X when processing data"
   ✅ Suggested: "Use Y for data processing tasks"

   [Continue for each finding...]
   ```

5. **Ask user for action**:
   Use AskUserQuestion to ask:
   ```
   Found XX instances of negative framing across XX files.

   What would you like to do?
   1. Show all findings with suggested fixes
   2. Auto-fix straightforward cases (review before commit)
   3. Show summary only
   4. Export report to file
   ```

6. **Apply fixes (if requested)**:
   - For auto-fix option:
     - Only fix clear-cut cases
     - Skip ambiguous or security-critical instructions
     - Use Edit tool to make changes
     - Create list of changes made

   - For manual review:
     - Show each instance with context
     - Provide suggested rewrite
     - Ask for confirmation before editing

7. **Final report**:
   ```
   ✅ Negative Framing Check Complete!

   Summary:
   - Scanned: XX files
   - Found: XX instances
   - Fixed: XX instances
   - Remaining: XX instances (require manual review)

   Next steps:
   1. Review changes: git diff
   2. Test affected skills/commands
   3. Commit if satisfied: git commit -m "fix: convert negative framing to positive alternatives"

   💡 Tip: Use positive framing to tell Claude what TO do, not what NOT to do.
   This prevents the "pink elephant problem" where mentioning unwanted behavior
   actually increases its likelihood.
   ```

**Implementation notes:**
- Focus on instruction text, not explanatory prose
- Preserve security-critical negative instructions (e.g., "NEVER commit secrets")
- Keep the original meaning while reframing positively
- Some legitimate uses of negative language are acceptable for clarity
- Prioritize high-impact changes (frequently-used skills/commands)

**Best practices for positive framing:**
1. Tell Claude what TO do instead of what NOT to do
2. Describe desired behavior explicitly
3. Use examples of correct behavior
4. Frame constraints as preferred alternatives
5. Save strong negative language for critical security/safety issues

**References:**
- Anthropic prompt engineering: "Tell Claude what to do instead of what not to do"
- Article: "The Pink Elephant Problem: Why 'Don't Do That' Fails with LLMs"
- Claude Code best practices: Positive framing improves reliability
