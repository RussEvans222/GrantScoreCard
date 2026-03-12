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
- `saveDraftApplication(applicationPayload)`
- `submitApplication(applicationPayload)`
- `initializeEvaluation(applicationId)`

Current implementation status:
- `getFundingFinderResults` delegates to `PSGWorkspaceReadService` and returns normalized finder rows.
- `saveDraftApplication` now parses canonical intake JSON and saves `ApplicationForm` draft state.
- `submitApplication` now marks `ApplicationForm` submission state.
- `initializeEvaluation` now creates `ApplicationFormEvaluation` using the linked funding opportunity template.

## Canonical DTO Contracts

Request DTOs:
- `FundingFinderRequest`
- `GrantApplicationDraftRequest`
- `GrantSubmissionRequest`
- `EvaluationInitializationRequest`

Response DTOs:
- `FundingFinderResponse`
- `GrantApplicationDraftResponse`
- `GrantSubmissionResponse`
- `EvaluationInitializationResponse`

All DTOs are JSON-friendly and intended for OmniStudio payload transport.

## Sequence: Funding Finder

```text
User
 -> OmniScript (Funding Finder step, UI component: grantDiscoveryIntakeStep)
 -> Integration Procedure (finder orchestration)
 -> GrantIntakeOrchestrationGateway.getFundingFinderResults(...)
 -> PSGWorkspaceReadService (secure read + pagination)
 <- FundingFinderResponse
 <- Integration Procedure response
 <- OmniScript renders program options
```

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
 -> (future) evaluation setup services/flows
 <- EvaluationInitializationResponse
 <- OmniScript displays next-step status
```

## Security Notes
- Existing PR1 protections remain in service layer paths:
  - dynamic object access checks
  - `Security.stripInaccessible`
  - DTO mapping from sanitized records only
- Gateway methods should continue delegating to secured services.
