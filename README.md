# GrantScoreCard (Salesforce Grantmaking Starter Kit)

GrantScoreCard is a Salesforce DX project for a flow-first grantmaking demo:

- applicant intake in Experience Cloud
- rubric/template setup for Funding Opportunities
- reviewer assignment automation
- evaluator scorecard with AI-assisted scoring suggestions

This repo is curated so another team can deploy to a demo org and stand up the solution quickly.

## One-Click Deploy

<a href="https://githubsfdeploy.herokuapp.com?owner=RussEvans222&repo=GrantScoreCard&ref=main">
  <img alt="Deploy to Salesforce"
    src="https://raw.githubusercontent.com/afawcett/githubsfdeploy/master/deploy.png">
</a>

## Architecture Overview

```text
FundingOpportunity
  -> Evaluation_Template__c
      -> Evaluation_Template_Criterion__c
          -> (on reviewer assignment)
             ApplicationFormEvaluation
                -> Evaluation_Criterion_Score__c snapshots
```

Runtime paths:

1. **Applicant Intake**
   `FundingOpportunity.Apply Now` -> `Grant_Application_Intake_Flow` -> creates `ApplicationForm` + `ApplicationFormRelation`

2. **Rubric Setup (Admin)**
   `FundingOpportunity.Setup Evaluation Criteria` -> `Evaluation_Template_Wizard_Flow`

3. **Reviewer Assignment**
   `ApplicationForm.Assign Reviewers` -> `Assign_Reviewers_Create_Evaluations` -> creates AFEs + stage/task/email side effects

4. **Scoring**
   `afeScorecard` LWC + `AFEScorecardController` for manual + AI suggestions

## Prerequisites

- Salesforce CLI (`sf`) installed
- Dev Hub / target demo org access
- Einstein Prompt Builder enabled in target org (for AI features)
- User permissions to deploy metadata and assign permission sets

## Quick Start

### 1) Clone + auth

```bash
git clone https://github.com/RussEvans222/GrantScoreCard.git
cd GrantScoreCard
sf org login web --alias GRANTS
```

### 2) Deploy core metadata (manifest)

```bash
sf project deploy start \
  --target-org GRANTS \
  --manifest config/deploy-manifest-core.xml \
  --wait 60
```

### 3) Seed required library data (idempotent)

```bash
sf apex run --target-org GRANTS --file scripts/apex/seed_grantmaking_demo.apex
```

This creates/updates starter `Section_Library__c` and `Criterion_Library__c` records by `DeveloperKey__c`.

### 4) Assign permission sets

```bash
sf org assign permset --target-org GRANTS --name Evaluation_Rubric_Admin
sf org assign permset --target-org GRANTS --name ApplicationForm_Applicant_Access
```

## Prompt Template Setup (Important)

### Required templates used by Apex

- Single-criterion AI template API name: `AFE_Criterion_Scoring_Suggestion`
- Bulk scorecard AI template API name: `AFE_Scorecard`

`AFE_Criterion_Scoring_Suggestion` is included in source metadata.

`AFE_Scorecard` must exist in the org and be active with this input contract:

- `Input:ApplicationFormEvaluation` (Object: `ApplicationFormEvaluation`)

Expected response JSON:

```json
{
  "scores": [
    {
      "criterionId": "a96...",
      "score": 3,
      "reason": "Short criterion-specific rationale"
    }
  ]
}
```

## Post-Deploy Activation Checklist

1. Confirm these flows are **Active**:
   - `Grant_Application_Intake_Flow`
   - `Evaluation_Template_Wizard_Flow`
   - `Assign_Reviewers_Create_Evaluations`
   - `Initialize_Evaluation_Criteria_Scores`
   - `Recalculate_AFE_Weighted_Total`
2. Confirm quick actions are on layouts/pages:
   - `FundingOpportunity.Apply Now`
   - `FundingOpportunity.Setup Evaluation Criteria`
   - `ApplicationForm.Assign Reviewers`
3. Confirm `afeScorecard` appears on `ApplicationFormEvaluation` record page.

## End-to-End Validation (Smoke)

### Admin setup

1. Open a Funding Opportunity.
2. Click **Setup Evaluation Criteria**.
3. Choose criteria, set weights to total 100, activate template.

### Applicant intake

1. From Funding Opportunity, click **Apply Now**.
2. Submit flow.
3. Verify created:
   - `ApplicationForm`
   - `ApplicationFormRelation` with `ReferenceRecordId = FundingOpportunity.Id`

### Reviewer path

1. Open the Application Form and click **Assign Reviewers**.
2. Verify:
   - AFE records created
   - `ApplicationForm.Stage` set to `In Review`
   - reviewer tasks + emails generated

### Scorecard

1. Open an AFE record and load `afeScorecard`.
2. Generate AI suggestions (single + bulk).
3. Save reviewer scores.
4. Verify `Evaluation_Criterion_Score__c` updated and weighted totals recomputed.

## Troubleshooting

### AI bulk returns fallback for all rows

Check debug logs for:

- `AI PROMPT INVOKE template=AFE_Scorecard`
- `AI RAW RESPONSE TEXT:`

Common causes:

- `AFE_Scorecard` template missing/inactive
- wrong prompt input resource API name
- model/runtime access not enabled for running user

### Reviewer flow says template missing

Ensure the Funding Opportunity has `Evaluation_Template__c` set to an active published template.

## Repo Structure

- `config/deploy-manifest-core.xml` -> deployable core keep-list manifest
- `scripts/apex/seed_grantmaking_demo.apex` -> idempotent seed script
- `docs/setup/demo-org-setup.md` -> detailed setup runbook
- `docs/testing/e2e-test-plan.md` -> end-to-end test scenarios
- `docs/architecture/component-map.md` -> component dependency map

## Notes for Extending

- Keep `Evaluation_Template__c` versioning semantics intact (draft/published)
- Do not bypass `AssignReviewersCreateEvaluationsAction` if you need stage/task/email side effects
- Preserve scorecard AI response contract (`scores[]`) and parser aliases in controller
