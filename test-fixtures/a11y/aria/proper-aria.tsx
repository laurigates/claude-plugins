// TEST FILE: Properly implemented ARIA patterns
// Should NOT trigger ARIA violations

import React, { useState, useRef, useEffect } from "react";

// Proper accordion with all ARIA attributes
export function AccessibleAccordion() {
  const [openIndex, setOpenIndex] = useState<number | null>(null);

  const items = [
    { id: "section1", title: "Section 1", content: "Content for section 1" },
    { id: "section2", title: "Section 2", content: "Content for section 2" },
  ];

  return (
    <div className="accordion">
      {items.map((item, index) => (
        <div key={item.id} className="accordion-item">
          <h3>
            <button
              id={`${item.id}-trigger`}
              aria-expanded={openIndex === index}
              aria-controls={`${item.id}-panel`}
              onClick={() => setOpenIndex(openIndex === index ? null : index)}
            >
              {item.title}
            </button>
          </h3>
          <div
            id={`${item.id}-panel`}
            role="region"
            aria-labelledby={`${item.id}-trigger`}
            hidden={openIndex !== index}
          >
            {item.content}
          </div>
        </div>
      ))}
    </div>
  );
}

// Proper tabs with all ARIA attributes
export function AccessibleTabs() {
  const [activeTab, setActiveTab] = useState(0);

  const tabs = [
    { id: "tab1", label: "First Tab", content: "First tab content" },
    { id: "tab2", label: "Second Tab", content: "Second tab content" },
    { id: "tab3", label: "Third Tab", content: "Third tab content" },
  ];

  return (
    <div className="tabs">
      <div role="tablist" aria-label="Content sections">
        {tabs.map((tab, index) => (
          <button
            key={tab.id}
            role="tab"
            id={tab.id}
            aria-selected={activeTab === index}
            aria-controls={`${tab.id}-panel`}
            tabIndex={activeTab === index ? 0 : -1}
            onClick={() => setActiveTab(index)}
          >
            {tab.label}
          </button>
        ))}
      </div>
      {tabs.map((tab, index) => (
        <div
          key={`${tab.id}-panel`}
          role="tabpanel"
          id={`${tab.id}-panel`}
          aria-labelledby={tab.id}
          hidden={activeTab !== index}
          tabIndex={0}
        >
          {tab.content}
        </div>
      ))}
    </div>
  );
}

// Proper dropdown menu
export function AccessibleMenu() {
  const [isOpen, setIsOpen] = useState(false);
  const menuRef = useRef<HTMLUListElement>(null);

  return (
    <div className="menu-container">
      <button
        aria-haspopup="menu"
        aria-expanded={isOpen}
        aria-controls="menu-list"
        onClick={() => setIsOpen(!isOpen)}
      >
        Actions
      </button>
      {isOpen && (
        <ul ref={menuRef} id="menu-list" role="menu" aria-label="Actions menu">
          <li role="menuitem" tabIndex={-1}>
            Edit
          </li>
          <li role="menuitem" tabIndex={-1}>
            Duplicate
          </li>
          <li role="menuitem" tabIndex={-1}>
            Delete
          </li>
        </ul>
      )}
    </div>
  );
}

// Proper icon button with accessible name
export function AccessibleIconButton({
  icon,
  label,
  onClick,
}: {
  icon: React.ReactNode;
  label: string;
  onClick: () => void;
}) {
  return (
    <button onClick={onClick} aria-label={label}>
      <span aria-hidden="true">{icon}</span>
    </button>
  );
}

// Proper custom checkbox
export function AccessibleCheckbox({
  checked,
  onChange,
  label,
}: {
  checked: boolean;
  onChange: (checked: boolean) => void;
  label: string;
}) {
  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === " " || e.key === "Enter") {
      e.preventDefault();
      onChange(!checked);
    }
  };

  return (
    <div
      role="checkbox"
      aria-checked={checked}
      tabIndex={0}
      onClick={() => onChange(!checked)}
      onKeyDown={handleKeyDown}
      className="custom-checkbox"
    >
      <span className="checkbox-indicator" aria-hidden="true" />
      <span>{label}</span>
    </div>
  );
}

// Proper live region for notifications
export function AccessibleNotification({
  message,
  type,
}: {
  message: string;
  type: "info" | "error";
}) {
  if (!message) return null;

  return (
    <div
      role={type === "error" ? "alert" : "status"}
      aria-live={type === "error" ? "assertive" : "polite"}
      className={`notification notification-${type}`}
    >
      {message}
    </div>
  );
}

// Proper modal dialog
export function AccessibleDialog({
  isOpen,
  onClose,
  title,
  children,
}: {
  isOpen: boolean;
  onClose: () => void;
  title: string;
  children: React.ReactNode;
}) {
  const dialogRef = useRef<HTMLDivElement>(null);
  const titleId = "dialog-title";

  useEffect(() => {
    if (isOpen) {
      dialogRef.current?.focus();
    }
  }, [isOpen]);

  if (!isOpen) return null;

  return (
    <div
      ref={dialogRef}
      role="dialog"
      aria-modal="true"
      aria-labelledby={titleId}
      tabIndex={-1}
      className="dialog-overlay"
    >
      <div className="dialog-content">
        <h2 id={titleId}>{title}</h2>
        {children}
        <button onClick={onClose}>Close</button>
      </div>
    </div>
  );
}
