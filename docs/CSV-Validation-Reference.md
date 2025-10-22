# Firewall Rules CSV Validation - Quick Reference

## Test-FirewallRulesCsv.ps1

### Purpose
Validates Azure Firewall Policy rules CSV files for formatting errors and rule conflicts before deployment.

### Usage

```powershell
# Basic validation
.\pipeline-scripts\Test-FirewallRulesCsv.ps1

# Validate specific file
.\pipeline-scripts\Test-FirewallRulesCsv.ps1 -PolicyCsvPath '.\config\parameters\FirewallRules\FirewallRules.csv'

# Strict mode (warnings = failures)
.\pipeline-scripts\Test-FirewallRulesCsv.ps1 -Strict
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `PolicyCsvPath` | string | `.\config\parameters\FirewallRules\FirewallRules.csv` | Path to CSV file to validate |
| `Strict` | switch | false | Fail on warnings (normally only fails on errors) |

### Exit Codes

| Code | Meaning | CI/CD Behavior |
|------|---------|----------------|
| `0` | ✅ Validation passed | Pipeline continues |
| `1` | ❌ Validation failed | Pipeline fails, blocks PR |

### Validation Checks

#### 1. CSV Formatting (Fail-Fast)
- ✅ Balanced quotes (even number of `"` per line)
- ✅ No missing commas between fields
- ✅ No orphaned quotes (`,word"` or `"word,`)
- ✅ Proper field delimiters

#### 2. CSV Structure
- ✅ All required columns present:
  - RuleCollectionGroup
  - RuleCollectionGroupPriority
  - RuleCollectionName
  - RuleCollectionPriority
  - RuleCollectionAction
  - RuleCollectionType
  - RuleType
  - RuleName

#### 3. Enum Validation
- ✅ **RuleType**: `ApplicationRule`, `NetworkRule`, `NatRule`
- ✅ **RuleCollectionAction**: `Allow`, `Deny`
- ✅ **RuleCollectionType**: `FirewallPolicyFilterRuleCollection`, `FirewallPolicyNatRuleCollection`
- ✅ **SourceType**: `SourceAddresses`, `SourceIpGroups`
- ✅ **DestinationType**: `TargetFqdns`, `DestinationAddresses`, `DestinationFqdns`, `DestinationIpGroups`
- ✅ **Protocols**: `Http`, `Https`, `Mssql`, `TCP`, `UDP`, `ICMP`, `Any`

#### 4. Priority Conflicts
- ✅ No duplicate RuleCollection priorities within same RuleCollectionGroup
- ✅ Consistent RuleCollectionGroup priority across all rows
- ✅ No duplicate rule names within same collection

#### 5. IP/CIDR Validation
- ✅ Valid IP addresses: `10.0.0.1`
- ✅ Valid CIDR notation: `10.0.0.0/24`
- ✅ Octet range: 0-255
- ✅ Prefix range: 0-32
- ✅ Wildcard allowed: `*`

#### 6. FQDN Validation
- ✅ Valid domain format: `example.com`
- ✅ Subdomain support: `sub.example.com`
- ✅ Wildcard support: `*.example.com`
- ✅ Alphanumeric + hyphens allowed
- ✅ Max 63 chars per label

#### 7. Protocols & Ports
- **ApplicationRule**:
  - ✅ Format: `Protocol:Port` (e.g., `Https:443`)
  - ✅ Multiple: `Https:443,Http:80`
- **NetworkRule**:
  - ✅ Protocols: `TCP`, `UDP`, `ICMP`, `Any`
  - ✅ Ports: `1-65535` or `*`
  - ✅ Port ranges: `80-443`

#### 8. Rule Completeness
- ✅ Source field required
- ⚠️ Destination field required (warning only for non-NAT rules)
- ✅ ApplicationRule requires Protocols
- ✅ NetworkRule requires Protocols and DestinationPorts

#### 9. Priority Ranges
- ✅ RuleCollectionGroup priority: 100-65000
- ✅ RuleCollection priority: 100-65000
- ✅ Numeric validation (no text values)

### Output Format

```
========================================
Azure Firewall Rules CSV Validator
========================================

Validating: .\config\parameters\FirewallRules\FirewallRules.csv

Checking CSV formatting...
  [OK]    CSV formatting is valid
  [OK]    CSV file loaded successfully (21 rows)

[1] Validating CSV Structure...
  [OK]    All required columns present

[2] Validating Enum Values...
  [OK]    All enum values are valid

[3] Checking Priority Conflicts...
  [OK]    No priority conflicts detected

[4] Validating IP Addresses and CIDR Notation...
  [OK]    All IP addresses and CIDR notations are valid

[5] Validating FQDNs...
  [OK]    All FQDNs are valid

[6] Validating Protocols and Ports...
  [OK]    All protocols and ports are valid

[7] Validating Rule Completeness...
  [OK]    All rules have required fields

[8] Validating Priority Ranges...
  [OK]    All priorities are within valid range (100-65000)

========================================
Validation Summary
========================================
Errors:   0
Warnings: 0
Info:     0

✓ Validation PASSED
```

### Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `Malformed CSV - unbalanced quotes` | Odd number of `"` on a line | Check for missing opening/closing quotes |
| `Missing comma between fields` | `"value1""value2"` | Add comma: `"value1","value2"` |
| `Invalid RuleType` | Typo in RuleType column | Use: `ApplicationRule`, `NetworkRule`, or `NatRule` |
| `Priority conflict` | Duplicate priority in group | Change priority to unique value |
| `Invalid source IP/CIDR` | Malformed IP address | Use format: `10.0.0.0/24` or `10.0.0.1` |
| `Invalid FQDN` | Special chars in domain | Use alphanumeric, hyphens, dots only |
| `Invalid protocol format` | Missing `:` in ApplicationRule | Use format: `Https:443` |
| `Priority out of range` | Priority < 100 or > 65000 | Set priority between 100-65000 |

### Integration with CI/CD

#### Azure DevOps (PR Validation)
- Pipeline: `.azuredevops/PR-Validation.yaml`
- Triggers: Pull requests to `main` with CSV changes
- Blocks merge if validation fails

#### GitHub Actions (Example)
```yaml
- name: Validate Firewall Rules CSV
  run: |
    pwsh -File pipeline-scripts/Test-FirewallRulesCsv.ps1 -PolicyCsvPath config/parameters/FirewallRules/FirewallRules.csv
  shell: pwsh
```

### Troubleshooting

**Q: Script passes locally but fails in pipeline**
- Check file encoding (should be UTF-8)
- Check line endings (CRLF vs LF)
- Ensure file is committed and pushed

**Q: How to see what line has the error?**
- Error messages include line numbers: `[ERROR] Line 15: ...`
- Line numbers start from 1 (header row = line 1)

**Q: Can I disable specific checks?**
- Not currently supported
- You can modify the script to comment out specific validation sections

**Q: What about warnings in strict mode?**
- Use `-Strict` parameter to fail on warnings
- Useful for enforcing best practices in production

### See Also
- [PR Validation Setup Guide](PR-Validation-Setup.md)
- [Deploy-Firewall-Rules Pipeline](.azuredevops/Deploy-Firewall-Rules.yaml)
- [Invoke-DeployFirewallPolicyRules.ps1](../pipeline-scripts/Invoke-DeployFirewallPolicyRules.ps1)
