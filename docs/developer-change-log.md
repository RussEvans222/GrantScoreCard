# Developer Change Log

## March 12, 2026

### AI Framework Review Engine
A new service layer was added to support AI-based framework analysis using Salesforce Prompt Builder.

Key classes:
- `EvaluationFrameworkReviewService`
- `EvaluationFrameworkPromptInvoker`
- `EvaluationFrameworkTemplateUpdater`

What it does:
- invokes the `EvaluationFrameworkReview` prompt template
- parses structured JSON from the AI response
- optionally updates evaluation template framework metrics
- optionally applies criteria library action suggestions

This architecture keeps AI orchestration in Apex services so LWCs can call a single method and render a clean, typed response.

### Criteria Library Workspace Improvements
The Criteria Library workspace was expanded to give admins more practical governance context.

New visibility includes:
- criterion usage summaries
- template usage mappings
- recent application evaluations connected to selected criteria

This makes it easier to understand how criterion changes affect real evaluation activity.

### Developer Debugging Improvements
Developer-oriented logging, UI guidance, and architecture documentation were improved to make the system easier to learn and maintain.

Highlights:
- clearer service boundaries in Apex
- better explanation of Apex-to-LWC response flow
- improved workspace help text for usage filtering and troubleshooting
