# GrantScoreCard (Salesforce Grantmaking Starter Kit)

GrantScoreCard is a Salesforce DX project for a flow-first grantmaking demo on Public Sector Solutions / Grants Management data.  
It provides end-to-end intake, rubric setup, reviewer assignment, and AI-assisted evaluation.

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

## Feature Set Headers (Image Placeholders)

Use 1600 x 200 header images for each feature section.

`docs/images/headers/intake/01-intake-header-1600x200.png`  
`docs/images/headers/rubric-setup/02-rubric-setup-header-1600x200.png`  
`docs/images/headers/criterion-library/03-criterion-library-header-1600x200.png`  
`docs/images/headers/reviewer-assignment/04-reviewer-assignment-header-1600x200.png`  
`docs/images/headers/scorecard-ai/05-scorecard-ai-header-1600x200.png`  
`docs/images/headers/status-tracker/06-status-tracker-header-1600x200.png`

### Drop-In Banner Placeholders

Replace these with your exported 1600x200 files when ready:

![Grantmaking Scorecard - Application Intake](docs/images/headers/intake/01-intake-header-1600x200.png)
![Grantmaking Scorecard - Evaluation Rubric Setup](docs/images/headers/rubric-setup/02-rubric-setup-header-1600x200.png)
![Grantmaking Scorecard - Criterion Library](docs/images/headers/criterion-library/03-criterion-library-header-1600x200.png)
![Grantmaking Scorecard - Reviewer Assignment](docs/images/headers/reviewer-assignment/04-reviewer-assignment-header-1600x200.png)
![Grantmaking Scorecard - AI Evaluation Scorecard](docs/images/headers/scorecard-ai/05-scorecard-ai-header-1600x200.png)
![Grantmaking Scorecard - Application Status Tracker](docs/images/headers/status-tracker/06-status-tracker-header-1600x200.png)

## Latest Updates (March 11, 2026)

- **Rubric setup wizard simplified** to a cleaner admin flow:
  - optional clone -> criteria selection -> matrix configuration -> activation
  - library management removed from normal setup path
  - bundle-oriented language in criteria editing
- **Application status card updated** to use Lightning Data Service on `ApplicationForm` record context.
- **Assign Reviewers UX improved**:
  - clean confirmation messaging
  - task automation tuned for review workflow
  - reviewer notification email format updated
- **Scorecard AI experience updated**:
  - default mode is `Overwrite all`
  - button label is `Run AI Evaluation`
  - helper text clarifies reviewer final authority
- **AI prompt guidance improved** for evidence-based rationale quality and balanced 1-5 scoring.

## Runtime Paths

1. **Applicant Intake**  
   `[Header Image Placeholder: docs/images/headers/intake/01-intake-header-1600x200.png]`  
   `FundingOpportunity.Apply Now` -> `Grant_Application_Intake_Flow` -> creates `ApplicationForm` + `ApplicationFormRelation`

2. **Rubric Setup (Admin)**  
   `[Header Image Placeholder: docs/images/headers/rubric-setup/02-rubric-setup-header-1600x200.png]`  
   `FundingOpportunity.Setup Evaluation Criteria` -> `Evaluation_Template_Wizard_Flow`

3. **Criterion Library (Admin Data)**  
   `[Header Image Placeholder: docs/images/headers/criterion-library/03-criterion-library-header-1600x200.png]`  
   `Criterion_Library__c` + `Section_Library__c` provide reusable rubric criteria across funding opportunities.

4. **Reviewer Assignment**  
   `[Header Image Placeholder: docs/images/headers/reviewer-assignment/04-reviewer-assignment-header-1600x200.png]`  
   `ApplicationForm.Assign Reviewers` -> `Assign_Reviewers_Create_Evaluations` -> creates AFEs + task/email/stage side effects

5. **Scoring**  
   `[Header Image Placeholder: docs/images/headers/scorecard-ai/05-scorecard-ai-header-1600x200.png]`  
   `afeScorecard` LWC + `AFEScorecardController` for manual + AI suggestions

6. **Application Status Tracking**  
   `[Header Image Placeholder: docs/images/headers/status-tracker/06-status-tracker-header-1600x200.png]`  
   `applicationStatusTracker` on `ApplicationForm` record page

## Prerequisites

- Salesforce CLI (`sf`)
- Access to a target org (alias examples use `GRANTS`)
- Einstein Prompt Builder enabled for AI features
- User permissions to deploy metadata and assign permission sets

## Quick Start

### 1) Clone + auth

```bash
git clone https://github.com/RussEvans222/GrantScoreCard.git
cd GrantScoreCard
sf org login web --alias GRANTS
```

### 2) Deploy core metadata

```bash
sf project deploy start \
  --target-org GRANTS \
  --manifest config/deploy-manifest-core.xml \
  --wait 60
```

### 3) Seed section + criterion library data

```bash
sf apex run --target-org GRANTS --file scripts/apex/seed_grantmaking_demo.apex
```

### 4) Assign permission sets

```bash
sf org assign permset --target-org GRANTS --name Evaluation_Rubric_Admin
sf org assign permset --target-org GRANTS --name ApplicationForm_Applicant_Access
```

## Prompt Templates

Required templates used by scorecard Apex:

- `AFE_Criterion_Scoring_Suggestion` (single criterion AI)
- `AFE_Scorecard` (bulk AI)

Bulk expected response contract:

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

## Post-Deploy Checklist

1. Activate flows:
   - `Grant_Application_Intake_Flow`
   - `Evaluation_Template_Wizard_Flow`
   - `Assign_Reviewers_Create_Evaluations`
   - `Initialize_Evaluation_Criteria_Scores`
   - `Recalculate_AFE_Weighted_Total`
2. Confirm quick actions:
   - `FundingOpportunity.Apply Now`
   - `FundingOpportunity.Setup Evaluation Criteria`
   - `ApplicationForm.Assign Reviewers`
3. Confirm page placements:
   - `afeScorecard` on `ApplicationFormEvaluation`
   - `applicationStatusTracker` on `ApplicationForm`

## Smoke Validation

1. Configure a rubric on a Funding Opportunity and publish it.
2. Submit intake via `Apply Now`.
3. Verify redirect to created `ApplicationForm`.
4. Run `Assign Reviewers` and confirm:
   - AFEs are created
   - Stage updates to `In Review`
   - tasks and reviewer emails are generated
5. Open an AFE scorecard and run AI evaluation (single + bulk).

## Troubleshooting

### AI bulk fallback behavior

Check logs for:

- `AI PROMPT INVOKE template=AFE_Scorecard`
- `AI RAW RESPONSE TEXT:`

Common causes:

- prompt template missing/inactive
- prompt input resource mismatch
- model/runtime access not enabled for running user

### Reviewer flow template missing message

Ensure `FundingOpportunity.Evaluation_Template__c` points to an active published template.

## Repo Structure

- `config/deploy-manifest-core.xml` - deploy manifest
- `scripts/apex/seed_grantmaking_demo.apex` - idempotent seed data
- `docs/setup/demo-org-setup.md` - setup runbook
- `docs/testing/e2e-test-plan.md` - test scenarios
- `docs/architecture/component-map.md` - component dependency map

## Extension Notes

- Preserve `Evaluation_Template__c` version semantics (draft/published)
- Keep reviewer side effects in `AssignReviewersCreateEvaluationsAction`
- Preserve scorecard AI parser contract keys (`criterionId`, `score`, `reason`)
