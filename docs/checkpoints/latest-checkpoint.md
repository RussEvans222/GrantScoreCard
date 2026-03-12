# GrantScoreCard Build Checkpoint
**Date:** March 12, 2026  
**Phase:** OmniStudio Intake Rebuild  
**Repository:** GrantScoreCard

---

# Purpose of This Document

This document is a **checkpoint snapshot** of the current GrantScoreCard architecture and development plan.

The goal is to ensure that as we rebuild the **grant intake using OmniStudio**, we remain aligned with the **original GrantScoreCard data model and evaluation framework**.

We are **NOT redesigning the evaluation system** in this phase.  
We are **only rebuilding the intake experience using OmniStudio (OmniScript, Integration Procedures, Data Mappers).**

---

# Core GrantScoreCard Data Model (Baseline)

This is the **canonical architecture** used in previous versions of the project.

```
FundingOpportunity
    ↓ lookup
Evaluation_Template__c
    ↓ related list
Evaluation_Template_Criterion__c
```

During the review process:

```
ApplicationForm
    ↓
ApplicationFormEvaluation
    ↓
Evaluation_Criterion_Score__c
```

---

# Object Relationships

## FundingOpportunity

Represents a grant program or funding opportunity.

Key responsibilities:

• Defines the funding program  
• Links to the evaluation rubric  
• Used during intake selection

Key field:

```
Evaluation_Template__c (Lookup)
```

This lookup determines **which rubric applies to this opportunity**.

---

## Evaluation_Template__c

Represents a **rubric definition**.

Examples:

• Community Development Grant Rubric  
• Infrastructure Improvement Grant Rubric  
• Small Business Innovation Grant Rubric

Fields:

```
Version__c
Status__c
Root_Template__c
FundingOpportunity__c (optional association)
```

Related records:

```
Evaluation_Template_Criterion__c
```

---

## Evaluation_Template_Criterion__c

Defines **individual scoring criteria** used during grant evaluation.

Examples:

• Economic Impact
• Community Benefit
• Environmental Sustainability
• Budget Feasibility

Fields:

```
Weight__c
Display_Order__c
Max_Score__c
Criterion_Description__c
```

These records represent the **rubric rows**.

---

## ApplicationForm

Represents a **submitted grant application**.

Created from:

• Intake Flow
• OmniScript (new version)

Typical fields:

```
FundingOpportunity__c
Applicant_Organization__c
Project_Description__c
Funding_Request_Amount__c
Submission_Date__c
```

---

## ApplicationFormEvaluation

Represents **a review session for an application**.

Relationships:

```
ApplicationForm → ApplicationFormEvaluation
Evaluation_Template__c → ApplicationFormEvaluation
```

This is created when a reviewer begins scoring.

---

## Evaluation_Criterion_Score__c

Represents **a single criterion score**.

Relationships:

```
ApplicationFormEvaluation
Evaluation_Template_Criterion__c
```

Fields:

```
Score__c
Weighted_Score__c
Reviewer_Comments__c
```

These records are the **scorecard rows**.

---

# Confirmed Architecture Flow

## Intake

```
Applicant
   ↓
OmniScript
   ↓
Create ApplicationForm
```

---

## Evaluation Preparation

```
ApplicationForm
   ↓
Create ApplicationFormEvaluation
   ↓
Snapshot Evaluation_Template_Criterion records
   ↓
Create Evaluation_Criterion_Score records
```

---

## Review

```
Reviewer scores each criterion
   ↓
Weighted total calculated
   ↓
Recommendation generated
```

---

# Current Phase (OmniStudio Rebuild)

We are rebuilding the **grant intake layer only**.

Existing evaluation infrastructure remains unchanged.

---

# Components Being Rebuilt

## OmniScript

```
GrantIntake_MVP_English_1
```

Responsibilities:

• Capture project description  
• Identify funding opportunity  
• Create ApplicationForm record  
• Support AI project analysis

---

## Integration Procedures

Planned IPs:

```
IP_AnalyzeProjectFunding
IP_FindFundingOpportunities
IP_CreateApplicationForm
```

Possible future:

```
IP_GenerateEligibilityScore
IP_PrepareEvaluationContext
```

---

## Data Mappers (Extract)

Used for AI grounding.

Examples:

```
DR_ApplicantContext
DR_FundingOpportunityContext
DR_EvaluationTemplateContext
```

Purpose:

Provide structured JSON context for Prompt Builder.

---

# AI Architecture Direction

Future integration will include **Agentforce orchestration**.

Example pattern:

```
OmniScript
    ↓
Integration Procedure
    ↓
Agentforce
    ↓
Prompt Builder
    ↓
Recommendation
```

AI capabilities planned:

• Funding program recommendations  
• Project summarization  
• Eligibility estimation  
• Reviewer scoring assistance

---

# What Is Completed

✔ Core GrantScoreCard data model defined  
✔ Evaluation rubric system implemented  
✔ Criterion snapshot scoring architecture established  
✔ Grant intake OmniScript created  
✔ Scoped CSS theme implemented  
✔ Full-screen LWC wrapper designed

---

# What Is In Progress

OmniStudio intake rebuild:

```
OmniScript UI
Integration Procedures
Agentforce integration
```

---

# What Still Needs to Be Built

## OmniStudio Layer

• Integration Procedures for funding discovery  
• Data Mapper extracts for AI grounding  
• OmniScript steps for project discovery

---

## AI Layer

• Prompt Builder templates

Examples:

```
Grant Project Funding Analysis
Grant Eligibility Scoring
Grant Recommendation Summary
```

---

## Evaluation Automation

Future improvements:

• AI-assisted rubric scoring  
• Reviewer recommendation summaries  
• Risk detection for grant applications

---

# Architectural Guardrails

To preserve compatibility with Agentforce:

### Integration Procedure JSON

Keys must be:

```
alphanumeric only
camelCase recommended
```

Example:

✔ `fundingOpportunityId`  
✔ `projectDescription`

Avoid:

✖ `funding_opportunity_id`  
✖ `project-description`

---

# Next Steps (Next Development Session)

1. Finalize OmniScript intake UX  
2. Implement Integration Procedure for funding analysis  
3. Connect Prompt Builder template  
4. Test AI recommendation loop

---

# End of Checkpoint
