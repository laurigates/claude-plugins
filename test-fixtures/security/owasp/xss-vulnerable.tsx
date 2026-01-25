// TEST FILE: Contains XSS vulnerability patterns
// For workflow validation - DO NOT use these patterns in production

import React from "react";

interface Props {
  userContent: string;
  htmlContent: string;
  url: string;
}

// VULNERABLE: dangerouslySetInnerHTML with user content
function UnsafeHtmlRenderer({ userContent }: Props) {
  return <div dangerouslySetInnerHTML={{ __html: userContent }} />;
}

// VULNERABLE: innerHTML assignment
function DirectDomManipulation({ htmlContent }: Props) {
  React.useEffect(() => {
    const element = document.getElementById("content");
    if (element) {
      element.innerHTML = htmlContent; // XSS vulnerability
    }
  }, [htmlContent]);

  return <div id="content" />;
}

// VULNERABLE: document.write with user data
function LegacyRenderer({ userContent }: Props) {
  React.useEffect(() => {
    document.write(userContent); // XSS vulnerability
  }, []);

  return null;
}

// VULNERABLE: Unvalidated URL in href
function UnsafeLink({ url }: Props) {
  // Could be javascript: URL
  return <a href={url}>Click me</a>;
}

// VULNERABLE: eval with user input
function DynamicCode({ userContent }: Props) {
  const result = eval(userContent); // Code injection
  return <div>{result}</div>;
}

// VULNERABLE: Function constructor
function DynamicFunction({ userContent }: Props) {
  const fn = new Function("return " + userContent);
  return <div>{fn()}</div>;
}

export {
  UnsafeHtmlRenderer,
  DirectDomManipulation,
  LegacyRenderer,
  UnsafeLink,
  DynamicCode,
  DynamicFunction,
};
