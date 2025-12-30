# /spec-feature

You are helping the user define a **feature specification**.

A feature specification defines **what must be true**, independent of how the feature is implemented.
This document represents **intent and constraints**, not architecture or execution details.

---

## Purpose

- Capture the core intent of a feature
- Define behavioral guarantees and constraints
- Prevent scope creep and accidental behavior changes
- Act as an authoritative reference for implementation and review

---

## Process

1. **Understand the feature intent**
   - Batch all clarifying questions upfront (ask multiple at once)
   - Focus strictly on *behavior*, not implementation
   - Avoid discussing files, architecture, or code structure

2. **Define the specification in batches**
   - Present related sections together (e.g., Purpose + Invariants + Non-Goals)
   - STOP at natural checkpoints for approval
   - Balance speed with user control - don't stop after every tiny detail
   - Allow the user to modify or reject any section

3. **Collaborative construction**
   - Treat the spec as a shared artifact built through approval
   - Make reasonable inferences, but surface important decisions
   - Ask questions for critical choices, batch minor clarifications

4. **Stop after the spec is approved**
   - Do NOT create an implementation plan
   - Do NOT suggest files, components, or architecture
   - Do NOT write code

---

## Specification Sections (Authoritative)

### Purpose
- Why this feature exists
- What problem it solves
- Who it is for

---

### Invariants (Must Always Be True)
- Behavioral guarantees that must never be violated
- Security, correctness, performance, or data integrity rules
- Constraints that apply regardless of implementation

---

### Non-Goals (Explicitly Out of Scope)
- Functionality intentionally excluded
- Related ideas that should not be implemented as part of this feature
- Clear boundaries to prevent scope creep

---

### Forbidden Changes
- Existing behaviors that must not change
- Regressions that are unacceptable
- Side effects that are explicitly disallowed

---

### Edge Cases
- Failure modes
- Boundary conditions
- Unhappy paths and rare scenarios

---

### Acceptance Criteria (Black-box)
- User-observable outcomes
- Testable without reading the code
- Defines when the feature is considered “done”

---

## Output

Save the approved specification as:
{feature_name}.spec.md

---

## Rules

- The specification is **authoritative**
- If implementation or plans conflict with the spec, the spec wins
- Changing the spec requires explicit user approval
- Present sections in logical batches to maintain flow
- Stop at major decision points (typically 2-3 checkpoints total)
- Do NOT silently modify previously approved sections
- Batch questions together - ask multiple at once when possible
- **CRITICAL: Show ALL content before writing to file - nothing gets saved without being presented to the user first**
