# AI Invocation Pattern (Prompt Builder)

This document defines the standing architecture rule for AI integration in GrantScoreCard.

## Core Rules

1. Prompt Builder templates are the default mechanism for AI interaction across the platform.

2. AI prompts must not be embedded directly in Apex, LWC, or Flow logic unless explicitly required for prototyping.

3. Prompt invocation paths should follow the standard architecture:

```text
UI / Flow / OmniScript
    ↓
Gateway
    ↓
Service Layer
    ↓
Prompt Builder Template
    ↓
AI Response Handling
```

4. Prompt templates must remain configurable in Salesforce metadata so they can evolve without requiring code changes.

5. The system should support invoking AI during multiple workflow phases, including:
- Project discovery / funding matching
- Application summarization
- Evaluation rubric guidance
- Reviewer scoring assistance
- Post-review insights

6. Gateway and service layers should remain the orchestration boundary for Apex-initiated AI calls.

## Apex Invocation Pattern

When AI analysis is required from Apex, Prompt Builder template invocation should be handled in the service layer.

Service layer responsibilities:
- Prepare grounding and context data for the AI request.
- Invoke the Prompt Builder template.
- Validate and normalize the AI response.
- Map the result back into application objects or workflow state.

```text
UI / Flow / OmniScript
    ↓
Gateway
    ↓
Service Layer
    ↓
Prompt Builder Template
    ↓
AI Response Handling
```

## Implementation Guidance

- Treat Prompt Builder templates as first-class integration points.
- Keep prompt text and tuning in template metadata, not code constants.
- Keep request/response shaping in gateway/service orchestration classes.
- Keep UI components focused on user interaction and rendering AI outputs.
