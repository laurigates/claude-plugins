# OpenFeature SDK Installation

Read when adding the OpenFeature SDK and a provider package to a project (Node.js server/browser, Python, Go, Java, Rust).

## Node.js (Server)

```bash
# Core SDK
npm install @openfeature/server-sdk

# Providers (choose one)
npm install @openfeature/go-feature-flag-provider  # GO Feature Flag
npm install @openfeature/flagd-provider            # flagd
npm install @openfeature/in-memory-provider        # Testing
```

## Node.js (Browser/React)

```bash
# Web SDK
npm install @openfeature/web-sdk

# React integration
npm install @openfeature/react-sdk

# Web providers
npm install @openfeature/go-feature-flag-web-provider
```

## Python

```bash
uv add openfeature-sdk
uv add openfeature-provider-go-feature-flag  # GO Feature Flag provider
```

## Go

```bash
go get github.com/open-feature/go-sdk
go get github.com/open-feature/go-sdk-contrib/providers/go-feature-flag
```

## Java

```xml
<dependency>
    <groupId>dev.openfeature</groupId>
    <artifactId>sdk</artifactId>
    <version>1.7.0</version>
</dependency>
```

## Rust

```toml
[dependencies]
open-feature = "0.2"
```
