# OmniStudio Framework Standard

This document defines the canonical development standards for all OmniStudio components in the GrantScoreCard project.

All new OmniScripts, Integration Procedures, DataRaptors, and AI integrations MUST follow these standards unless an explicit exception is documented in the pull request.

This framework acts as the primary contributor reference for OmniStudio development within this repository.

Related documentation:
- `docs/design/ai-grantscorecard-visual-style-guide.md`
- `docs/architecture/omnistudio-intake-contract.md`
- `docs/architecture/ai-invocation-pattern.md`

If conflicts occur, this framework governs new work unless explicitly overridden.

## 1. Project Philosophy

OmniStudio is the required implementation framework for external intake experiences.

Architecture chain:
`Experience Cloud → OmniScript → Integration Procedure → DataRaptor → Apex Gateway → Prompt Builder`

Flow Builder MUST NOT be used for intake unless an explicit architecture exception is documented.

## 2. OmniScript UI Standards

Discovery screens MUST resemble a modern AI prompt interface.

Required characteristics:
- centered card layout
- large whitespace
- strong heading hierarchy
- large textarea prompt field
- minimal form inputs
- single primary action button

Textarea defaults:
- `rows = 14–16`
- `width = 100%`

Spacing utilities should include:
- `slds-p-around_large`
- `slds-m-bottom_medium`
- `slds-m-top_large`

Anti-pattern:
Traditional multi-field form layouts on discovery screens are not allowed.

## 3. Card Layout Pattern

Standard discovery layout structure:
`Card Container -> Title -> Subtitle -> Large Textarea -> Primary Action Button`

This pattern MUST be used for AI discovery screens.

## 4. OmniScript Naming Conventions

OmniScript:
- `GrantIntake_<Subtype>_<Language>_<Version>`
- Example: `GrantIntake_MVP_English_1`

Integration Procedures:
- `GrantIntake_<Action>`
- Example: `GrantIntake_AnalyzeProject`

DataRaptors:
- `DRX<EntityPurpose>`
- Example: `DRXFundingOpportunitySearch`
- No underscores should appear in DataRaptor names.

Apex Gateway:
- `GrantIntakeOrchestrationGateway`

Prompt Templates:
- `Grant_<Purpose>`
- Example: `Grant_Project_Funding_Analysis`

## 5. DataRaptor Standards

DataRaptors must only reference fields that exist in the Salesforce schema.

Example FundingOpportunity fields:
- `Id`
- `Name`
- `ProgramArea`
- `EligibilitySummary`
- `MaxAwardAmount`
- `OpenDate`
- `CloseDate`

Speculative fields are not allowed.

## 6. Integration Procedure Standards

Integration Procedures act only as orchestration layers.

Responsibilities:
- accept OmniScript input
- transform request payloads
- call DataRaptors
- invoke Apex gateway for AI
- return structured JSON response

Business logic MUST NOT be implemented inside Integration Procedures.

## 7. AI Invocation Pattern

Canonical AI architecture:
`OmniScript -> Integration Procedure -> Apex Gateway -> Prompt Builder Template -> JSON response returned to OmniScript`

Prompt logic MUST exist inside Prompt Builder templates.

Apex classes should only orchestrate invocation.

Required JSON response contract:

```json
{
  "summary": "",
  "recommendedFundingTypes": [],
  "keywords": [],
  "confidenceScore": 0
}
```

## 8. OmniScript Result Rendering

Result steps should use Repeat Blocks bound to:
- `context.fundingOpportunities`

Displayed fields should include:
- `Name`
- `ProgramArea`
- `EligibilitySummary`
- `MaxAwardAmount`
- `OpenDate`
- `CloseDate`

Results should appear as simple card layouts.

## 9. Experience Cloud Integration

OmniScripts should be embedded in Experience Cloud pages using:
- `runtime_omnistudio:omniscript`

Required configuration parameters:
- `Type`
- `Subtype`
- `Language`
- `Version`

OmniScripts must support guest users when appropriate.

## 10. Export and Deployment

After OmniStudio changes are made in the org, artifacts must be exported with:

```bash
./scripts/export_omnistudio.sh GRANTS vlocity-job.yaml
```

Expected artifact locations:
- `datapacks/OmniScript`
- `datapacks/IntegrationProcedure`
- `datapacks/DataRaptor`

## 11. Future UI Enhancements

Potential upgrades:
- FlexCard funding opportunity cards
- AI ranking of funding opportunities
- semantic search improvements
- AI keyword weighting

## 12. OmniScript Layout Rules

OmniScript discovery screens MUST render using a centered wide container.

Standard wrapper pattern:
- `slds-grid`
- `slds-grid_align-center`
- `slds-p-around_x-large`

Inner container rules:
- `max-width: 1080px`
- `width: 100%`

The discovery card must visually occupy a large portion of the viewport.

Textarea elements must appear as a large AI prompt input.

Recommended configuration:
- `rows = 16`
- `width = 100%`

Card styling guidelines:
- rounded corners
- large internal padding
- clear typography hierarchy

The layout should resemble a modern AI interface similar to ChatGPT style prompt cards.

## 13. Repository Structure

```text
datapacks/
  OmniScript/
  IntegrationProcedure/
  DataRaptor/

force-app/main/default/
  omniScripts/
  omniIntegrationProcedures/
  omniDataTransforms/

docs/
  architecture/
  design/
  standards/
```

## 14. OmniStudio Development Workflow

Standard lifecycle:
1. Develop OmniScript, IP, and DataRaptor inside the GRANTS org.
2. Validate runtime behavior in Experience Cloud.
3. Export artifacts:
   `./scripts/export_omnistudio.sh GRANTS vlocity-job.yaml`
4. Commit exported DataPacks.
5. Push to repository.
