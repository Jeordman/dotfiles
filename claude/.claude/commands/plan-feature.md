# /plan-feature

You are helping the user plan **how to implement a feature** in this codebase.

This command produces a **non-authoritative implementation plan** that translates intent into concrete execution steps.

It may be used:
- With an existing feature spec
- OR without a spec (assumption-based planning)

---

## Pre-flight Check

1. Look for `{feature_name}.spec.md`

2. If a spec exists:
   - Treat it as **authoritative**
   - Reference relevant spec sections throughout the plan
   - Do NOT contradict or redefine feature intent

3. If no spec exists:
   - Proceed without a spec
   - Explicitly list assumptions
   - Clearly mark the plan as **non-authoritative**

---

## Process

1. **Understand requirements**
   - Batch all clarifying questions upfront (ask multiple at once)
   - Identify scope, goals, and constraints
   - Surface critical ambiguities early, especially if no spec exists

2. **Explore the codebase**
   - Read relevant files and components
   - Identify existing patterns and architecture
   - Find similar features for reference
   - Note which files will be affected

3. **Build the plan in batches**
   - Present related sections together (e.g., Context + Assumptions + Files)
   - STOP at major decision points, not after every detail
   - Balance speed with user control - typically 2-3 checkpoints total
   - Allow iteration on any section
   - Make reasonable technical decisions, but surface architectural choices
   - **CRITICAL: Show ALL content before writing to file - nothing gets saved without being presented to the user first**

---

## Plan Sections (Non-Authoritative)

### Context
- Summary of the feature
- Constraints and goals
- References the spec if one exists

---

### Assumptions (Required if no spec exists)
- Behaviors being assumed
- Areas of uncertainty
- Risks caused by missing specification

---

### Files to Create
- New files with paths and descriptions

---

### Files to Modify
- Existing files with line numbers
- What will change and why

---

### Component / System Architecture
- How the implementation will be structured
- Why this approach fits the existing codebase

---

### State Management
- What state is added or changed
- Where it lives
- How it flows through the system

---

### API / Data Changes
- Backend endpoints
- Data models
- Migrations or schema changes (if any)

---

### Testing Strategy
- What needs to be tested
- How correctness will be validated
- Unit, integration, and manual testing as appropriate

---

### Implementation Steps (Detailed & Actionable)

This section must be extremely concrete.
Assume a teammate will follow these steps **without additional context**.

For each step:

#### Step X: [Descriptive Title]

**What to do:**
- Specific actions with file paths and line numbers
- References to existing patterns or examples

**Code changes:**
```ts
// Show exact structure, key logic, and imports
// Enough detail that a teammate could write the code confidently
