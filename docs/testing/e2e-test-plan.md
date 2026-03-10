# End-to-End Test Plan

## Scope

Validate complete grantmaking lifecycle:

1. Intake
2. Template setup
3. Reviewer assignment
4. Scorecard + AI scoring

## Test Data Prerequisites

- Seed script executed (`scripts/apex/seed_grantmaking_demo.apex`)
- At least one active Funding Opportunity record
- Reviewer users available and active

## Scenario Matrix

## 1. Intake from Funding Opportunity

- Launch `Apply Now` quick action from Funding Opportunity.
- Complete flow screens and submit.
- Verify:
  - `ApplicationForm` created
  - `ApplicationFormRelation` created
  - `ReferenceRecordId` points to launching Funding Opportunity
  - Redirect lands on created ApplicationForm record

## 2. Intake from no-context launch

- Launch `Grant_Application_Intake_Flow` directly.
- Select Funding Opportunity manually and submit.
- Verify same record creation behavior.

## 3. Template wizard create-from-scratch

- Launch `Setup Evaluation Criteria` from Funding Opportunity without template.
- Select criteria, configure weights to 100, activate.
- Verify:
  - `Evaluation_Template__c` created/published
  - `FundingOpportunity.Evaluation_Template__c` populated
  - `Evaluation_Template_Criterion__c` rows saved

## 4. Template wizard clone branch

- Launch wizard on target FO and choose source FO in clone option.
- Verify preselected criteria and editable configuration.
- Activate and validate FO pointer switches to cloned/published template.

## 5. Reviewer assignment side effects

- On ApplicationForm, click `Assign Reviewers`.
- Select reviewers and submit.
- Verify:
  - AFE rows created (dedupe respected)
  - `ApplicationForm.Stage` set to `In Review` when createdCount > 0
  - reviewer tasks created
  - reviewer emails sent

## 6. Criterion snapshot initialization

- After AFE creation, verify `Evaluation_Criterion_Score__c` rows exist.
- Confirm section/order/label/weight values align with active template.

## 7. Scorecard manual scoring

- Open `afeScorecard` on AFE.
- Enter reviewer score and rationale, save.
- Verify row persistence and weighted total recomputation.

## 8. AI single-row scoring

- Trigger single criterion AI suggestion.
- Verify suggested score + rationale update and save behavior.

## 9. AI bulk scoring

- Trigger bulk AI (FILL_BLANKS and OVERWRITE_ALL modes).
- Verify parser accepts response and maps rows by criterion id.
- Verify save persists updates and warnings appear only on fallback.

## Failure/Regression Checks

- Missing template on FO -> assignment flow should show clear stop message.
- Invalid weight total (!= 100) -> wizard blocks activation.
- No duplicate open AFE per reviewer/application.
- Score input validation enforces integer 0..5.
