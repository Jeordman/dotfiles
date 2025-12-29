# Feature Planning Command

You are helping the user plan and document a large feature interactively before implementation.

## Process:

1. **Use TodoWrite to track the planning process**:
   - Explore relevant codebase areas
   - Analyze existing patterns and architecture
   - Create comprehensive feature plan
   - Save plan as markdown file

2. **Understand the feature requirements**:
   - Ask clarifying questions if needed
   - Identify the scope and goals
   - Understand affected components/files
   - Note any constraints or requirements

3. **Explore the codebase**:
   - Read relevant existing components for patterns
   - Understand current architecture
   - Identify files that will be affected
   - Find similar features for reference

4. **Present findings one section at a time**:
   - Show each analysis/recommendation
   - Wait for user approval before adding to markdown
   - Allow user to request changes or adjustments
   - Build the document incrementally based on feedback

5. **Create the feature plan document** with these sections (present each for approval):
   - **Overview**: Feature description and goals
   - **Files to Create**: New files needed with descriptions
   - **Files to Modify**: Existing files to change with what changes
   - **Component Architecture**: How components will be structured
   - **State Management**: What state changes are needed
   - **API/Data Changes**: Backend or data requirements
   - **Testing Strategy**: What needs to be tested
   - **Implementation Steps**: DETAILED step-by-step execution plan that teammates can follow exactly
     - Each step should have: What to do, Code changes (with examples), Why, and Acceptance criteria
     - Include file references and line numbers
     - Show code structure examples for each step
     - Make it actionable - anyone should be able to implement following these steps
   - **Potential Issues**: Risks with impact, mitigation, and workarounds
   - **Open Questions**: Items needing clarification with context and options

6. **Interactive approval process**:
   - Present each section individually
   - Wait for user to approve, modify, or skip
   - Only add approved content to the markdown file
   - Allow user to iterate on any section

## Important Guidelines:

- **DO NOT implement any code** - this is planning only
- **DO explore the codebase** to understand existing patterns
- **DO ask questions** if requirements are unclear
- **DO present findings incrementally** for approval
- **DO reference specific files and line numbers** when relevant
- **DO consider existing architecture** and patterns
- **DO NOT rush** - take time to analyze thoroughly

## Output Format:

The final markdown file should be named: `{feature_name}_plan.md`

Structure:
```markdown
# {Feature Name} Implementation Plan

## Overview
[Feature description, goals, and scope]

## Files to Create
- `path/to/NewComponent/index.tsx` - Description
- `path/to/NewHook/useFeature.ts` - Description

## Files to Modify
- `path/to/ExistingComponent/index.tsx:123` - What changes and why
- `src/store/useGlobalStore.ts:45` - What state to add

## Component Architecture
[How components will be organized and structured]

## State Management
[What state is needed, where it lives, how it flows]

## API/Data Requirements
[Backend endpoints, data models, etc.]

## Testing Strategy
[What needs testing and how]

## Implementation Steps

This section should be VERY detailed and actionable - teammates should be able to follow these steps exactly.

### Step 1: [First Major Task]
**What to do:**
- Specific action with file references
- Example: Create `src/components/FeatureName/index.tsx` based on pattern in `src/components/ExistingFeature/index.tsx:45-120`

**Code changes:**
```tsx
// Describe exactly what code to write or modify
// Include imports, structure, and key logic
```

**Why:**
- Explanation of why this step comes first
- Dependencies or prerequisites

**Acceptance criteria:**
- How to know this step is complete
- What should work at this point

---

### Step 2: [Second Major Task]
**What to do:**
- Specific actions...

**Code changes:**
```tsx
// Exact code structure needed
```

**Why:**
- Reasoning...

**Acceptance criteria:**
- Completion criteria...

---

[Continue for all steps - each step should be independently executable by a teammate]

### Final Step: Testing & Verification
**What to do:**
- Run specific tests
- Manual testing checklist
- Verify all acceptance criteria

## Potential Issues
- **Issue**: Specific risk or concern
  - **Impact**: What could go wrong
  - **Mitigation**: How to prevent or handle it
  - **Workaround**: Alternative approach if needed

## Open Questions
- **Question**: Specific thing that needs clarification
  - **Why it matters**: Impact on implementation
  - **Options**: Possible answers/approaches
  - **Decision needed by**: Who should answer this
```

## Usage:

The user will say something like:
- "I want to plan a new feature for [description]"
- "Help me think through implementing [feature]"
- "Let's plan out [feature] before building it"

Then follow the process above to interactively build the plan.
