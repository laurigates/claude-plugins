// TEST FILE: Contains missing ARIA states and properties
// Should trigger ARIA pattern violations

import React, { useState } from "react";

// VIOLATION: Accordion without aria-expanded
export function BrokenAccordion() {
  const [openIndex, setOpenIndex] = useState<number | null>(null);

  const items = [
    { title: "Section 1", content: "Content 1" },
    { title: "Section 2", content: "Content 2" },
  ];

  return (
    <div className="accordion">
      {items.map((item, index) => (
        <div key={index} className="accordion-item">
          {/* Missing aria-expanded on trigger */}
          <button onClick={() => setOpenIndex(openIndex === index ? null : index)}>
            {item.title}
          </button>
          {openIndex === index && (
            <div className="accordion-panel">{item.content}</div>
          )}
        </div>
      ))}
    </div>
  );
}

// VIOLATION: Dropdown menu without aria-expanded
export function BrokenDropdown() {
  const [isOpen, setIsOpen] = useState(false);

  return (
    <div className="dropdown">
      {/* Missing aria-expanded and aria-haspopup */}
      <button onClick={() => setIsOpen(!isOpen)}>Menu</button>
      {isOpen && (
        <ul>
          {/* Missing role="menuitem" on items */}
          <li>Option 1</li>
          <li>Option 2</li>
          <li>Option 3</li>
        </ul>
      )}
    </div>
  );
}

// VIOLATION: Tabs without proper ARIA attributes
export function BrokenTabs() {
  const [activeTab, setActiveTab] = useState(0);

  const tabs = ["Tab 1", "Tab 2", "Tab 3"];

  return (
    <div className="tabs">
      {/* Missing role="tablist" */}
      <div className="tab-list">
        {tabs.map((tab, index) => (
          // Missing role="tab", aria-selected, aria-controls
          <button
            key={index}
            className={activeTab === index ? "active" : ""}
            onClick={() => setActiveTab(index)}
          >
            {tab}
          </button>
        ))}
      </div>
      {/* Missing role="tabpanel", aria-labelledby */}
      <div className="tab-panel">Content for tab {activeTab + 1}</div>
    </div>
  );
}

// VIOLATION: Slider without required attributes
export function BrokenSlider() {
  const [value, setValue] = useState(50);

  return (
    <div className="slider-container">
      <div
        role="slider"
        // Missing aria-valuenow, aria-valuemin, aria-valuemax, aria-label
        className="slider-track"
      >
        <div className="slider-thumb" style={{ left: `${value}%` }} />
      </div>
    </div>
  );
}

// VIOLATION: Combobox without required attributes
export function BrokenCombobox() {
  const [isOpen, setIsOpen] = useState(false);
  const [value, setValue] = useState("");

  return (
    <div className="combobox">
      <input
        type="text"
        role="combobox"
        // Missing aria-expanded, aria-controls, aria-autocomplete
        value={value}
        onChange={(e) => setValue(e.target.value)}
        onFocus={() => setIsOpen(true)}
      />
      {isOpen && (
        <ul id="listbox">
          <li>Suggestion 1</li>
          <li>Suggestion 2</li>
        </ul>
      )}
    </div>
  );
}

// VIOLATION: Dialog without aria-modal and aria-labelledby
export function BrokenDialog({ isOpen }: { isOpen: boolean }) {
  if (!isOpen) return null;

  return (
    // Missing aria-modal="true" and aria-labelledby
    <div role="dialog" className="modal">
      <h2>Dialog Title</h2>
      <p>Dialog content here</p>
      <button>Close</button>
    </div>
  );
}
