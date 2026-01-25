// TEST FILE: Contains heading hierarchy and focus visibility issues
// Should trigger WCAG 2.4.6 and 2.4.7 violations

import React from "react";
import "./styles.css";

// VIOLATION: Skipped heading levels
export function ArticlePage() {
  return (
    <article>
      <h1>Main Title</h1>
      {/* Skips h2, goes directly to h3 */}
      <h3>First Section</h3>
      <p>Content here...</p>

      <h3>Second Section</h3>
      <p>More content...</p>

      {/* Skips to h5 */}
      <h5>Subsection</h5>
      <p>Subsection content...</p>
    </article>
  );
}

// VIOLATION: Multiple h1 elements
export function MultipleH1Page() {
  return (
    <div>
      <header>
        <h1>Site Name</h1>
      </header>
      <main>
        <h1>Page Title</h1>
        <h1>Another Section</h1>
      </main>
    </div>
  );
}

// VIOLATION: Generic heading text
export function GenericHeadings() {
  return (
    <div>
      <h2>Section</h2>
      <h2>Details</h2>
      <h2>More Information</h2>
      <h3>Click here</h3>
    </div>
  );
}

// VIOLATION: Generic link text
export function GenericLinks() {
  return (
    <nav>
      <a href="/page1">Click here</a>
      <a href="/page2">Read more</a>
      <a href="/page3">Learn more</a>
      <a href="/page4">Here</a>
    </nav>
  );
}

// VIOLATION: Focus outline removed without alternative
export function NoFocusIndicator() {
  return (
    <div>
      {/* Inline style removing focus */}
      <button style={{ outline: "none" }}>No Focus Style</button>

      {/* Another pattern */}
      <a href="/page" style={{ outline: 0 }}>
        Link without focus
      </a>

      {/* Input with outline removed */}
      <input type="text" style={{ outline: "none" }} placeholder="Type here" />
    </div>
  );
}

// CSS that would cause issues (in associated stylesheet)
// .button:focus { outline: none; }
// .link:focus { outline: 0; }

// VIOLATION: Empty links
export function EmptyLinks() {
  return (
    <div>
      <a href="/page"></a>
      <a href="/another" className="icon-link">
        {/* No text, no aria-label */}
      </a>
    </div>
  );
}
