# Codex Quota Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a self-signable IPA with live server Codex quota and black/white widgets.

**Architecture:** A small authenticated service invokes the installed Codex protocol. SwiftUI and WidgetKit consume a normalized snapshot over HTTPS; the app never receives OpenAI authentication.

**Tech Stack:** SwiftUI, WidgetKit, AppIntents (iOS 17+), Security Keychain, Python standard library, XcodeGen, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-24-codex-quota-design.md`

## Global Constraints

- iOS 16 minimum; native Liquid Glass on iOS 26 and standard materials on older systems.
- Two widget kinds: black and white, each small/medium.
- No OpenAI credentials, server access codes, or account identifiers in Git or IPA.
- Isolated branch and directory; preserve existing products and server routes.

## Review Focus

- Missing/null quota windows must remain unavailable, never become 100%.
- A past reset must show waiting for fresh data, not a negative timer or inferred full allowance.
- A failed refresh must keep its old timestamp and visible stale state.
- Invalid access code must fail before invoking Codex or returning account data.
- Missing App Group entitlement must have a documented iOS 17+ widget configuration fallback.

### Task 1: Read-only backend

Files: `quota-ios/backend/quota_service.py`, `quota-ios/backend/tests/test_quota_service.py`.
Produces: authenticated `GET /v1/quota`, JSON `{version,updatedAt,stale,plan,windows:[{id,title,usedPercent,remainingPercent,windowMinutes,resetsAt}]}`; `GET /health` contains no account data.

- [ ] Write normalization, cache-failure and HTTP authorization tests; run and observe missing behavior.
- [ ] Implement finite validated quota mapping, app-server JSON-RPC transport, bounded caching, HTTP routes.
- [ ] Run `python3 -m unittest discover -s quota-ios/backend/tests -v`; all pass.

### Task 2: App and widgets

Files: `quota-ios/Shared/*.swift`, `quota-ios/App/*.swift`, `quota-ios/Widget/*.swift`, `quota-ios/Tests/*.swift`, `quota-ios/project.yml`.
Consumes: Task 1 snapshot schema and bearer endpoint.
Produces: app, black/white small/medium widgets, model XCTest target.

- [ ] Write XCTest cases for decoding nullable resets, remaining clamping, stale timestamps, and past resets before models.
- [ ] Implement models, HTTPS client, Keychain and optional App Group configuration, Chinese glass interface, and WidgetKit providers with manual iOS 17+ fallback.
- [ ] Generate/build/test in the GitHub macOS job; inspect actual diagnostics and repair failures.

### Task 3: Deployment and IPA delivery

Files: `.github/workflows/build-codex-quota.yml`, `quota-ios/scripts/package-ipa.sh`, `quota-ios/backend/codex-quota.service`, `quota-ios/README.md`.
Consumes: compiled `.app` and Task 1 service.
Produces: deployed read-only HTTPS route, Actions unsigned IPA artifact, reproducible instructions.

- [ ] Deploy loopback service with private generated code and isolated nginx location; validate config before reload.
- [ ] Check health, unauthorized request rejection, and authenticated live quota via public HTTPS.
- [ ] Publish branch via GitHub tools and inspect Actions run; retrieve IPA if successful.
- [ ] Run all repository tests, inspect diffs for credentials and unrelated changes, record evidence and remaining device-signing limits.
