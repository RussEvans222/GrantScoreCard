#!/usr/bin/env bash
set -euo pipefail

ORG_ALIAS="${1:-GRANTS}"
JOB_FILE="${2:-vlocity-job.yaml}"

echo "[1/2] Exporting OmniScript, IntegrationProcedure, and DataRaptor via vlocity..."
vlocity packExport -sfdx.username "${ORG_ALIAS}" -job "${JOB_FILE}"

echo "[2/2] Retrieving OmniUiCard metadata via sf CLI..."
sf project retrieve start --target-org "${ORG_ALIAS}" --metadata OmniUiCard

echo "OmniStudio export complete."
