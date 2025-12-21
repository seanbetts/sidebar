---
name: subdomain-discover
description: Discover subdomains using DNS bruteforce, Certificate Transparency logs, and sitemap parsing. Use when you need to map a brand's digital footprint, perform security reconnaissance, or prepare for crawler policy analysis.
---

# subdomain-discover

Discover subdomains for a target domain using multiple reconnaissance techniques.

## Description

Performs comprehensive subdomain discovery using DNS bruteforce, Certificate Transparency logs, and sitemap parsing. Includes intelligent filtering to remove internal infrastructure domains and redirect-only subdomains, focusing on consumer-facing and public domains.

## When to Use

- Map the digital footprint of a brand or organization
- Discover public-facing web properties before analysis
- Security reconnaissance and infrastructure mapping
- Input for robots.txt/crawler policy analysis
- DNS management and subdomain inventory

## Requirements

- **dnspython** - DNS resolution (installed via pyproject.toml)
- **aiohttp** - Async HTTP requests (installed via pyproject.toml)
- **lxml** - XML parsing for sitemaps (installed via pyproject.toml)

## Scripts

### discover_subdomains.py
Discovers subdomains using multiple techniques with intelligent filtering.

```bash
python discover_subdomains.py DOMAIN [--wordlist FILE] [--timeout SECONDS] [--dns-timeout SECONDS] [--json] [--verbose]
```

**Arguments**:
- `DOMAIN`: Target domain to discover subdomains for (required)

**Options**:
- `--wordlist FILE`: Custom wordlist for DNS bruteforce (default: built-in list)
- `--timeout SECONDS`: HTTP request timeout (default: 10.0)
- `--dns-timeout SECONDS`: DNS resolution timeout (default: 5.0)
- `--json`: Output results in JSON format
- `--verbose`: Show detailed progress information
- `--no-filter`: Skip filtering internal/redirect domains (show all results)

**Discovery Techniques**:

1. **DNS Bruteforce**
   - Tests common subdomain names against DNS
   - Default wordlist includes 100+ high-value subdomains
   - Custom wordlist support for targeted discovery
   - Covers: www, api, docs, support, blog, shop, developer, etc.

2. **Certificate Transparency Logs**
   - Queries crt.sh and certspotter.com APIs
   - Discovers subdomains from SSL/TLS certificates
   - Often reveals historical and internal domains
   - Timeout: 30 seconds (CT APIs can be slow)

3. **Sitemap Parsing**
   - Extracts URLs from sitemap.xml and sitemap indexes
   - Parses robots.txt for sitemap references
   - Recursively processes sitemap indexes
   - Discovers cross-domain references

**Intelligent Filtering**:

The script applies multiple filtering passes to focus on public-facing domains:

- **Source Confidence Filtering**: Multi-source validation
  - Domains found by multiple methods = highest confidence
  - DNS bruteforce hits = high confidence (specifically tested)
  - Sitemap discoveries = medium-high confidence
  - CT-only domains = requires additional validation

- **Internal Domain Filtering**: Removes infrastructure
  - Development/testing: *-dev, *-test, *-staging, *-qa
  - Server identifiers: srv01, node123, us-east1
  - Cryptic codes: Short consonant-heavy subdomains
  - Wildcard and invalid domains

- **Consumer-Facing Prioritization**: Keeps valuable domains
  - E-commerce: store, shop, cart, checkout
  - Support: help, docs, support, knowledge
  - Content: blog, news, media, downloads
  - Developer: api, developer, console, docs
  - Business: partners, business, enterprise

- **Redirect Filtering**: Removes redirect-only domains
  - Tests each subdomain for HTTP 301/302/303/307/308
  - Filters out domains that don't serve actual content
  - Keeps main domain variants (www, non-www)

**Examples**:

```bash
# Basic discovery
python discover_subdomains.py example.com

# JSON output for piping to other tools
python discover_subdomains.py example.com --json

# Custom wordlist with verbose output
python discover_subdomains.py example.com --wordlist custom_subdomains.txt --verbose

# Skip filtering to see all discovered domains
python discover_subdomains.py example.com --no-filter --json

# Longer timeouts for slow networks
python discover_subdomains.py example.com --timeout 20 --dns-timeout 10
```

## Output Format

**Human-readable output** shows discovery progress and results:

```
Starting subdomain discovery for: example.com
DNS Bruteforce found: 15 domains
Certificate Transparency found: 42 domains
Sitemap Parsing found: 8 domains
Checking for redirect subdomains...
Filtered out 12 redirect subdomains

Found 23 domains/subdomains:
  - example.com
  - www.example.com
  - api.example.com
  - docs.example.com
  - support.example.com
  ...
```

**JSON output** provides structured data:

```json
{
  "success": true,
  "data": {
    "domain": "example.com",
    "discovered_count": 23,
    "domains": [
      "example.com",
      "www.example.com",
      "api.example.com",
      "docs.example.com",
      "support.example.com"
    ],
    "discovery_stats": {
      "dns_bruteforce": 15,
      "certificate_transparency": 42,
      "sitemap_parsing": 8,
      "filtered_redirects": 12,
      "final_count": 23
    },
    "duration_seconds": 45
  }
}
```

## Output Locations

Results are written to stdout (console or JSON). To save results:

```bash
# Save human-readable output
python discover_subdomains.py example.com > subdomains.txt

# Save JSON output
python discover_subdomains.py example.com --json > subdomains.json

# Pipe to other tools
python discover_subdomains.py example.com --json | jq '.data.domains[]'
```

## Performance Notes

- DNS bruteforce: ~100 domains/second (depends on DNS server)
- Certificate Transparency: 10-30 seconds (API dependent)
- Sitemap parsing: 2-5 seconds per sitemap
- Redirect checking: ~10 domains/second (batched requests)
- Total time: 30-90 seconds for typical domains

## Error Handling

**DNS Errors**:
- NXDOMAIN: Subdomain doesn't exist (normal, filtered out)
- Timeout: Increase `--dns-timeout` for slow DNS servers
- Rate limiting: DNS servers may rate limit, results may be incomplete

**HTTP Errors**:
- Connection failures: Domain may be unreachable (kept in results)
- Timeouts: Increase `--timeout` for slow servers
- SSL errors: Domain may have certificate issues (kept in results)

**API Errors**:
- CT API failures: Script continues with other methods
- Sitemap parsing errors: Malformed XML ignored

**Error Output**:
```json
{
  "success": false,
  "error": {
    "type": "DNSError|NetworkError|ValueError",
    "message": "Detailed error message",
    "suggestions": [
      "Check domain spelling",
      "Verify DNS server connectivity",
      "Try increasing timeout values"
    ]
  }
}
```

## Advanced Usage

### Custom Wordlist

Create a custom wordlist for targeted subdomain discovery:

```bash
# wordlist.txt
admin
staging
beta
test
dev
internal
vpn
```

```bash
python discover_subdomains.py example.com --wordlist wordlist.txt
```

### Pipeline Integration

Use with other Agent Smith skills:

```bash
# Discover subdomains, then analyze robots.txt policies
python discover_subdomains.py example.com --json > domains.json
python ../web-crawler-policy/scripts/analyze_policies.py \
  --domains $(jq -r '.data.domains[]' domains.json) \
  --output analysis.csv
```

### Filtering Control

```bash
# See all discovered domains (no filtering)
python discover_subdomains.py example.com --no-filter

# Compare filtered vs unfiltered
python discover_subdomains.py example.com --json > filtered.json
python discover_subdomains.py example.com --no-filter --json > unfiltered.json
diff <(jq '.data.domains' filtered.json) <(jq '.data.domains' unfiltered.json)
```

## Tips

- Use `--verbose` to understand which discovery methods are working
- Custom wordlists should focus on your target industry/organization
- CT logs are great for historical subdomains but may include outdated ones
- Redirect filtering removes many internal redirects but may filter legitimate domains
- For large organizations, expect 20-50 public-facing subdomains
- DNS bruteforce is most reliable but limited to tested names
- Sitemap parsing discovers cross-domain references missed by other methods

## Limitations

- DNS bruteforce only finds subdomains in wordlist
- CT logs may include expired or historical subdomains
- Sitemap parsing requires public sitemaps
- Cannot discover subdomains behind authentication
- Private/internal networks not accessible
- Rate limiting may affect completeness
- Wildcard DNS can cause false positives (filtered by default)

## Related Skills

- **web-crawler-policy** - Analyze robots.txt policies on discovered domains
- **dns-lookup** - Detailed DNS record analysis (future skill)
- **ssl-check** - SSL certificate analysis (future skill)
