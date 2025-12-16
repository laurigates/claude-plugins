---
name: accessibility-implementation
description: WCAG 2.1/2.2 compliance implementation, ARIA patterns, keyboard navigation, focus management, and accessibility testing. Use when implementing accessible components, fixing accessibility issues, or when the user mentions WCAG, ARIA, screen readers, or keyboard navigation.
allowed-tools: Glob, Grep, Read, Edit, Write, Bash, BashOutput, TodoWrite, WebSearch, WebFetch
---

# Accessibility Implementation

Technical implementation of WCAG guidelines, ARIA patterns, and assistive technology support.

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

## ARIA Patterns

### Buttons and Links

```html
<!-- Custom button -->
<div role="button" tabindex="0"
     aria-pressed="false"
     onkeydown="handleKeyDown(event)">
  Toggle Feature
</div>

<!-- Icon button (needs accessible name) -->
<button aria-label="Close dialog">
  <svg aria-hidden="true">...</svg>
</button>

<!-- Link vs button -->
<!-- Use link for navigation, button for actions -->
<a href="/page">Go to page</a>
<button type="button">Submit form</button>
```

### Form Controls

```html
<!-- Input with label -->
<label for="email">Email address</label>
<input id="email" type="email"
       aria-describedby="email-hint email-error"
       aria-invalid="true"
       required>
<div id="email-hint">We'll never share your email</div>
<div id="email-error" role="alert">Please enter a valid email</div>

<!-- Checkbox group -->
<fieldset>
  <legend>Notification preferences</legend>
  <label><input type="checkbox" name="notif" value="email"> Email</label>
  <label><input type="checkbox" name="notif" value="sms"> SMS</label>
</fieldset>

<!-- Combobox (autocomplete) -->
<label for="country">Country</label>
<input id="country"
       role="combobox"
       aria-expanded="false"
       aria-autocomplete="list"
       aria-controls="country-listbox">
<ul id="country-listbox" role="listbox" hidden>
  <li role="option" id="opt-us">United States</li>
  <li role="option" id="opt-uk">United Kingdom</li>
</ul>
```

### Modal Dialog

```html
<div role="dialog"
     aria-modal="true"
     aria-labelledby="dialog-title"
     aria-describedby="dialog-desc">
  <h2 id="dialog-title">Confirm Action</h2>
  <p id="dialog-desc">Are you sure you want to proceed?</p>
  <button>Cancel</button>
  <button>Confirm</button>
</div>
```

```typescript
// Focus trap implementation
function trapFocus(dialog: HTMLElement) {
  const focusable = dialog.querySelectorAll(
    'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
  );
  const first = focusable[0] as HTMLElement;
  const last = focusable[focusable.length - 1] as HTMLElement;

  dialog.addEventListener('keydown', (e) => {
    if (e.key === 'Tab') {
      if (e.shiftKey && document.activeElement === first) {
        e.preventDefault();
        last.focus();
      } else if (!e.shiftKey && document.activeElement === last) {
        e.preventDefault();
        first.focus();
      }
    }
    if (e.key === 'Escape') {
      closeDialog();
    }
  });

  // Move focus to first element
  first.focus();
}
```

### Tabs

```html
<div role="tablist" aria-label="Settings tabs">
  <button role="tab"
          id="tab-1"
          aria-selected="true"
          aria-controls="panel-1">
    General
  </button>
  <button role="tab"
          id="tab-2"
          aria-selected="false"
          aria-controls="panel-2"
          tabindex="-1">
    Privacy
  </button>
</div>

<div role="tabpanel" id="panel-1" aria-labelledby="tab-1">
  General settings content
</div>
<div role="tabpanel" id="panel-2" aria-labelledby="tab-2" hidden>
  Privacy settings content
</div>
```

```typescript
// Tab keyboard navigation
tablist.addEventListener('keydown', (e) => {
  const tabs = Array.from(tablist.querySelectorAll('[role="tab"]'));
  const current = tabs.indexOf(document.activeElement as Element);

  let next: number;
  switch (e.key) {
    case 'ArrowRight':
      next = (current + 1) % tabs.length;
      break;
    case 'ArrowLeft':
      next = (current - 1 + tabs.length) % tabs.length;
      break;
    case 'Home':
      next = 0;
      break;
    case 'End':
      next = tabs.length - 1;
      break;
    default:
      return;
  }

  e.preventDefault();
  (tabs[next] as HTMLElement).focus();
  activateTab(tabs[next]);
});
```

### Live Regions

```html
<!-- Status messages -->
<div role="status" aria-live="polite">
  Form saved successfully
</div>

<!-- Alerts (interrupts) -->
<div role="alert" aria-live="assertive">
  Error: Connection lost
</div>

<!-- Progress updates -->
<div aria-live="polite" aria-atomic="true">
  Loading: 45% complete
</div>
```

## Keyboard Navigation

### Standard Key Bindings

| Key | Behavior |
|-----|----------|
| Tab | Move to next focusable element |
| Shift+Tab | Move to previous focusable element |
| Enter/Space | Activate button, select option |
| Escape | Close modal, cancel operation |
| Arrow keys | Navigate within component (tabs, menu, listbox) |
| Home/End | Go to first/last item in list |

### Focus Management

```typescript
// Return focus after modal close
const triggerElement = document.activeElement;
openModal();
// On close:
closeModal();
triggerElement?.focus();

// Move focus to error
function showValidationErrors() {
  const firstError = document.querySelector('[aria-invalid="true"]');
  (firstError as HTMLElement)?.focus();
}

// Skip link
<a href="#main-content" class="skip-link">Skip to main content</a>
<main id="main-content" tabindex="-1">...</main>
```

### Roving Tabindex

```typescript
// For composite widgets (toolbar, menu, tabs)
function setRovingTabindex(container: HTMLElement, selector: string) {
  const items = container.querySelectorAll(selector);

  items.forEach((item, index) => {
    item.setAttribute('tabindex', index === 0 ? '0' : '-1');
  });

  container.addEventListener('keydown', (e) => {
    const current = Array.from(items).indexOf(document.activeElement as Element);
    let next = current;

    if (e.key === 'ArrowRight' || e.key === 'ArrowDown') {
      next = (current + 1) % items.length;
    } else if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') {
      next = (current - 1 + items.length) % items.length;
    }

    if (next !== current) {
      items[current].setAttribute('tabindex', '-1');
      items[next].setAttribute('tabindex', '0');
      (items[next] as HTMLElement).focus();
      e.preventDefault();
    }
  });
}
```

## Testing

### Automated Testing

```bash
# axe-core CLI
npx @axe-core/cli https://localhost:3000

# Lighthouse accessibility audit
npx lighthouse http://localhost:3000 --only-categories=accessibility --output=json

# pa11y
npx pa11y http://localhost:3000

# jest-axe for unit tests
npm install --save-dev jest-axe
```

```typescript
// jest-axe example
import { axe, toHaveNoViolations } from 'jest-axe';

expect.extend(toHaveNoViolations);

test('component is accessible', async () => {
  const { container } = render(<MyComponent />);
  const results = await axe(container);
  expect(results).toHaveNoViolations();
});
```

```typescript
// Playwright accessibility testing
import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

test('page should not have accessibility violations', async ({ page }) => {
  await page.goto('/');

  const results = await new AxeBuilder({ page })
    .withTags(['wcag2a', 'wcag2aa'])
    .analyze();

  expect(results.violations).toEqual([]);
});
```

### Manual Testing Checklist

**Keyboard Navigation**
- [ ] All interactive elements reachable via Tab
- [ ] Focus order matches visual order
- [ ] Focus indicator always visible
- [ ] No keyboard traps
- [ ] Escape closes modals/menus

**Screen Reader Testing**
- [ ] VoiceOver (macOS): Cmd+F5
- [ ] NVDA (Windows): Free download
- [ ] Test: Links announce destination
- [ ] Test: Forms announce labels and errors
- [ ] Test: Dynamic content announced

**Visual Testing**
- [ ] Zoom to 200% without horizontal scroll
- [ ] Color contrast meets ratios
- [ ] Information not conveyed by color alone
- [ ] Focus indicators visible in all themes

## Common Fixes

### Missing Accessible Name

```html
<!-- Bad: Icon button without label -->
<button><svg>...</svg></button>

<!-- Good: Add aria-label -->
<button aria-label="Close">
  <svg aria-hidden="true">...</svg>
</button>
```

### Missing Form Labels

```html
<!-- Bad: Placeholder as label -->
<input placeholder="Email">

<!-- Good: Proper label -->
<label for="email">Email</label>
<input id="email" type="email">

<!-- Good: Visually hidden label -->
<label for="search" class="visually-hidden">Search</label>
<input id="search" type="search" placeholder="Search...">
```

### Missing Heading Structure

```html
<!-- Bad: Skipping heading levels -->
<h1>Page Title</h1>
<h3>Section</h3>  <!-- Missing h2 -->

<!-- Good: Proper hierarchy -->
<h1>Page Title</h1>
<h2>Section</h2>
<h3>Subsection</h3>
```

### Focus Not Visible

```css
/* Bad: Removing focus outline */
button:focus { outline: none; }

/* Good: Custom focus indicator */
button:focus-visible {
  outline: 2px solid #0066cc;
  outline-offset: 2px;
}
```

### Color Contrast

```css
/* Bad: Low contrast */
.text { color: #999; background: #fff; } /* 2.85:1 ratio */

/* Good: Sufficient contrast */
.text { color: #595959; background: #fff; } /* 4.56:1 ratio */
```

## CSS Utilities

```css
/* Visually hidden but accessible */
.visually-hidden {
  position: absolute;
  width: 1px;
  height: 1px;
  padding: 0;
  margin: -1px;
  overflow: hidden;
  clip: rect(0, 0, 0, 0);
  white-space: nowrap;
  border: 0;
}

/* Skip link */
.skip-link {
  position: absolute;
  top: -40px;
  left: 0;
  padding: 8px;
  background: #000;
  color: #fff;
  z-index: 100;
}

.skip-link:focus {
  top: 0;
}

/* Reduced motion */
@media (prefers-reduced-motion: reduce) {
  *,
  *::before,
  *::after {
    animation-duration: 0.01ms !important;
    transition-duration: 0.01ms !important;
  }
}
```

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
