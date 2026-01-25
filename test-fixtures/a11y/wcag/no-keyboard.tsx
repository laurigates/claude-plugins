// TEST FILE: Contains elements without keyboard support
// Should trigger WCAG 2.1.1 Keyboard violations

import React, { useState } from "react";

interface CardProps {
  title: string;
  onClick: () => void;
}

// VIOLATION: onClick without keyboard handler
export function ClickableCard({ title, onClick }: CardProps) {
  return (
    // div with onClick but no keyboard support
    <div className="card" onClick={onClick}>
      <h3>{title}</h3>
      <p>Click to expand</p>
    </div>
  );
}

// VIOLATION: Custom button using div without keyboard
export function CustomButton({ label }: { label: string }) {
  const handleClick = () => {
    console.log("clicked");
  };

  return (
    // Should be a button or have tabIndex, role, and keyboard handlers
    <div className="custom-button" onClick={handleClick}>
      {label}
    </div>
  );
}

// VIOLATION: Mouse-only hover interaction
export function HoverTooltip({ text }: { text: string }) {
  const [show, setShow] = useState(false);

  return (
    <span
      className="tooltip-trigger"
      onMouseEnter={() => setShow(true)}
      onMouseLeave={() => setShow(false)}
      // Missing onFocus/onBlur for keyboard users
    >
      Hover me
      {show && <div className="tooltip">{text}</div>}
    </span>
  );
}

// VIOLATION: tabIndex > 0 disrupts tab order
export function BadTabOrder() {
  return (
    <div>
      <button tabIndex={3}>Third</button>
      <button tabIndex={1}>First</button>
      <button tabIndex={2}>Second</button>
    </div>
  );
}

// VIOLATION: Draggable without keyboard alternative
export function DraggableItem({ id }: { id: string }) {
  const handleDragStart = (e: React.DragEvent) => {
    e.dataTransfer.setData("text/plain", id);
  };

  return (
    <div
      draggable
      onDragStart={handleDragStart}
      // No keyboard-based reordering mechanism
    >
      Drag me
    </div>
  );
}

// VIOLATION: Span acting as link without keyboard
export function FakeLink({ href }: { href: string }) {
  return (
    <span
      className="link"
      onClick={() => (window.location.href = href)}
      // Missing tabIndex, role="link", and keyboard handler
    >
      Click here
    </span>
  );
}
