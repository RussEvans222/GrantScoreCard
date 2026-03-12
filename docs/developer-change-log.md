# Developer Change Log

## Latest Update News (March 12, 2026)

### OmniStudio Intake Completion Progress
- Aligned Grant Intake analysis path to the existing Prompt Builder template:
  - label: `Grant Project Funding Analysis`
  - developer name: `Grant_Project_Funding_Analysis`
- Standardized response mapping into OmniScript `context.*` nodes:
  - `context.aiSummary`
  - `context.recommendedFundingTypes`
  - `context.keywords`
  - `context.confidenceScore`
  - `context.fundingOpportunities[]`
- Extended Experience Cloud-facing intake presentation with scoped gradient/button/card styling while preserving OmniScript structure and bindings.
- Added full-screen wrapper LWC `grantIntakeFullPage` for flexible page composition and future side-panel expansion.

### Deployment and Sync
- Full source deployment to org alias `GRANTS` completed successfully:
  - Deploy ID: `0AfHp00003ni0kJKAQ`
  - Status: `Succeeded`
  - Components deployed: `566`
- Wrapper-only deployment validation also completed:
  - Deploy ID: `0AfHp00003ni0k4KAA`
  - Status: `Succeeded`

### Feature Walkthrough (Today’s OmniStudio Changes)
1. User opens Experience Cloud Grant Discovery page.
2. `Step_ProjectDiscovery` captures `context.projectDescription`.
3. Analyze action runs `GrantIntake_AnalyzeProject`.
4. IP calls `GrantIntakeOrchestrationGateway.analyzeProject`.
5. Apex invokes Prompt Builder template `Grant_Project_Funding_Analysis`.
6. Structured JSON response is normalized into `context.*`.
7. OmniScript transitions to results rendering step and displays recommended funding opportunities.

## March 12, 2026

### Major Enhancements
- Added the **Evaluation Criteria Manager** app shell with admin workspaces for criteria governance, template usage, and AI review operations.
- Integrated **Evaluation Framework Review** AI orchestration and structured results rendering in Criteria Insights.
- Added **inline editing for template display names** with dynamic field selection and FLS-aware save behavior.
- Enabled **AI evidence storage** on criterion score records via `Evaluation_Criterion_Score__c.AI_Evidence__c` and updated permission access.

### AI Feature Expansion
- Added multi-workflow AI coverage across the grant evaluation lifecycle.
- Prompt template support now includes:
  - `EvaluationFrameworkReview`
  - `ETDisplayName`
  - scorecard suggestion prompts (`AFE_Criterion_Scoring_Suggestion`, `AFE_Scorecard`)
- The platform now demonstrates framework analysis, template naming assistance, and reviewer scoring guidance as connected AI-assisted workflows.

### Evaluation Template Display Name Generator
A new AI prompt template was introduced to automatically generate meaningful display names for evaluation templates.

Prompt API Name:
- `ETDisplayName`

Input Objects:
- `Evaluation_Template__c`
- `Evaluation_Template_Criterion__c` (related snapshot)

Output:
- Short human-readable template title (target: 3-5 words)

Why this matters:
- Helps administrators quickly identify rubric purpose when many templates exist.
- Improves template dropdown usability across manager workspaces and insights screens.

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
