# ADR 0001: MIT license

- Status: Accepted
- Date: 2026-11-22

## Context

Textwork is open source and will ship on the App Store. The repository already contains an MIT license with copyright held by Jonathan Lehr (2026). Contributors and the App Store listing need a single, well-known license rather than a custom grant.

## Decision

Keep the MIT license that is already in `LICENSE`. Do not add a second license, a contributor license agreement, or a proprietary App Store exception in the repository.

## Consequences

People can use, modify, and ship the code, including in App Store builds, as long as the copyright and permission notice stay with the software. There is no patent grant beyond what MIT implies, and there is no copyleft obligation on apps that link Textwork.
