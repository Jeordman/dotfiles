# Generate PR Description

Generate a concise GitHub PR description in markdown format with the following structure:

1. **Description section** (< 100 words, or < 120 words if explaining complex changes): Brief explanation of what was implemented/changed and why
2. **Technical Details** (if applicable): Explanation of complicated code changes or architectural decisions
3. **Note section** (if applicable): Any dependencies, requirements, or follow-up tasks needed
4. **Testing Checklist**: 5-7 actionable test items using `- [ ]` checkbox format

## Requirements:
- Keep description under 100 words (can extend to 120 words if explaining complex technical changes)
- If code changes involve complex patterns, new architecture, or non-obvious implementations, add a Technical Details section
- Include relevant testing URLs or tools (e.g., Facebook Debugger for OG tags)
- Make checklist items specific and actionable
- Include both happy path and error/fallback scenario tests
- If external dependencies exist (API keys, translations, etc.), mention them in a **Note**

## Format:
```markdown
## Description
[Brief description of changes and their purpose - up to 120 words if complex]

## Technical Details
[Only include if there are complex patterns or architectural decisions to explain]
- [Key implementation detail or pattern used]
- [Why this approach was chosen]
- [Any tradeoffs or considerations]

**Note:** [Any dependencies or follow-up tasks, if applicable]

## Testing Checklist
- [ ] [Specific test action]
- [ ] [Test with tool/URL]
- [ ] [Error case test]
- [ ] [Visual/UI verification]
- [ ] [Integration test]
```

Analyze the current changes in the repository and generate an appropriate PR description following this format.
