# GrantScoreCard Curated Accelerator Deployment Runbook

This runbook is for deploying GrantScoreCard into a fresh Public Sector Solutions org baseline.

## 1) Preflight Org Readiness Validation

Run these checks before deployment.

| Check | Command / Validation | Expected Result | Blocker if Failed | Recovery |
|---|---|---|---|---|
| Org auth | `sf org display --target-org <ALIAS>` | Connected status | Cannot deploy | Re-auth org |
| API compatibility | `sf org display --target-org <ALIAS> --verbose` | API supports v66 metadata | Metadata parse/deploy errors | Upgrade org/API usage |
| Prompt Builder availability | Setup > Prompt Builder enabled | Prompt templates usable | Prompt invocations fail | Enable Einstein Prompt Builder + permissions |
| Required prompt templates present | Prompt Builder list includes `AFE_Criterion_Scoring_Suggestion`, `AFE_Scorecard`, `EvaluationFrameworkReview`, `ETDisplayName` | All present + active | AI features incomplete | Deploy prompt metadata + activate templates |
| Permission assignment capability | `sf org assign permset --target-org <ALIAS> --name Evaluation_Rubric_Admin --dry-run` (or run assign in test sandbox) | Assign succeeds | Users cannot access fields/actions | Grant admin rights / fix permset dependencies |
| Required object model present | `sf data query --target-org <ALIAS> --query "SELECT Id FROM FundingOpportunity LIMIT 1"` | Query runs | Core PSS objects unavailable | Confirm PSS package baseline |

## 2) Prompt Template Inventory + Invocation Matrix

| Prompt API Name | Invocation Source | Inputs | Expected Output | Failure / Fallback Behavior |
|---|---|---|---|---|
| `AFE_Criterion_Scoring_Suggestion` | `AFEScorecardController` (single-row suggestion) | Application context + criterion context | JSON with `suggestedScore`, `suggestedRationale` | Controller surfaces warning/error toast and preserves manual scoring path |
| `AFE_Scorecard` | `AFEScorecardController` (bulk suggestion) | Evaluation + criteria set | JSON `scores[]` with criterion mapping | Controller warns on parse/runtime issues; reviewer can continue manually |
| `EvaluationFrameworkReview` | `EvaluationFrameworkReviewService` via `criteriaInsightsWorkspace` | `Evaluation_Template__c` + `Evaluation_Template_Criterion__c` snapshot | JSON framework health, dimensions, issues, recommendations, improvements | Response error message returned to workspace UI; no scoring-path impact |
| `ETDisplayName` | Evaluation Template record page Einstein field action | `Evaluation_Template__c` + related criteria snapshot | Plain-text short display name | User can manually edit `Display_Name__c` |

## 3) Flow Activation Matrix

| Flow API Name | Required State | Trigger / Entry Path | Dependencies | Validation Checkpoint |
|---|---|---|---|---|
| `Grant_Application_Intake_Flow` | Active | Funding Opportunity quick action `Apply Now` | ApplicationForm relation handling | Submit test intake creates ApplicationForm + relation |
| `Evaluation_Template_Wizard_Flow` | Active | Funding Opportunity quick action `Configure Evaluation Rubric` | Criteria selector/editor LWCs + Apex actions | Create/publish template from wizard |
| `Assign_Reviewers_Create_Evaluations` | Active | ApplicationForm quick action `Assign Reviewers` | Reviewer assignment Apex + template link | AFE records/tasks/emails/status update |
| `Initialize_Evaluation_Criteria_Scores` | Active | AFE creation side effect | Evaluation template criterion rows | Score rows created for each criterion |
| `Recalculate_AFE_Weighted_Total` | Active | Score updates | Evaluation_Criterion_Score__c values | Weighted total/recommendation refresh |

## 4) Flexipage / Page Assignment Matrix

| Object / Context | Flexipage | Required Components / Actions | Assignment Target | Verification |
|---|---|---|---|---|
| `ApplicationForm` | `Application_Form_Record_Page` | `applicationStatusTracker`, assign-reviewer action visibility | App/profile assignment for target users | Open ApplicationForm record and confirm status card + reviewer action |
| `ApplicationFormEvaluation` | `Application_Form_Evaluation_Record_Page` | `afeScorecard`, `afeEvaluationSnapshot`, complete action | App/profile assignment for reviewers/admin | Open AFE and run scorecard flow |
| `Evaluation_Template__c` | `Evaluation_Template_Record_Page1` (or assigned active variant) | `Display_Name__c` generative action using `ETDisplayName` | App/profile/record type page assignment | Open template record and run ETDisplayName generation |

## 5) Minimum Required Seed Data Definition

Keep seed data separate from metadata deployment.

| Data Set | Minimum Rows | Purpose | Source |
|---|---:|---|---|
| Section / Bundle library (`Section_Library__c`) | 2+ | Group criteria into reusable bundles | `scripts/apex/seed_grantmaking_demo.apex` |
| Criteria library (`Criterion_Library__c`) | 4+ | Baseline rubric criteria for wizard/manager | `scripts/apex/seed_grantmaking_demo.apex` |
| Funding Opportunity sample | 1+ | Launch point for intake and template setup | Manual/org sample data |
| Evaluation Template linkage | 1 | Enables reviewer assignment + score initialization | Wizard publish or existing template |

Seed execution order:
1. Deploy metadata
2. Assign permission sets
3. Run seed Apex script
4. Activate flows
5. Run smoke tests

## 6) Troubleshooting Matrix

| Symptom | Likely Cause | Diagnostic | Remediation |
|---|---|---|---|
| AI buttons fail in scorecard | Missing/inactive prompt template | Prompt Builder template list + debug logs | Activate/deploy required prompt template |
| Criteria Insights analysis fails | `EvaluationFrameworkReview` unavailable/access denied | Check template exists and user has Einstein access | Activate template + grant permissions |
| ETDisplayName not available on template page | Wrong flexipage assignment | Lightning App Builder page assignment check | Assign page containing `Display_Name__c` generative action |
| Template dropdown shows auto-number only | `Display_Name__c` blank or not visible | Check FLS + record values | Grant FLS and populate `Display_Name__c` |
| Reviewer assignment creates no AFEs | Missing published template link | Check `FundingOpportunity.Evaluation_Template__c` | Publish template and relink FO |
| Weighted totals not updating | Recalc flow inactive | Flow setup activation check | Activate `Recalculate_AFE_Weighted_Total` |
| Bundle/criteria manager empty | Seed data not loaded | Query `Section_Library__c` and `Criterion_Library__c` counts | Run seed script |

## 7) Staged Deployment Steps (Keep Separate)

### Step A: Metadata Deploy (Curated Manifest)

```bash
sf project deploy start \
  --target-org <ALIAS> \
  --manifest config/deploy-manifest-accelerator-curated.xml \
  --wait 90
```

Expected result: deploy succeeded with no component errors.

### Step B: Permission Assignment

```bash
sf org assign permset --target-org <ALIAS> --name Evaluation_Rubric_Admin
sf org assign permset --target-org <ALIAS> --name ApplicationForm_Applicant_Access
```

Expected result: assignment succeeds for target users.

### Step C: Seed Data Execution

```bash
sf apex run --target-org <ALIAS> --file scripts/apex/seed_grantmaking_demo.apex
```

Expected result: idempotent create/update of sections and criteria baseline.

### Step D: Flow Activation

Activate the five required flows in Setup (see Flow Activation Matrix).

Expected result: all five show Active latest version.

### Step E: Smoke Testing

Run end-to-end smoke scenarios from `docs/testing/e2e-test-plan.md`:
- intake
- rubric setup
- reviewer assignment
- scorecard AI (single + bulk)
- criteria insights + ETDisplayName generation

## 8) Validation Strategy

### Check-only validation for curated package

```bash
sf project deploy start \
  --target-org <ALIAS> \
  --manifest config/deploy-manifest-accelerator-curated.xml \
  --dry-run \
  --wait 90
```

### Full staged execution

Execute Steps A-E in order and record outcomes per matrix.
