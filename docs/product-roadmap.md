## 1. Project Roadmap Overview

This document defines a forward-looking product + engineering roadmap for GrantScoreCard, aligned to Spring '26 Salesforce platform direction and an OmniStudio-first delivery model.

The canonical evaluation data model remains unchanged:

- `FundingOpportunity -> Evaluation_Template__c -> Evaluation_Template_Criterion__c`
- `ApplicationForm -> ApplicationFormEvaluation -> Evaluation_Criterion_Score__c`

Hard guardrail:
- AI scoring remains advisory-only and must never auto-populate `Evaluation_Criterion_Score__c`.

Roadmap horizon:
- Near-term delivery focus across the next two release waves.

## 2. Platform Architecture Summary

Target stack:

- `Experience Cloud -> OmniScripts/FlexCards -> Integration Procedures -> Data Mappers -> Salesforce Data Model`
- AI layer: `Integration Procedures -> Prompt Builder -> Agentforce`

Architecture rules:

- Integration Procedures own all server-side business logic.
- OmniScripts are orchestration and UI only.
- FlexCards consume Integration Procedure responses but do not contain business rules.

Spring '26 alignment:

- Standard OmniStudio Runtime compatibility for all new assets.
- LWR + OmniStudio adoption for Experience Cloud performance and portability.
- Agentforce action-ready IP/Data Mapper design for reusable AI operations.
- Agent Script orchestration potential for multi-step grant workflows.
- LWC enhancements + GraphQL mutation support for targeted custom interactions.
- ARIA accessibility + stronger OLS/FLS enforcement testing as release gates.

## 3. Roadmap Feature Backlog

| Category | Feature | Description | Technical Approach | Complexity | Priority |
|---|---|---|---|---|---|
| OmniScript Development | Grant Discovery Wizard | Guided intake flow for project discovery and funding matching intake. | Expand `GrantIntake_MVP_English_1` into modular discovery steps with context envelope contracts. | L | P0 |
| OmniScript Development | Evaluation Template Builder | Admin wizard to compose evaluation templates with reusable criterion groups. | OmniScript admin flow backed by IP orchestration and Data Mapper persistence. | L | P1 |
| OmniScript Development | Criterion Library Manager | OmniScript-based criterion CRUD and taxonomy management for admins. | Admin OmniScript + IP + Data Mapper layer with list/detail step patterns. | M | P1 |
| OmniScript Development | Reviewer Assignment Tool | Guided assignment flow from application context to reviewer work queue. | OmniScript orchestration calling `IP_AssignReviewers` and assignment validation actions. | M | P1 |
| OmniScript Development | Reviewer Scorecard UI | OmniScript-first reviewer capture experience for structured criterion comments. | OmniScript components bound to scorecard DTOs; no direct scoring automation writes by AI. | L | P2 |
| FlexCard UI Enhancements | Funding Recommendation FlexCard | Visual cards for AI-ranked matching opportunities with relevance signals. | FlexCard fed by `IP_FindFundingOpportunities` response and OmniScript context. | M | P0 |
| FlexCard UI Enhancements | Application Summary Cards | Compact cards for applicant progress, deadline, and submission state. | FlexCard data source from IP response node normalization. | S | P1 |
| FlexCard UI Enhancements | Evaluation Dashboard Cards | Program-level snapshot cards for evaluator workload and cycle status. | FlexCards using aggregated IP endpoints and lightweight Data Mapper extracts. | M | P2 |
| Integration Procedures | IP_AnalyzeProjectFunding | Analyze project text and produce AI summary + recommendation payload. | Transform input -> Prompt Builder via gateway -> normalized context output. | M | P0 |
| Integration Procedures | IP_FindFundingOpportunities | Retrieve active opportunities and enrich with eligibility metadata. | Data Mapper extract + optional ranking transform + normalized response contract. | M | P0 |
| Integration Procedures | IP_CreateApplicationForm | Draft/save/submit orchestration for application intake records. | Canonical request contract, Data Mapper load, status transitions, and validation mapping. | M | P0 |
| Integration Procedures | IP_AssignReviewers | Operational API for reviewer assignment and workload balancing inputs. | Assignment orchestration with security checks and deterministic response payload. | M | P1 |
| Data Mapper Context Layer | DR_ApplicantContext | Standard applicant context extract for AI and eligibility checks. | Data Mapper extract with field allowlist and OLS/FLS-compliant mappings. | S | P1 |
| Data Mapper Context Layer | DR_FundingOpportunityContext | Grounding extract for funding attributes, windows, and constraints. | Data Mapper extract with normalized field aliases and active-status filters. | S | P1 |
| Data Mapper Context Layer | DR_EvaluationTemplateContext | Rubric context extract for reviewer prep and AI guidance prompts. | Data Mapper extract across template + criterion relationships with ordered output. | M | P1 |
| Agentforce / AI Enhancements | AI project summarization | Summarize applicant project intent and key signals for discovery. | Prompt Builder template called through IP gateway with strict JSON contract. | M | P0 |
| Agentforce / AI Enhancements | AI eligibility scoring | Advisory eligibility confidence for matched opportunities. | Agentforce action invoking IP + Data Mapper context; output marked advisory-only. | M | P1 |
| Agentforce / AI Enhancements | AI grant recommendation engine | Recommend top opportunities using project, criteria, and timeline signals. | Composite action: analyze IP + opportunity finder IP + ranking transform. | L | P1 |
| Agentforce / AI Enhancements | AI reviewer scoring assistance | Provide rubric-aligned review hints and rationale prompts for reviewers. | Reviewer-side advisory action using template context and prior scoring evidence. | L | P2 |
| Internal Grant Operations Tools | Program Operations Console | Central operations view for intake health, assignment queues, and bottlenecks. | LWR page with FlexCards and action-launch OmniScripts. | L | P2 |
| Internal Grant Operations Tools | Eligibility Rules Registry | Admin-facing rule dictionary for auditable eligibility logic references. | Metadata-backed registry UI with read-only trace links from IP decisions. | M | P2 |
| Evaluation and Reviewer Experience | Reviewer Prep Packet | Auto-generated review packet with rubric, summary, and key risk flags. | Agentforce action + Data Mapper context bundle rendered in FlexCard/LWC panel. | M | P1 |
| Evaluation and Reviewer Experience | Calibration Assistant | Compare reviewer variance and surface rubric interpretation drift. | Aggregation IP + analytics view; advisory insights only. | L | P2 |
| Experience Cloud UX Enhancements | LWR Intake Landing Experience | LWR-native discovery landing with optimized performance and CLS stability. | Rebuild entry page composition in LWR-compatible Experience Cloud templates. | M | P1 |
| Experience Cloud UX Enhancements | Guided Resume + Draft Continuity | Session-safe resume patterns across guest/auth transitions. | Save-token orchestration contract + state hydration guards in OmniScript. | M | P1 |
| DevOps / Packaging Improvements | Standard Runtime Readiness Pipeline | Validate all OmniStudio assets for standard runtime portability in CI. | CLI validation jobs and metadata scanning for managed package dependencies. | M | P0 |
| DevOps / Packaging Improvements | OmniStudio Export/Import Stability | Harden DataPack export/import consistency across environments. | Pipeline job using `./scripts/export_omnistudio.sh GRANTS vlocity-job.yaml` and diff gates. | M | P1 |
| DevOps / Packaging Improvements | Security Enforcement Regression Suite | Catch OLS/FLS regressions under stricter OmniStudio enforcement. | Automated integration tests with profile/permission permutations. | L | P1 |
| Future Innovation Ideas | Grant discovery copilot | Conversational assistant to guide applicants to best-fit programs. | Agent Script orchestrating discovery prompts + IP action calls + explainability notes. | L | P2 |
| Future Innovation Ideas | eligibility triage assistant | Early-stage triage assistant for pass/fail and missing-evidence guidance. | Agent Script with Data Mapper grounding and deterministic rule overlays. | M | P2 |
| Future Innovation Ideas | reviewer prep assistant | AI helper that assembles rubric context and prior-cycle insights for reviewers. | Agent Script orchestrating template context actions and reviewer prep packet generation. | M | P2 |
| Future Innovation Ideas | grant portfolio insights assistant | Portfolio-level assistant for funding mix, risk clusters, and trend insights. | Agent Script + analytics IPs with summary narratives and drill-down action links. | XL | P2 |

## 4. Recommended Next 5 Features

1. Standard Runtime stabilization of `GrantIntake_MVP_English_1`  
Outcome: locks cross-org portability and baseline runtime reliability for intake.  
Dependency note: requires dependency audit and Experience Cloud runtime validation matrix.

2. `IP_AnalyzeProjectFunding` + Prompt Builder integration  
Outcome: establishes canonical AI analysis contract for discovery and downstream reuse.  
Dependency note: requires stable gateway mapping and strict JSON schema validation.

3. Funding recommendation FlexCard results layer  
Outcome: delivers applicant-facing recommendation cards with explainable relevance.  
Dependency note: depends on normalized output from `IP_FindFundingOpportunities`.

4. `IP_CreateApplicationForm` orchestration contract  
Outcome: standardizes draft/save/submit semantics for application creation workflows.  
Dependency note: depends on field-level security tests and data mapper write mappings.

5. Agentforce action packaging of discovery Integration Procedures  
Outcome: unlocks reusable AI actions for copilot and assisted intake scenarios.  
Dependency note: depends on action-safe contracts, guardrails, and observability conventions.

## 5. Agentforce Opportunities

| Opportunity | Business Value | Required OmniStudio Artifacts | Agentforce Action Interface | Dependencies / Risks |
|---|---|---|---|---|
| grant discovery copilot | Increases applicant completion rates and better-fit program selection. | `GrantIntake_MVP_English_1`, `IP_AnalyzeProjectFunding`, `IP_FindFundingOpportunities`, `DR_ApplicantContext`, `DR_FundingOpportunityContext` | `analyzeProjectFunding`, `findFundingOpportunities`, `summarizeDiscoveryContext` | Prompt drift risk; require response schema validation and advisory language constraints. |
| eligibility triage assistant | Reduces manual triage effort and accelerates routing decisions. | `IP_FindFundingOpportunities`, eligibility transforms, `DR_FundingOpportunityContext`, `DR_ApplicantContext` | `evaluateEligibilitySignals`, `listEligibilityGaps` | False positives if context incomplete; enforce confidence thresholds and human review checkpoints. |
| reviewer prep assistant | Improves reviewer consistency and reduces onboarding time. | `IP_AssignReviewers`, reviewer prep IP, `DR_EvaluationTemplateContext`, reviewer FlexCards | `prepareReviewerPacket`, `summarizeApplicationForReview` | Must remain advisory-only; no automated score writes to `Evaluation_Criterion_Score__c`. |
| grant portfolio analytics assistant | Improves portfolio planning, risk detection, and leadership reporting. | Analytics IPs, dashboard FlexCards, portfolio context Data Mapper extracts | `summarizePortfolioHealth`, `detectPortfolioRiskPatterns` | Data quality variance across programs; requires governance and metric standardization. |

## 6. Standard Runtime Migration Considerations

Migration checklist:

- [ ] Complete managed package dependency audit for OmniStudio assets and runtime references.
- [ ] Enforce metadata portability standards for OmniScript, FlexCard, IP, and Data Mapper artifacts.
- [ ] Normalize Integration Procedure naming and response envelope conventions for reuse.
- [ ] Validate LWR Experience Cloud rendering/performance for intake and recommendation pages.
- [ ] Execute accessibility validation against ARIA, focus order, keyboard navigation, and contrast.
- [ ] Implement security enforcement testing for stricter OLS/FLS checks in OmniStudio runtime.
- [ ] Stabilize CI/CD export/import with deterministic artifact checks.

CI command reference:

```bash
./scripts/export_omnistudio.sh GRANTS vlocity-job.yaml
```

End-of-document summary:

- Total roadmap features generated: **32**
- Recommended next five priorities:
  1. Standard Runtime stabilization of `GrantIntake_MVP_English_1`
  2. `IP_AnalyzeProjectFunding` + Prompt Builder integration
  3. Funding recommendation FlexCard results layer
  4. `IP_CreateApplicationForm` orchestration contract
  5. Agentforce action packaging of discovery Integration Procedures
- Major AI opportunities discovered:
  - Applicant grant discovery copilot
  - Eligibility triage assistant
  - Reviewer prep assistant
  - Grant portfolio analytics assistant
