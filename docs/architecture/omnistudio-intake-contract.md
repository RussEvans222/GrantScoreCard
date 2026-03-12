# OmniStudio Intake Contract

## Purpose
This document defines the contract boundary for the future grant intake build:

`OmniScript -> Integration Procedure -> DataRaptor -> Apex services`

The new Apex gateway class is:

- `GrantIntakeOrchestrationGateway`

It exists to give OmniStudio a stable interface while backend services continue to evolve.

For AI-specific orchestration standards, see:
- `docs/architecture/ai-invocation-pattern.md`

## Layer Responsibilities

## OmniScript (UI Flow)
- Collect user input in guided steps.
- Handle screen transitions and user validation messages.
- Send request payloads to Integration Procedures.

## Integration Procedure (Orchestration)
- Coordinate multi-step operations.
- Call DataRaptors for CRUD mapping.
- Call Apex only for edge cases or advanced orchestration.
- Return one normalized response back to OmniScript.

## DataRaptor (CRUD Mapping)
- Read and write Salesforce records with declarative mappings.
- Handle field-level transformations where possible.
- Keep object-level mapping logic out of OmniScript.

## Apex (Edge Logic Only)
- Provide reusable contracts and advanced orchestration hooks.
- Enforce security and shared behavior when declarative tools are not enough.
- Avoid UI-specific behavior.

## Gateway Contract Methods

`GrantIntakeOrchestrationGateway` currently defines these method contracts:

- `getFundingFinderResults(searchText)`
- `analyzeProjectForFunding(searchText)`
- `saveDraftApplication(applicationPayload)`
- `submitApplication(applicationPayload)`
- `initializeEvaluation(applicationId)`

Current implementation status:
- `getFundingFinderResults` delegates to `PSGWorkspaceReadService` and returns normalized finder rows.
- `saveDraftApplication` now parses canonical intake JSON and saves `ApplicationForm` draft state.
- `submitApplication` now marks `ApplicationForm` submission state.
- `initializeEvaluation` now creates `ApplicationFormEvaluation` using the linked funding opportunity template.
- `analyzeProjectForFunding` returns AI discovery contract fields for intake (`aiSummary`, `recommendedFundingTypes`, `keywords`, `confidenceScore`).

## Canonical DTO Contracts

Request DTOs:
- `FundingFinderRequest`
- `GrantApplicationDraftRequest`
- `GrantSubmissionRequest`
- `EvaluationInitializationRequest`

Response DTOs:
- `FundingFinderResponse`
- `AnalyzeProjectResponse`
- `GrantApplicationDraftResponse`
- `GrantSubmissionResponse`
- `EvaluationInitializationResponse`

All DTOs are JSON-friendly and intended for OmniStudio payload transport.

## AI Discovery Intake Screen

Implemented OmniStudio-first discovery artifacts:

- OmniScript: `GrantIntake_MVP_English`
  - Type: `GrantIntake`
  - Subtype: `MVP`
  - Language: `English`
  - Version: `1`
  - Active: `true`
  - Web component enabled: `true`
  - OmniScript embeddable: `true`
- Integration Procedure: `GrantIntake_AnalyzeProject`
  - Type: `GrantIntake`
  - Subtype: `AnalyzeProject`
  - Language: `English`
- DataRaptor: `DRXFundingOpportunitySearch`
  - Extracts active `FundingOpportunity` rows for recommendation context.

UI structure in `Step_ProjectDiscovery`:

- `Text Block`: headline + subtitle with centered SaaS card layout using the repository visual palette.
- `Text Area` (`Inp_ProjectDescription`): long-form project input.
- `Integration Procedure Action` (`AnalyzeProject`): executes `GrantIntake_AnalyzeProject`.

Response values are written into OmniScript JSON under `context`:

- `context.aiSummary`
- `context.recommendedFundingTypes`
- `context.keywords`
- `context.confidenceScore`

`Step_FundingFinder` consumes these values for the next-screen recommendation experience.

Experience Cloud compatibility:

- Deployable via Experience Builder OmniScript component and `<omnistudio-omniscript>`.
- Intended config on site page:
  - Type = `GrantIntake`
  - Subtype = `MVP`
  - Language = `English`
- Compatible with guest and authenticated users subject to org sharing/FLS settings.

## Experience Cloud Intake UI

Portal entry:
- Experience site bundle: `Grantmaking1`
- Route: `grant-discovery` (`custom-grant-discovery`)
- Page label: `Grant Discovery`
- Runtime component: `runtime_omnistudio:omniscript`
  - `type = GrantIntake`
  - `subType = MVP`
  - `language = English`
  - `version = 1`

OmniScript flow:
- `Step_ProjectDiscovery`
  - Centered discovery card using OmniScript Text Block HTML and style-guide palette.
  - Text Area input (`Inp_ProjectDescription`) for long-form project description.
  - Integration Procedure action button (`Analyze Project`) invoking `GrantIntake_AnalyzeProject`.
- `Step_FundingFinder`
  - Text Block summary bound to `context.aiSummary` and `context.recommendedFundingTypes`.
  - Repeat Block (`fundingOpportunities`) rendering one result card per recommendation.
  - Per-card CTA (`View Opportunity`) as a native OmniScript Navigate Action.

AI analysis:
- Integration Procedure `GrantIntake_AnalyzeProject` transforms input, calls:
  - Apex Remote Action: `GrantIntakeOrchestrationGateway.analyzeProjectForFunding`
  - DataRaptor Extract Action: `DRXFundingOpportunitySearch`
- Response shape now includes:
  - `aiSummary`
  - `recommendedFundingTypes`
  - `fundingOpportunities[]`
  - `context.aiSummary`, `context.recommendedFundingTypes`, `context.keywords`

Funding recommendation rendering:
- Result cards show:
  - `Name`
  - `ProgramArea`
  - `EligibilitySummary`
  - `MaxAwardAmount`
  - `OpenDate`
  - `CloseDate`
- UI remains OmniStudio-native (Text Block, Text Area, Button/Navigate Action, Repeat Block).
- No Flow Builder logic and no additional LWCs are introduced.

## Sequence: Funding Finder

```text
User
 -> OmniScript Step_ProjectDiscovery (native OmniStudio elements)
 -> Integration Procedure Action (GrantIntake_AnalyzeProject)
 -> Integration Procedure Set Values (context.projectDescription -> searchText)
 -> Integration Procedure Remote Action
 -> GrantIntakeOrchestrationGateway.analyzeProjectForFunding(searchText)
 <- AnalyzeProjectResponse (aiSummary, recommendedFundingTypes, keywords, confidenceScore)
 <- Integration Procedure response
 <- OmniScript writes context.aiSummary/context.recommendedFundingTypes/context.keywords
 -> OmniScript Step_FundingFinder renders recommendation context
```

## OmniStudio Wiring Standard

Use this contract path for intake discovery and recommendation:

```text
OmniScript
  -> Integration Procedure
    -> GrantIntakeOrchestrationGateway
      -> Service Layer
```

Step wiring for the first intake step:
- `Step_ProjectDiscovery`
  - Elements: `Txt_ProjectDiscoveryIntro`, `Inp_ProjectDescription`, `AnalyzeProject`
  - Output input: `%Inp_ProjectDescription%` sent as `context.projectDescription`
  - Next action: execute `GrantIntake_AnalyzeProject`, then navigate to `Step_FundingFinder`.

## OmniStudio Artifact Source Control

OmniStudio assets for intake should be managed with Vlocity DataPacks using this path:

`Vlocity DataPacks -> Git -> Org`

Source control pattern:
- Export OmniStudio artifacts (OmniScript, Integration Procedure, DataRaptor, FlexCard) to DataPacks.
- Commit DataPack artifacts to this repository.
- Deploy/promote artifacts to target orgs from Git-managed DataPacks.
- Keep runtime orchestration contracts in Apex/Gateway versioned alongside DataPacks.

## Sequence: Program Selection + Draft Save

```text
User selects program and enters draft data
 -> OmniScript
 -> Integration Procedure (draft orchestration)
 -> DataRaptor Load (ApplicationForm draft fields)
 -> GrantIntakeOrchestrationGateway.saveDraftApplication(...)
 <- GrantApplicationDraftResponse
 <- OmniScript shows "Draft saved"
```

## Sequence: Submission

```text
User clicks Submit
 -> OmniScript
 -> Integration Procedure (submission orchestration)
 -> DataRaptor Load (final application values)
 -> GrantIntakeOrchestrationGateway.submitApplication(...)
 <- GrantSubmissionResponse
 <- OmniScript shows submission confirmation
```

## Sequence: Evaluation Initialization

```text
Submission confirmed
 -> Integration Procedure
 -> GrantIntakeOrchestrationGateway.initializeEvaluation(applicationId)
 -> (future) evaluation setup services
 <- EvaluationInitializationResponse
 <- OmniScript displays next-step status
```

## Security Notes
- Existing PR1 protections remain in service layer paths:
  - dynamic object access checks
  - `Security.stripInaccessible`
  - DTO mapping from sanitized records only
- Gateway methods should continue delegating to secured services.
