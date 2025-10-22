# Pull Request Validation Setup

This guide explains how to set up automated validation for firewall rules CSV files on pull requests.

## Overview

The PR validation pipeline (`PR-Validation.yaml`) automatically runs the `Test-FirewallRulesCsv.ps1` script whenever a pull request is created or updated that modifies CSV files in `config/parameters/FirewallRules/`.

## Setup Instructions

### 1. Create the Pipeline in Azure DevOps

1. Navigate to your Azure DevOps project
2. Go to **Pipelines** → **Pipelines**
3. Click **New Pipeline** (or **Create Pipeline**)
4. Select **Azure Repos Git** (or your repository source)
5. Select your repository
6. Choose **Existing Azure Pipelines YAML file**
7. Select the branch (e.g., `main` or `development-testscript`)
8. Path: `/.azuredevops/PR-Validation.yaml`
9. Click **Continue**
10. Click **Save** (or **Run** to test it)

### 2. Configure Branch Policy (Required to Block PRs)

To make the validation **mandatory** and block pull requests from being completed if validation fails:

1. Go to **Repos** → **Branches**
2. Find your target branch (e.g., `main`)
3. Click the **...** menu next to the branch
4. Select **Branch policies**
5. Under **Build Validation**, click **+** to add a build policy
6. Configure:
   - **Build pipeline**: Select `PR-Validation` (the pipeline you just created)
   - **Trigger**: `Automatic (whenever the source branch is updated)`
   - **Policy requirement**: `Required` ✅
   - **Build expiration**: `Immediately when main is updated`
   - **Display name**: `Firewall Rules CSV Validation`
7. Click **Save**

### 3. Test the Setup

1. Create a new branch from `main`:
   ```bash
   git checkout main
   git pull
   git checkout -b test-pr-validation
   ```

2. Make a change to a CSV file (introduce an error for testing):
   ```bash
   # Edit config/parameters/FirewallRules/FirewallRules.csv
   # For example, remove a quote to create a malformed CSV
   ```

3. Commit and push:
   ```bash
   git add .
   git commit -m "Test PR validation"
   git push -u origin test-pr-validation
   ```

4. Create a pull request to `main`

5. The validation pipeline should automatically run

6. If validation fails:
   - The PR will show a **failed check** ❌
   - The **Complete** button will be **disabled** or show a warning
   - You must fix the errors before merging

7. If validation passes:
   - The PR will show a **passed check** ✅
   - The PR can be completed/merged

## What Gets Validated

The validation script checks:

- ✅ **CSV Formatting**
  - Balanced quotes
  - Proper field delimiters
  - No missing commas between fields

- ✅ **Required Columns**
  - All mandatory columns present

- ✅ **Enum Values**
  - Valid RuleType, Action, CollectionType, SourceType, DestinationType

- ✅ **Priority Conflicts**
  - No duplicate priorities within rule collection groups
  - Consistent priority values

- ✅ **IP Addresses & CIDR**
  - Valid IP address format
  - Valid CIDR notation (e.g., `10.0.0.0/24`)

- ✅ **FQDNs**
  - Valid domain name format
  - Supports wildcards (e.g., `*.microsoft.com`)

- ✅ **Protocols & Ports**
  - Valid protocol types
  - Valid port numbers (1-65535)
  - Proper format for application rules (e.g., `Https:443`)

- ✅ **Rule Completeness**
  - Required fields present for each rule type

- ✅ **Priority Ranges**
  - Priorities between 100-65000

## Pipeline Behavior

### Triggers
- **Automatic**: Runs on any PR to `main` that modifies CSV files in `config/parameters/FirewallRules/`
- **Manual**: Can be run manually from Azure DevOps if needed

### Exit Codes
- `0`: Validation passed ✅
- `1`: Validation failed ❌

### Outputs
- Detailed validation report in pipeline logs
- Color-coded results (errors in red, warnings in yellow, success in green)
- Line numbers for errors to help locate issues quickly

## Bypassing Validation (Not Recommended)

If you need to bypass validation in an emergency:

1. Go to the PR
2. Click on the failed validation check
3. If you have permissions, you can override the policy
4. **Warning**: This should only be used in exceptional circumstances

## Troubleshooting

### Pipeline doesn't trigger on PR

**Solution**: 
- Check that the PR targets the `main` branch
- Check that the CSV file path matches `config/parameters/FirewallRules/**/*.csv`
- Verify the pipeline is enabled in Azure DevOps

### Validation passes locally but fails in pipeline

**Solution**:
- Check for line ending differences (CRLF vs LF)
- Ensure the CSV file is committed with UTF-8 encoding
- Run: `.\pipeline-scripts\Test-FirewallRulesCsv.ps1 -PolicyCsvPath '.\config\parameters\FirewallRules\FirewallRules.csv'`

### Can't complete PR even though validation passed

**Solution**:
- Check for other branch policies (e.g., required reviewers)
- Ensure the build policy shows as "Succeeded"
- Try refreshing the PR page

## Local Testing

Before creating a PR, test locally:

```powershell
# Test a specific CSV file
.\pipeline-scripts\Test-FirewallRulesCsv.ps1 -PolicyCsvPath '.\config\parameters\FirewallRules\FirewallRules.csv'

# Test with strict mode (warnings fail validation)
.\pipeline-scripts\Test-FirewallRulesCsv.ps1 -PolicyCsvPath '.\config\parameters\FirewallRules\FirewallRules.csv' -Strict
```

## Additional Resources

- [Azure DevOps Branch Policies](https://learn.microsoft.com/en-us/azure/devops/repos/git/branch-policies)
- [Build Validation Policy](https://learn.microsoft.com/en-us/azure/devops/repos/git/branch-policies#build-validation)
- [YAML Pipeline Documentation](https://learn.microsoft.com/en-us/azure/devops/pipelines/yaml-schema)
