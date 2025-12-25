---
name: web-crawler-policy
description: Analyze robots.txt and llms.txt policies to understand which crawlers can access content. Use when auditing crawler policies, analyzing AI content accessibility, or generating marketing intelligence on brand representation in LLMs.
---

# web-crawler-policy

Analyze robots.txt and llms.txt policies across domains to understand crawler permissions and AI content accessibility.

## Description

Comprehensive web crawler policy analyzer that fetches and parses robots.txt and llms.txt files, analyzes permissions for traditional search crawlers and AI/LLM crawlers, and generates detailed reports. Optional LLM-powered marketing intelligence reports provide strategic insights on brand representation in AI systems.

## When to Use

- Audit crawler policies across your digital properties
- Understand which AI systems can access your content
- Analyze competitor content accessibility strategies
- Generate marketing intelligence on AI brand representation
- Create crawler permission reports for compliance/documentation
- Optimize content policies for AI discovery while protecting sensitive areas

## Requirements

- **aiohttp** - Async HTTP requests (installed via pyproject.toml)
- **tabulate** - Table formatting (installed via pyproject.toml)
- **openai** - LLM-powered reports (installed via pyproject.toml, optional)
- **OPENAI_API_KEY** - API key for LLM reports (from Doppler or environment variable)

## Scripts

### analyze_policies.py
Main script for analyzing crawler policies and generating reports.

```bash
python analyze_policies.py DOMAIN [OPTIONS]
python analyze_policies.py --domains DOMAIN1 DOMAIN2 ... [OPTIONS]
```

**Arguments**:
- `DOMAIN`: Target domain to analyze (discovers subdomains automatically)
- `--domains`: Specify exact domains to analyze (skips subdomain discovery)

**Discovery Options**:
- `--no-discover`: Skip subdomain discovery, analyze only the main domain
- `--wordlist FILE`: Custom wordlist for subdomain discovery
- `--dns-timeout SECONDS`: DNS resolution timeout (default: 5.0)

**Analysis Options**:
- `--timeout SECONDS`: HTTP request timeout (default: 10.0)
- `--no-llms`: Skip checking for llms.txt files
- `--save-robots`: Save robots.txt and llms.txt files to disk
- `--output-dir DIR`: Output directory for saved files (default: /workspace/Reports)

**Output Options**:
- `--output FILE`: Export results to CSV
- `--json-output FILE`: Export raw data to JSON
- `--no-table`: Skip console table output
- `--all`: Save all output formats with default names

**LLM Report Options**:
- `--report`: Generate LLM-powered marketing intelligence report
- `--llm-model MODEL`: LLM model to use (default: gpt-4o)
- `--llm-api-key KEY`: OpenAI API key (or use OPENAI_API_KEY from Doppler)
- `--report-output FILE`: Output path for markdown report

**Examples**:

```bash
# Analyze domain with subdomain discovery
python analyze_policies.py example.com

# Analyze specific domains (no discovery)
python analyze_policies.py --domains example.com api.example.com docs.example.com

# Full analysis with all outputs
python analyze_policies.py example.com --all

# Generate LLM-powered marketing report
python analyze_policies.py example.com --report

# Save robots.txt files to disk
python analyze_policies.py example.com --save-robots --output-dir ~/my-reports

# Custom subdomain wordlist
python analyze_policies.py example.com --wordlist custom.txt --report

# Skip llms.txt checking
python analyze_policies.py example.com --no-llms --output analysis.csv

# Full pipeline with subdomain-discover
python ../subdomain-discover/scripts/discover_subdomains.py example.com --json > domains.json
python analyze_policies.py --domains $(jq -r '.data.domains[]' domains.json) --report
```

## Features

### Robots.txt Analysis
- Fetches robots.txt from all discovered/specified domains
- Parses User-agent directives and Allow/Disallow rules
- Identifies traditional web crawlers (GoogleBot, BingBot, etc.)
- Identifies AI/LLM crawlers (GPTBot, ClaudeBot, Google-Extended, etc.)
- Identifies dual-purpose crawlers (used for both search and AI)
- Analyzes permissions across all domains
- Handles case-insensitive matching and crawler aliases

### llms.txt Support
- Fetches llms.txt files (proposed AI-specific policy standard)
- Parses common llms.txt directives:
  - `llm-training` / `ai-training` / `model-training`
  - `llm-inference` / `ai-inference` / `model-inference`
  - `contact` / `email`
  - `policy` / `policy-url`
- Validates file format (rejects HTML/JSON masquerading as llms.txt)
- Compares llms.txt policies with robots.txt rules

### Crawler Classification

**Traditional Web Crawlers**:
- Search engine bots not primarily used for AI training
- Examples: AhrefsBot, SemrushBot, MJ12bot

**AI/LLM Crawlers**:
- GPTBot (OpenAI GPT training)
- ClaudeBot (Anthropic Claude training)
- Google-Extended (Google AI training)
- CCBot (Common Crawl - used by many AI companies)
- Meta-ExternalAgent (Meta AI)
- PerplexityBot (Perplexity AI)
- ByteSpider (ByteDance AI)
- AmazonBot (Amazon AI)
- OAI-SearchBot (OpenAI search)

**Dual-Purpose Crawlers**:
- GoogleBot (Search + AI training)
- BingBot (Search + AI training)
- FacebookExternalHit (Sharing + AI training)
- TwitterBot (Cards + AI training)

### Output Formats

**Console Table** (default):
Shows permissions across all domains in formatted tables:
```
==============================================
ROBOTS.TXT ANALYSIS
==============================================

AI/LLM Crawlers:
┌──────────┬─────────┬────────────┬─────────┐
│ Provider │ Crawler │ example.com│ api... │
├──────────┼─────────┼────────────┼─────────┤
│ OpenAI   │ gptbot  │ Blocked    │ Allowed │
│ Anthropic│claudebot│ Allowed    │ Allowed │
└──────────┴─────────┴────────────┴─────────┘
```

**CSV Export**:
Structured data for spreadsheet analysis:
```csv
analysis_type,crawler_type,provider,crawler,description,example.com,api.example.com
robots.txt,LLM/AI,OpenAI,gptbot,OpenAI GPT training,Blocked,Allowed
robots.txt,LLM/AI,Anthropic,claudebot,Anthropic Claude,Allowed,Allowed
llms.txt,Directive,,llm-training,LLM policy directive,disallowed,Not specified
```

**JSON Export**:
Complete raw data for programmatic use:
```json
{
  "domain": "example.com",
  "discovered_domains": ["example.com", "api.example.com"],
  "robots_data": {
    "example.com": {
      "robots_found": true,
      "llms_found": true,
      "rules": {...},
      "llms_rules": {...}
    }
  },
  "permission_analysis": {
    "summary": {...},
    "robots_analysis": {...},
    "llms_analysis": {...}
  }
}
```

**LLM-Powered Marketing Report** (optional):
Comprehensive markdown report with strategic insights:
- Executive summary of AI content accessibility
- Brand representation impact analysis
- Key strategic findings with business implications
- Content gaps and opportunities
- Competitive positioning analysis
- Prioritized recommendations with implementation roadmap
- Domain-by-domain policy matrices
- Crawler permission breakdowns

## LLM Report Generation

When `--report` is enabled, the script uses OpenAI's GPT-4 with structured outputs to generate a marketing-focused intelligence report.

**Report Sections**:
1. Executive Summary
2. Brand Digital Footprint Overview
3. AI Content Accessibility Analysis
4. Subdomain Content Policy Matrix
5. Crawler Permission Analysis
6. Key Strategic Findings
7. Content Gaps and Opportunities
8. Competitive Positioning Impact
9. Strategic Recommendations
10. Implementation Roadmap

**API Configuration**:
```bash
# Use Doppler secrets (recommended)
DOPPLER_TOKEN="..." doppler run -- python analyze_policies.py example.com --report

# Or set environment variable
export OPENAI_API_KEY="sk-..."
python analyze_policies.py example.com --report

# Or pass directly
python analyze_policies.py example.com --report --llm-api-key "sk-..."
```

**Cost Considerations**:
- Uses GPT-4o model (default)
- Typical cost: $0.10-0.30 per report
- Large domains with many subdomains may cost more
- Reports are generated once and saved as markdown

## Default Save Locations

**Reports and Analysis**:
```
/workspace/Reports/{domain}/
```

**Saved robots.txt files** (with `--save-robots`):
```
/workspace/Reports/{domain}/robots_{subdomain}_{timestamp}.txt
/workspace/Reports/{domain}/llms_{subdomain}_{timestamp}.txt
```

**Output files** (with `--all`):
```
/workspace/Reports/{domain}/crawler_analysis_{timestamp}.csv
/workspace/Reports/{domain}/scan_results_{timestamp}.json
/workspace/Reports/{domain}/analysis_report_{timestamp}.md
/workspace/Reports/{domain}/analysis_report_{timestamp}_analysis.json
```

## Workflow

### Typical Usage Flow

1. **Domain Input**: Specify target domain or list of domains
2. **Subdomain Discovery** (optional): Automatically discover subdomains
3. **Policy Fetching**: Fetch robots.txt and llms.txt from all domains
4. **Policy Parsing**: Parse and structure policy rules
5. **Permission Analysis**: Analyze crawler permissions across domains
6. **Report Generation**: Generate tables, CSV, JSON outputs
7. **LLM Analysis** (optional): Generate marketing intelligence report
8. **File Saving** (optional): Save robots.txt files and reports to disk

### Integration with subdomain-discover

```bash
# Step 1: Discover subdomains
python ../subdomain-discover/scripts/discover_subdomains.py example.com --json > domains.json

# Step 2: Analyze discovered domains
python analyze_policies.py \
  --domains $(jq -r '.data.domains[]' domains.json) \
  --all --report

# Or use internal discovery (default)
python analyze_policies.py example.com --all --report
```

## Crawler Detection

The script uses intelligent crawler detection:

### Exact Matching
- Case-insensitive matching (GPTBot, gptbot, GPTBOT all match)

### Alias Recognition
- GoogleBot → googlebot, googlebot-image, googlebot-video
- GPTBot → gptbot, openai, chatgpt-user
- ClaudeBot → claudebot, claude-web, anthropic

### Pattern Matching
- Detects LLM-related patterns: llm-, ai-, gpt, neural, training
- Identifies internal codes and cryptic user-agents

## Error Handling

**Network Errors**:
- Connection failures: Domain skipped, marked as "No robots.txt"
- Timeouts: Increase `--timeout` value
- SSL errors: Domain skipped with warning

**Parsing Errors**:
- Malformed robots.txt: Best-effort parsing, may miss some rules
- Invalid llms.txt: Rejected if HTML/JSON format detected
- Missing files: Marked as not found, analysis continues

**LLM Errors**:
- API key missing: Error message with suggestions
- Rate limits: Automatic retry with exponential backoff
- Timeout: Retries up to 3 times
- Structured output validation: Ensures all required fields present

## Performance

- Subdomain discovery: 30-90 seconds (depends on domain)
- robots.txt fetching: ~2-5 seconds per domain (parallel)
- Analysis and table generation: <1 second
- CSV/JSON export: <1 second
- LLM report generation: 10-30 seconds (OpenAI API call)

## Tips

- Use `--all` for comprehensive output in one command
- Save robots.txt files with `--save-robots` for historical tracking
- LLM reports provide strategic insights for marketing teams
- CSV exports work well for spreadsheet analysis and presentations
- JSON exports enable programmatic analysis and automation
- Combine with `subdomain-discover` for maximum control over discovery
- Use `--no-discover` to analyze specific domains without discovery overhead
- Check llms.txt files to see if brands have AI-specific policies

## Limitations

- Requires network access to fetch robots.txt files
- Cannot access robots.txt behind authentication
- LLM reports require OpenAI API key (costs apply)
- Large domains with 50+ subdomains may be slow
- CT log queries can timeout for very large domains
- Some crawlers may not be classified correctly if using non-standard names

## Related Skills

- **subdomain-discover** - Discover subdomains before policy analysis
- **dns-lookup** - Detailed DNS analysis (future skill)
- **ssl-check** - SSL certificate validation (future skill)
