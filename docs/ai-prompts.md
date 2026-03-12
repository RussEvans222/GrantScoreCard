# AI Prompt Templates

This document lists the Salesforce Prompt Builder templates used by GrantScoreCard and explains how each one fits into the architecture.

## AFE_Criterion_Scoring_Suggestion

Purpose:
- Generate a single criterion score suggestion and rationale for one score row in the AFE scorecard.

Primary usage:
- Invoked from the `afeScorecard` experience for one-row AI assistance.

Expected output shape:
- JSON with `suggestedScore` and `suggestedRationale`.

## AFE_Scorecard

Purpose:
- Generate bulk criterion suggestions for an evaluation scorecard.

Primary usage:
- Invoked from bulk AI action in scorecard to fill/update multiple rows.

Expected output shape:
- JSON with `scores[]` entries containing `criterionId`, `score`, and `reason`.

## EvaluationFrameworkReview

Purpose:
- Analyze rubric structure quality for an evaluation template.

Inputs:
- `Evaluation_Template__c`
- Related `Evaluation_Template_Criterion__c` snapshot

Primary usage:
- Invoked from Criteria Insights workspace.

Expected output shape:
- Structured JSON with framework health score, dimension scores, issues, recommendations, and improvements.

## ETDisplayName

Purpose:
- Generate a short display name for evaluation templates.

Inputs:
- `Evaluation_Template__c`
- `Evaluation_Template_Criterion__c` snapshot

Output:
- Plain text display name.

Example:
- `Innovation Impact Grant Review`

Trigger path:
- Triggered through an Einstein Action on the Evaluation Template record page.
- Prompt API name used by the action: `ETDisplayName`.

Why it helps:
- Makes template picklists and admin screens easier to scan than auto-number-only names.
