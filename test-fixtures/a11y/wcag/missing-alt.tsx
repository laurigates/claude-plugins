// TEST FILE: Contains images without alt attributes
// Should trigger WCAG 1.1.1 Non-text Content violations

import React from "react";

interface GalleryProps {
  images: Array<{ src: string; title: string }>;
}

// VIOLATION: Images without alt attribute
export function Gallery({ images }: GalleryProps) {
  return (
    <div className="gallery">
      {/* Missing alt - informative image */}
      <img src="/photo1.jpg" />

      {/* Missing alt - another informative image */}
      <img src="/product-photo.png" className="product-image" />

      {/* Empty alt on informative image (should have description) */}
      <img src="/team-photo.jpg" alt="" />

      {images.map((image) => (
        // Dynamic images without alt
        <img key={image.src} src={image.src} />
      ))}
    </div>
  );
}

// VIOLATION: Icon button without accessible name
export function IconButton({ onClick }: { onClick: () => void }) {
  return (
    <button onClick={onClick} className="icon-btn">
      {/* No aria-label, no visible text, no alt on icon */}
      <img src="/icons/delete.svg" />
    </button>
  );
}

// VIOLATION: Link with image but no alt
export function ImageLink({ href }: { href: string }) {
  return (
    <a href={href}>
      <img src="/logo.png" />
    </a>
  );
}

// VIOLATION: Form input without label
export function SearchBox() {
  return (
    <div className="search">
      {/* Input without associated label */}
      <input type="text" placeholder="Search..." />
      <button>
        <img src="/icons/search.svg" />
      </button>
    </div>
  );
}
