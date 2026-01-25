// TEST FILE: Contains incorrect ARIA role usage
// Should trigger ARIA pattern violations

import React from "react";

// VIOLATION: Redundant roles on semantic elements
export function RedundantRoles() {
  return (
    <div>
      {/* Redundant - button already has implicit button role */}
      <button role="button">Click me</button>

      {/* Redundant - anchor with href has implicit link role */}
      <a href="/page" role="link">
        Go to page
      </a>

      {/* Redundant - h1 has implicit heading role */}
      <h1 role="heading" aria-level={1}>
        Title
      </h1>

      {/* Redundant - ul has implicit list role */}
      <ul role="list">
        <li role="listitem">Item</li>
      </ul>

      {/* Redundant - nav has implicit navigation role */}
      <nav role="navigation">Links here</nav>
    </div>
  );
}

// VIOLATION: Invalid role values
export function InvalidRoles() {
  return (
    <div>
      {/* Invalid role - typo */}
      <div role="buton">Should be button</div>

      {/* Invalid role - doesn't exist */}
      <div role="clickable">Not a real role</div>

      {/* Invalid role - misspelling */}
      <div role="dialgo">Should be dialog</div>
    </div>
  );
}

// VIOLATION: Conflicting roles
export function ConflictingRoles() {
  return (
    <div>
      {/* Button with link role - conflicting semantics */}
      <button role="link">I'm confused</button>

      {/* Link with button role */}
      <a href="/page" role="button">
        Also confused
      </a>

      {/* Heading with button role */}
      <h2 role="button">Clickable heading?</h2>
    </div>
  );
}

// VIOLATION: Missing roles on custom components
export function MissingRoles() {
  const [isOpen, setIsOpen] = React.useState(false);
  const [checked, setChecked] = React.useState(false);

  return (
    <div>
      {/* Custom dropdown without proper role */}
      <div className="dropdown">
        <div className="dropdown-trigger" onClick={() => setIsOpen(!isOpen)}>
          Select option
        </div>
        {isOpen && (
          // Missing role="listbox" or role="menu"
          <div className="dropdown-menu">
            <div className="option">Option 1</div>
            <div className="option">Option 2</div>
          </div>
        )}
      </div>

      {/* Custom checkbox without role */}
      <div
        className={`custom-checkbox ${checked ? "checked" : ""}`}
        onClick={() => setChecked(!checked)}
        // Missing role="checkbox" and aria-checked
      >
        <span className="checkmark" />
        Accept terms
      </div>

      {/* Custom switch without role */}
      <div className="toggle" onClick={() => setChecked(!checked)}>
        <div className="toggle-track">
          <div className="toggle-thumb" />
        </div>
        {/* Missing role="switch" and aria-checked */}
      </div>
    </div>
  );
}
