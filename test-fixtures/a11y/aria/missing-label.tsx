// TEST FILE: Contains missing or poor ARIA labels
// Should trigger ARIA pattern violations

import React from "react";

// VIOLATION: Icon-only buttons without accessible name
export function IconButtons() {
  return (
    <div className="toolbar">
      {/* Missing aria-label */}
      <button className="icon-btn">
        <svg viewBox="0 0 24 24">
          <path d="M3 17.25V21h3.75L17.81..." />
        </svg>
      </button>

      {/* Missing aria-label */}
      <button className="icon-btn">
        <svg viewBox="0 0 24 24">
          <path d="M19 6.41L17.59 5 12..." />
        </svg>
      </button>

      {/* Missing aria-label */}
      <button className="icon-btn">
        <svg viewBox="0 0 24 24">
          <path d="M12 2C6.48 2 2 6.48..." />
        </svg>
      </button>
    </div>
  );
}

// VIOLATION: Generic aria-labels
export function GenericLabels() {
  return (
    <div>
      {/* Generic, unhelpful label */}
      <button aria-label="button">Do something</button>

      {/* Generic label */}
      <input type="text" aria-label="input" />

      {/* Generic label */}
      <nav aria-label="menu">
        <a href="/home">Home</a>
        <a href="/about">About</a>
      </nav>
    </div>
  );
}

// VIOLATION: aria-label repeating visible text
export function RedundantLabels() {
  return (
    <div>
      {/* aria-label same as visible text - redundant */}
      <button aria-label="Submit">Submit</button>

      {/* aria-label same as visible text */}
      <a href="/home" aria-label="Home">
        Home
      </a>

      {/* aria-label same as text content */}
      <h1 aria-label="Welcome to our site">Welcome to our site</h1>
    </div>
  );
}

// VIOLATION: Missing aria-label on inputs without visible label
export function UnlabeledInputs() {
  return (
    <form>
      {/* No label, no aria-label, only placeholder */}
      <input type="text" placeholder="Enter your name" />

      {/* No label, no aria-label */}
      <input type="email" placeholder="Email address" />

      {/* No label, no aria-label */}
      <textarea placeholder="Write your message..." />

      {/* Search input without label */}
      <div className="search-box">
        <input type="search" placeholder="Search..." />
        <button>
          <svg viewBox="0 0 24 24">
            <path d="M15.5 14h-.79l-.28-.27..." />
          </svg>
        </button>
      </div>
    </form>
  );
}

// VIOLATION: References to non-existent IDs
export function BrokenReferences() {
  return (
    <div>
      {/* aria-labelledby references non-existent ID */}
      <div role="region" aria-labelledby="nonexistent-heading">
        <p>This region references a heading that doesn't exist</p>
      </div>

      {/* aria-describedby references non-existent ID */}
      <input
        type="text"
        aria-describedby="nonexistent-description"
        aria-label="Some input"
      />

      {/* aria-controls references non-existent ID */}
      <button aria-controls="nonexistent-panel" aria-expanded="false">
        Toggle Panel
      </button>
    </div>
  );
}

// VIOLATION: Live regions misuse
export function LiveRegionIssues() {
  return (
    <div>
      {/* aria-live="assertive" on non-urgent content */}
      <div aria-live="assertive">
        <p>This is just regular content</p>
      </div>

      {/* Missing aria-live on dynamic notification area */}
      <div className="notifications">{/* Notifications would appear here */}</div>

      {/* Missing role="alert" or aria-live on error message */}
      <div className="error-message">Please fill in all required fields</div>
    </div>
  );
}
