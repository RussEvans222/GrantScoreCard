# Demo Org Setup Runbook

## 1) Authenticate target org

```bash
sf org login web --alias GRANTS
```

## 2) Deploy core metadata

```bash
sf project deploy start \
  --target-org GRANTS \
  --manifest config/deploy-manifest-core.xml \
  --wait 60
```

## 3) Seed section + criterion library data

```bash
sf apex run --target-org GRANTS --file scripts/apex/seed_grantmaking_demo.apex
```

The script is idempotent and updates by `DeveloperKey__c`.

## 4) Assign permission sets

```bash
sf org assign permset --target-org GRANTS --name Evaluation_Rubric_Admin
sf org assign permset --target-org GRANTS --name ApplicationForm_Applicant_Access
```

## 5) Prompt Builder preflight

### Required Prompt Templates

- `AFE_Criterion_Scoring_Suggestion` (single-row AI)
- `AFE_Scorecard` (bulk AI)

### `AFE_Scorecard` contract

- Input resources:
  - `Input:ApplicationFormEvaluation` (`ApplicationFormEvaluation` object)
- Expected output JSON:

```json
{
  "scores": [
    {
      "criterionId": "a96...",
      "score": 3,
      "reason": "Short rationale"
    }
  ]
}
```

## 6) Activate flows

Ensure latest versions are active:

- `Grant_Application_Intake_Flow`
- `Evaluation_Template_Wizard_Flow`
- `Assign_Reviewers_Create_Evaluations`
- `Initialize_Evaluation_Criteria_Scores`
- `Recalculate_AFE_Weighted_Total`

## 7) UX placement checks

- Funding Opportunity page includes:
  - `Apply Now`
  - `Setup Evaluation Criteria`
- Application Form page includes:
  - `Assign Reviewers`
- Application Form Evaluation page includes:
  - `afeScorecard`

## 8) Optional targeted tests

```bash
sf apex run test --target-org GRANTS --tests AFEScorecardControllerTest,RubricTemplateServiceTest,AssignReviewersCreateAFEsActionTest --result-format human --wait 60
```
