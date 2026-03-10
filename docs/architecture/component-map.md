# Grantmaking Component Map

## Core Data Model

- `FundingOpportunity`
  - lookup: `Evaluation_Template__c`
- `Evaluation_Template__c`
  - child: `Evaluation_Template_Criterion__c`
- `Criterion_Library__c`
  - lookup: `Section_Library__c`
- `ApplicationForm`
- `ApplicationFormRelation`
  - links ApplicationForm to FundingOpportunity (`ReferenceObjectName='FundingOpportunity'`)
- `ApplicationFormEvaluation`
  - lookup: `ApplicationFormId`
  - lookup: `Evaluation_Template__c`
- `Evaluation_Criterion_Score__c`
  - lookup: `ApplicationFormEvaluation__c`

## Runtime Components

## Intake

- Flow: `Grant_Application_Intake_Flow`
- Quick Action: `FundingOpportunity.Apply_Now`
- LWCs: `flowStepNavigator`, `flowAutoRedirect`
- Trigger support: `ApplicationFormAutoLinkFundingOpportunity` + `ApplicationFormFundingOpportunityLinker`

## Template Admin Wizard

- Flow: `Evaluation_Template_Wizard_Flow`
- Quick Action: `FundingOpportunity.Configure_Evaluation_Rubric`
- Apex actions:
  - `EvaluationTemplateWizardPrepareAction`
  - `EvalTemplateWizardBuildAction`
  - `EvaluationTemplateWizardSaveAction`
  - `CriterionLibraryManageAction`
  - `CriterionLibrarySelectorController`
  - `RubricTemplateService` (+ helper actions)
- LWCs:
  - `flowCriterionSelector`
  - `flowRubricCriteriaEditor`
  - `flowStepNavigator`

## Reviewer Assignment

- Flow: `Assign_Reviewers_Create_Evaluations`
- Quick Action: `ApplicationForm.Assign_Reviewers_Create_Evaluations`
- Apex: `AssignReviewersCreateEvaluationsAction`
- LWC: `reviewerPicker`
- Existing initializer flow remains runtime dependency:
  - `Initialize_Evaluation_Criteria_Scores`

## Scoring

- LWC: `afeScorecard`
- Apex: `AFEScorecardController`
- Existing total/recommendation flow dependency:
  - `Recalculate_AFE_Weighted_Total`

## Experience / Snapshot Widgets

- `applicationStatusTracker` + `ApplicationStatusController`
- `afeEvaluationSnapshot` + `AFEvaluationSnapshotController`

## Prompt Templates Used by Controller

- Single row: `AFE_Criterion_Scoring_Suggestion`
- Bulk: `AFE_Scorecard` (must exist in org; object input `Input:ApplicationFormEvaluation`)
