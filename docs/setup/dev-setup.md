# Developer Setup (Minimal)

## 1) Required Local Tools

Install the following tools before working in this repo:

- Salesforce CLI (`sf`)
- VS Code + Salesforce Extension Pack
- Git
- Node.js LTS

Verify your setup:

```bash
sf --version
sf plugins
sf org login web
sf org list
```

## 2) OmniStudio Runtime Check

Confirm OmniStudio is available in your target org:

- Go to **Setup -> Installed Packages** and verify **OmniStudio** is installed.
- Open the **App Launcher** and confirm **OmniScript Designer** is available.

If OmniScript Designer is not visible, check user permissions and package availability.

## 3) Tableau Embedding Prerequisites

For Lightning workspace embedding:

- Add your Tableau domain to **CSP Trusted Sites** in Salesforce.
- Ensure Tableau dashboards are configured to allow Lightning embedding.
- Confirm the trusted domain exactly matches your Tableau environment URL.
