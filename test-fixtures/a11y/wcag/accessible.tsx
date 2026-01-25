// TEST FILE: Properly accessible component
// Should NOT trigger WCAG violations

import React, { useState, useRef, useEffect } from "react";

interface ImageProps {
  src: string;
  alt: string;
  isDecorative?: boolean;
}

// Proper alt text handling
export function AccessibleImage({ src, alt, isDecorative }: ImageProps) {
  if (isDecorative) {
    // Decorative images use empty alt
    return <img src={src} alt="" role="presentation" />;
  }
  return <img src={src} alt={alt} />;
}

// Proper keyboard support on custom interactive element
export function AccessibleCard({
  title,
  onActivate,
}: {
  title: string;
  onActivate: () => void;
}) {
  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" || e.key === " ") {
      e.preventDefault();
      onActivate();
    }
  };

  return (
    <div
      className="card"
      role="button"
      tabIndex={0}
      onClick={onActivate}
      onKeyDown={handleKeyDown}
      aria-label={`Activate ${title}`}
    >
      <h3>{title}</h3>
      <p>Press Enter or Space to activate</p>
    </div>
  );
}

// Proper heading hierarchy
export function AccessibleArticle() {
  return (
    <article>
      <h1>Main Article Title</h1>

      <section>
        <h2>First Section</h2>
        <p>Introduction content...</p>

        <h3>Subsection A</h3>
        <p>Details...</p>

        <h3>Subsection B</h3>
        <p>More details...</p>
      </section>

      <section>
        <h2>Second Section</h2>
        <p>Content...</p>
      </section>
    </article>
  );
}

// Proper form labeling
export function AccessibleForm() {
  return (
    <form>
      <div className="form-group">
        <label htmlFor="email">Email Address</label>
        <input
          id="email"
          type="email"
          aria-describedby="email-hint"
          required
        />
        <span id="email-hint" className="hint">
          We'll never share your email.
        </span>
      </div>

      <div className="form-group">
        <label htmlFor="password">Password</label>
        <input id="password" type="password" required />
      </div>

      <button type="submit">Sign In</button>
    </form>
  );
}

// Proper icon button with accessible name
export function AccessibleIconButton({
  onClick,
  label,
}: {
  onClick: () => void;
  label: string;
}) {
  return (
    <button onClick={onClick} aria-label={label}>
      <svg aria-hidden="true" viewBox="0 0 24 24">
        <path d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12z" />
      </svg>
    </button>
  );
}

// Proper link with descriptive text
export function AccessibleLinks() {
  return (
    <nav aria-label="Main navigation">
      <a href="/products">View our products catalog</a>
      <a href="/about">Learn about our company</a>
      <a href="/contact">Contact our support team</a>
    </nav>
  );
}

// Proper focus management
export function AccessibleModal({
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
  const closeButtonRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (isOpen) {
      closeButtonRef.current?.focus();
    }
  }, [isOpen]);

  if (!isOpen) return null;

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="modal-title"
      className="modal"
    >
      <h2 id="modal-title">{title}</h2>
      {children}
      <button ref={closeButtonRef} onClick={onClose}>
        Close
      </button>
    </div>
  );
}
