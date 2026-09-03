---
created: 2025-12-16
modified: 2026-05-09
reviewed: 2026-04-25
name: accessibility-implementation
description: "WCAG 2.1/2.2 compliance, ARIA patterns, keyboard nav, focus management, a11y testing. Use when implementing accessible components or user mentions WCAG/ARIA/screen readers."
user-invocable: false
allowed-tools: Glob, Grep, Read, Edit, Write, Bash(npm *), Bash(npx *), Bash(axe *), TodoWrite, WebSearch, WebFetch
---

# Accessibility Implementation

Technical implementation of WCAG guidelines, ARIA patterns, and assistive technology support.

## When to Use This Skill

| Use this skill when... | Use design-tokens instead when... |
|---|---|
| Implementing WCAG 2.1/2.2 success criteria in code | Setting up CSS custom properties or theme systems |
| Adding ARIA roles, states, or live regions | Defining semantic colour tokens used by themes |
| Wiring keyboard navigation, focus traps, or skip links | Organizing primitive/semantic/component token tiers |
| Auditing components with axe-core, jest-axe, or Playwright | Implementing light/dark mode token overrides |

## Core Expertise

- **WCAG Compliance**: Implementing WCAG 2.1/2.2 success criteria in code
- **ARIA Patterns**: Correct usage of roles, states, and properties
- **Keyboard Navigation**: Focus management, key handlers, logical tab order
- **Screen Readers**: Content structure, announcements, live regions
- **Testing**: Automated and manual accessibility testing

## WCAG Quick Reference

### Level A (Must Have)

| Criterion | Implementation |
|-----------|----------------|
| 1.1.1 Non-text Content | `alt` for images, labels for inputs |
| 1.3.1 Info and Relationships | Semantic HTML, ARIA relationships |
| 2.1.1 Keyboard | All interactive elements keyboard accessible |
| 2.4.1 Bypass Blocks | Skip links, landmarks |
| 4.1.2 Name, Role, Value | ARIA labels, roles for custom widgets |

### Level AA (Should Have)

| Criterion | Implementation |
|-----------|----------------|
| 1.4.3 Contrast (Minimum) | 4.5:1 text, 3:1 large text |
| 1.4.11 Non-text Contrast | 3:1 for UI components |
| 2.4.6 Headings and Labels | Descriptive, hierarchical headings |
| 2.4.7 Focus Visible | Visible focus indicator (2px+ outline) |

## Best Practices

### Semantic HTML First
Use native HTML elements before ARIA. A `<button>` is better than `<div role="button">`.

### Don't Override Default Behavior
Native elements have built-in accessibility. Don't break it with JavaScript.

### Test with Real Users
Automated tools catch ~30% of issues. Manual testing with assistive technology is essential.

### Provide Multiple Ways
Offer keyboard, mouse, and touch alternatives for all interactions.

## References

- WCAG 2.1 Guidelines: https://www.w3.org/WAI/WCAG21/quickref/
- ARIA Authoring Practices: https://www.w3.org/WAI/ARIA/apg/
- axe-core Rules: https://dequeuniversity.com/rules/axe/
- A11y Project Checklist: https://www.a11yproject.com/checklist/

For full ARIA widget patterns, keyboard navigation implementations, testing recipes, common fixes, and CSS utilities, see [REFERENCE.md](REFERENCE.md).
