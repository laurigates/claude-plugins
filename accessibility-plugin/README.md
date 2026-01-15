# Accessibility Plugin

Comprehensive accessibility and UX implementation tooling for WCAG compliance, ARIA patterns, design tokens, and user experience design.

## Overview

This plugin provides specialized tools and agents for implementing accessible, usable digital experiences. It bridges the gap between UX design strategy and production code, ensuring WCAG compliance and best-in-class user experience patterns.

## Components

### Skills

#### accessibility-implementation
Technical implementation of WCAG 2.1/2.2 guidelines, ARIA patterns, and assistive technology support.

**Use when:**
- Implementing accessible components
- Fixing accessibility issues
- Adding ARIA attributes and keyboard navigation
- Setting up accessibility testing
- User mentions WCAG, ARIA, screen readers, or keyboard navigation

**Covers:**
- WCAG Level A and AA compliance
- ARIA patterns (modals, tabs, forms, live regions)
- Keyboard navigation and focus management
- Screen reader compatibility
- Automated testing with axe-core, Lighthouse, pa11y
- Manual testing checklists

#### design-tokens
CSS custom property architecture, theme systems, and design token organization.

**Use when:**
- Implementing design systems
- Setting up theme switching (light/dark mode)
- Creating component token architecture
- Integrating with CSS frameworks (Tailwind, etc.)
- User mentions design tokens, CSS variables, or theming

**Covers:**
- Three-tier token architecture (primitive, semantic, component)
- Light/dark theme implementation
- React theme context patterns
- Responsive token systems
- Token naming conventions and best practices

### Agents

#### ux-implementation
Bridges the gap between service design decisions and production code.

**Use proactively for:**
- Implementing UX designs with accessibility compliance
- Translating WCAG/ARIA requirements to code
- Creating component usability patterns
- Implementing design token systems
- Responsive behavior implementation
- Bridging service-design decisions to production

**Capabilities:**
- WCAG 2.1/2.2 implementation
- ARIA pattern expertise
- Keyboard navigation and focus management
- Design token architecture
- Responsive implementation patterns
- Performance-aware UX

**Model:** Claude Opus 4.5

#### service-design
Strategic UX architecture, service blueprints, and interaction design.

**Use proactively for:**
- UX architecture and strategy
- Service blueprints and user journey mapping
- Interaction design patterns
- Accessibility strategy
- User research and persona development

**Capabilities:**
- User journey mapping
- Service blueprinting
- Information architecture
- WCAG compliance strategy
- Universal design principles
- Omnichannel strategy

**Model:** Claude Opus 4.5

## Use Cases

### Accessibility Compliance
```bash
# Implement WCAG 2.1 AA compliance for a form
claude agent ux-implementation "Make the registration form WCAG 2.1 AA compliant"

# Audit accessibility issues
claude skill accessibility-implementation "Run accessibility audit on dashboard"
```

### Design System Implementation
```bash
# Set up design token system
claude skill design-tokens "Create design token architecture with light/dark themes"

# Implement responsive tokens
claude agent ux-implementation "Implement responsive design tokens for mobile-first layout"
```

### UX Strategy
```bash
# Create service blueprint
claude agent service-design "Create service blueprint for checkout flow"

# Design user journey
claude agent service-design "Map user journey for onboarding experience"
```

### Agent Coordination
```bash
# Scan for UX handoff markers (using agent-patterns-plugin)
/handoffs --agent ux-implementation

# Create handoff for implementation (see agent-patterns-plugin for marker format)
# @AGENT-HANDOFF-MARKER(ux-implementation) { type: "accessibility", ... }
```

## Integration with Other Plugins

### Testing Plugin
- Use with `test-architecture` agent for accessibility test strategy
- Combine with `test-runner` for automated a11y testing
- Integrate axe-core tests into CI/CD pipelines

### Code Quality Plugin
- Use with `code-review` agent for accessibility code review
- Combine with linting for automated checks
- Enforce WCAG compliance in code standards

### TypeScript Plugin
- Use with `typescript-development` for type-safe component APIs
- Implement ARIA patterns with proper TypeScript types
- Create accessible React components with type safety

### Python Plugin
- Use with `python-development` for backend accessibility features
- Implement accessible APIs and data structures
- Support assistive technology integration

## Best Practices

### Accessibility First
- Use semantic HTML before ARIA
- Test with actual assistive technologies
- Provide multiple interaction modes (keyboard, mouse, touch)
- Design for progressive enhancement

### Design Tokens
- Follow three-tier architecture (primitive → semantic → component)
- Use consistent naming conventions
- Provide fallback values
- Document token purpose and usage

### Agent Coordination
- Use @AGENT-HANDOFF-MARKER for asynchronous communication (see agent-patterns-plugin)
- Provide specific requirements, not vague requests
- Include context and references
- Clean up completed markers

### UX Implementation
- Validate with WCAG success criteria
- Test keyboard navigation manually
- Verify screen reader announcements
- Check color contrast ratios

## Resources

### WCAG Guidelines
- WCAG 2.1 Quick Reference: https://www.w3.org/WAI/WCAG21/quickref/
- ARIA Authoring Practices: https://www.w3.org/WAI/ARIA/apg/

### Testing Tools
- axe-core: https://github.com/dequelabs/axe-core
- Lighthouse: https://developers.google.com/web/tools/lighthouse
- pa11y: https://pa11y.org/

### Design Tokens
- Design Tokens Format: https://design-tokens.github.io/community-group/format/
- Style Dictionary: https://styledictionary.com/

### Learning Resources
- A11y Project Checklist: https://www.a11yproject.com/checklist/
- WebAIM: https://webaim.org/
- Deque University: https://dequeuniversity.com/

## Keywords

accessibility, wcag, aria, ux, design-tokens, service-design, usability, a11y, keyboard-navigation, screen-readers, theme-switching, design-systems, user-journey, service-blueprints, inclusive-design

## Version

1.0.0
