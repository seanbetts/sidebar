#!/usr/bin/env python3
"""Subdomain Discovery

Discovers subdomains for a target domain using multiple techniques:
- DNS bruteforce with wordlist
- Certificate Transparency logs
- Sitemap parsing

Includes intelligent filtering to focus on public-facing domains.
"""

import argparse
import asyncio
import json
import re
import sys
import time
from urllib.parse import urlparse

import aiohttp
import dns.resolver
from lxml import etree


def normalize_domain(domain: str) -> str:
    """Normalize domain by removing www prefix for consolidation."""
    if domain.startswith("www."):
        return domain[4:]
    return domain


class SubdomainScanner:
    """Handles subdomain discovery using multiple techniques."""

    def __init__(
        self,
        domain: str,
        timeout: float = 10.0,
        dns_timeout: float = 5.0,
        verbose: bool = False,
    ):
        self.domain = domain
        self.timeout = timeout
        self.dns_timeout = dns_timeout
        self.verbose = verbose
        self.discovered_subdomains: set[str] = set()

    def log(self, message: str):
        """Log message if verbose mode is enabled."""
        if self.verbose:
            print(message, file=sys.stderr)

    async def scan_dns_bruteforce(self, wordlist: list[str]) -> set[str]:
        """Bruteforce subdomain discovery using common subdomain names."""
        subdomains = set()
        resolver = dns.resolver.Resolver()
        resolver.timeout = self.dns_timeout
        resolver.lifetime = self.dns_timeout

        self.log(f"DNS bruteforce: testing {len(wordlist)} subdomain names...")

        for word in wordlist:
            subdomain = f"{word}.{self.domain}"
            try:
                await asyncio.get_event_loop().run_in_executor(
                    None, resolver.resolve, subdomain, "A"
                )
                subdomains.add(subdomain)
                self.log(f"  Found: {subdomain}")
            except (
                dns.resolver.NXDOMAIN,
                dns.resolver.NoAnswer,
                dns.resolver.Timeout,
                Exception,
            ):
                continue

        return subdomains

    async def scan_certificate_transparency(
        self, session: aiohttp.ClientSession
    ) -> set[str]:
        """Discover subdomains via Certificate Transparency logs."""
        subdomains = set()
        ct_urls = [
            f"https://crt.sh/?q=%25.{self.domain}&output=json",
            f"https://certspotter.com/api/v0/certs?domain={self.domain}",
        ]

        self.log("Querying Certificate Transparency logs...")

        for url in ct_urls:
            try:
                # Use longer timeout for CT APIs as they can return large datasets
                ct_timeout = max(self.timeout * 3, 30)
                async with session.get(url, timeout=ct_timeout) as response:
                    if response.status == 200:
                        data = await response.json()
                        if isinstance(data, list):
                            for cert in data:
                                if "name_value" in cert:
                                    names = cert["name_value"].split("\n")
                                    for name in names:
                                        name = name.strip()
                                        if (
                                            name.endswith(f".{self.domain}")
                                            or name == self.domain
                                        ):
                                            subdomains.add(name)
                                            self.log(f"  Found: {name}")
                                # Also check common_name field
                                if "common_name" in cert:
                                    name = cert["common_name"].strip()
                                    if (
                                        name.endswith(f".{self.domain}")
                                        or name == self.domain
                                    ):
                                        subdomains.add(name)
                                        self.log(f"  Found: {name}")
            except (TimeoutError, aiohttp.ClientError, Exception) as e:
                self.log(f"CT API error for {url}: {e}")
                continue

        return subdomains

    async def scan_sitemaps(self, session: aiohttp.ClientSession) -> set[str]:
        """Discover subdomains by parsing sitemap files."""
        subdomains = set()

        self.log("Scanning sitemaps...")

        # Try to get sitemap URLs from robots.txt first
        sitemap_urls = await self._get_sitemap_urls_from_robots(session)

        # Also try common sitemap locations
        common_sitemaps = [
            f"https://{self.domain}/sitemap.xml",
            f"https://{self.domain}/sitemap_index.xml",
            f"https://{self.domain}/sitemaps.xml",
            f"http://{self.domain}/sitemap.xml",
            f"http://{self.domain}/sitemap_index.xml",
        ]
        sitemap_urls.extend(common_sitemaps)

        # Remove duplicates
        sitemap_urls = list(set(sitemap_urls))

        for sitemap_url in sitemap_urls:
            try:
                discovered = await self._parse_sitemap(session, sitemap_url)
                if discovered:
                    self.log(f"  Found {len(discovered)} domains in {sitemap_url}")
                subdomains.update(discovered)
            except Exception:
                continue

        return subdomains

    async def _get_sitemap_urls_from_robots(
        self, session: aiohttp.ClientSession
    ) -> list[str]:
        """Extract sitemap URLs from robots.txt file."""
        sitemap_urls = []
        protocols = ["https", "http"]

        for protocol in protocols:
            robots_url = f"{protocol}://{self.domain}/robots.txt"
            try:
                async with session.get(robots_url, timeout=self.timeout) as response:
                    if response.status == 200:
                        content = await response.text()
                        # Look for sitemap entries in robots.txt
                        for line in content.split("\n"):
                            line = line.strip()
                            if line.lower().startswith("sitemap:"):
                                sitemap_url = line.split(":", 1)[1].strip()
                                if sitemap_url:
                                    sitemap_urls.append(sitemap_url)
                        break  # Stop after first successful robots.txt
            except (TimeoutError, aiohttp.ClientError, Exception):
                continue

        return sitemap_urls

    async def _parse_sitemap(
        self, session: aiohttp.ClientSession, sitemap_url: str
    ) -> set[str]:
        """Parse a sitemap XML file and extract subdomains from URLs."""
        subdomains = set()

        try:
            async with session.get(sitemap_url, timeout=self.timeout) as response:
                if response.status != 200:
                    return subdomains

                content = await response.text()

                # Parse XML content
                try:
                    root = etree.fromstring(content.encode("utf-8"))
                except etree.XMLSyntaxError:
                    return subdomains

                # Handle sitemap index files (contain references to other sitemaps)
                sitemap_elements = root.xpath(
                    '//*[local-name()="sitemap"]/*[local-name()="loc"]'
                )
                if sitemap_elements:
                    # This is a sitemap index, recursively parse child sitemaps
                    for elem in sitemap_elements[
                        :10
                    ]:  # Limit to first 10 sitemaps to avoid excessive requests
                        if elem.text:
                            child_subdomains = await self._parse_sitemap(
                                session, elem.text
                            )
                            subdomains.update(child_subdomains)

                # Handle regular sitemaps (contain URLs)
                url_elements = root.xpath(
                    '//*[local-name()="url"]/*[local-name()="loc"]'
                )
                for elem in url_elements:
                    if elem.text:
                        parsed_url = urlparse(elem.text)
                        if parsed_url.netloc:
                            # Check if this is a subdomain of our target domain
                            if (
                                parsed_url.netloc.endswith(f".{self.domain}")
                                or parsed_url.netloc == self.domain
                            ):
                                subdomains.add(parsed_url.netloc)

        except (TimeoutError, aiohttp.ClientError, Exception):
            pass

        return subdomains

    async def discover_subdomains(
        self, wordlist: list[str] | None = None, apply_filters: bool = True
    ) -> set[str]:
        """Main subdomain discovery method combining multiple techniques."""
        if not wordlist:
            wordlist = self._get_default_wordlist()

        # Track subdomain sources for intelligent filtering
        subdomain_sources = {}

        async with aiohttp.ClientSession() as session:
            tasks = [
                self.scan_dns_bruteforce(wordlist),
                self.scan_certificate_transparency(session),
                self.scan_sitemaps(session),
            ]

            results = await asyncio.gather(*tasks, return_exceptions=True)

            method_names = [
                "DNS Bruteforce",
                "Certificate Transparency",
                "Sitemap Parsing",
            ]
            source_keys = ["dns", "ct", "sitemap"]

            for i, result in enumerate(results):
                if isinstance(result, set):
                    print(f"{method_names[i]} found: {len(result)} domains")
                    # Track which source found each domain
                    for domain in result:
                        if domain not in subdomain_sources:
                            subdomain_sources[domain] = []
                        subdomain_sources[domain].append(source_keys[i])
                    self.discovered_subdomains.update(result)
                elif isinstance(result, Exception):
                    print(f"{method_names[i]} failed: {result}")

        # Always include the main domain
        self.discovered_subdomains.add(self.domain)
        subdomain_sources[self.domain] = ["main"]

        if apply_filters:
            # Apply source-aware filtering and consolidation
            self.discovered_subdomains = self._consolidate_domains_with_sources(
                self.discovered_subdomains, subdomain_sources
            )

            # Filter out domains that redirect (don't serve actual content)
            print("Checking for redirect subdomains...")
            async with aiohttp.ClientSession() as session:
                self.discovered_subdomains = await self._filter_redirect_domains(
                    session, self.discovered_subdomains
                )

        return self.discovered_subdomains

    def _get_default_wordlist(self) -> list[str]:
        """Get default subdomain wordlist focused on high-value public domains."""
        return [
            # Core web infrastructure (high priority)
            "www",
            "api",
            "cdn",
            "static",
            "assets",
            "media",
            "images",
            "files",
            # Consumer-facing e-commerce and services
            "shop",
            "store",
            "buy",
            "cart",
            "checkout",
            "pay",
            "payments",
            "billing",
            "order",
            "orders",
            "account",
            "accounts",
            "profile",
            "user",
            "customer",
            # Help and documentation (high LLM value)
            "support",
            "help",
            "docs",
            "documentation",
            "guides",
            "tutorials",
            "learn",
            "kb",
            "knowledge",
            "faq",
            "howto",
            "manual",
            "reference",
            "resources",
            # Community and content (high LLM training value)
            "blog",
            "news",
            "press",
            "stories",
            "articles",
            "content",
            "editorial",
            "community",
            "forum",
            "forums",
            "discussion",
            "wiki",
            "social",
            # Developer resources (high LLM value)
            "developer",
            "developers",
            "dev",
            "api-docs",
            "sdk",
            "tools",
            "code",
            "github",
            "git",
            "samples",
            "examples",
            "playground",
            "sandbox",
            # Business and marketing content
            "about",
            "company",
            "careers",
            "jobs",
            "team",
            "contact",
            "legal",
            "privacy",
            "terms",
            "policy",
            "investor",
            "investors",
            "press-releases",
            # Product and service portals
            "console",
            "dashboard",
            "admin",
            "panel",
            "control",
            "manage",
            "management",
            "portal",
            "app",
            "apps",
            "platform",
            "service",
            "services",
            # Mobile and regional
            "mobile",
            "m",
            "wap",
            "touch",
            "us",
            "www-us",
            "en",
            "english",
            # Educational and training content (high LLM value)
            "education",
            "edu",
            "training",
            "courses",
            "academy",
            "university",
            "school",
            "classroom",
            "research",
            "papers",
            "publications",
            # Downloads and media (potential LLM training content)
            "downloads",
            "download",
            "software",
            "utilities",
            "updates",
            "releases",
            "video",
            "audio",
            "podcast",
            "webinar",
            # Search and discovery
            "search",
            "find",
            "directory",
            "catalog",
            "library",
            "archive",
            # Status and monitoring (useful for understanding service architecture)
            "status",
            "health",
            "monitor",
            "monitoring",
            "metrics",
            "analytics",
            # Partnership and business development
            "partner",
            "partners",
            "business",
            "enterprise",
            "corporate",
            "b2b",
            "affiliate",
            "reseller",
            "channel",
            # Communication and collaboration
            "mail",
            "email",
            "calendar",
            "meet",
            "chat",
            "collaborate",
            "share",
            # Security and compliance (may have relevant policies)
            "security",
            "secure",
            "compliance",
            "audit",
            "certifications",
            # Innovation and future content
            "innovation",
            "labs",
            "beta",
            "preview",
            "experimental",
            "future",
        ]

    def _consolidate_domains_with_sources(
        self, domains: set[str], sources: dict[str, list[str]]
    ) -> set[str]:
        """Source-aware domain consolidation and filtering."""
        # Apply source-based filtering first
        filtered_domains = self._filter_by_source_confidence(domains, sources)

        # Then apply regular consolidation
        return self._consolidate_domains(filtered_domains)

    def _filter_by_source_confidence(
        self, domains: set[str], sources: dict[str, list[str]]
    ) -> set[str]:
        """Filter domains based on source confidence and validation."""
        filtered = set()
        main_domain = normalize_domain(self.domain)

        for domain in domains:
            domain_sources = sources.get(domain, [])

            # Always include main domain
            if domain == main_domain or domain == f"www.{main_domain}":
                filtered.add(domain)
                continue

            # Multi-source validation = highest confidence
            if len(domain_sources) > 1:
                filtered.add(domain)
                continue

            # DNS bruteforce hits = high confidence (we specifically tested these)
            if "dns" in domain_sources:
                filtered.add(domain)
                continue

            # Sitemap hits = medium-high confidence
            if "sitemap" in domain_sources:
                filtered.add(domain)
                continue

            # Certificate Transparency only = lower confidence, apply aggressive filtering
            if "ct" in domain_sources and len(domain_sources) == 1:
                if self._is_high_value_ct_domain(domain):
                    filtered.add(domain)
                    continue
                # Skip CT-only domains that don't meet high-value criteria
                continue

        return filtered

    def _is_high_value_ct_domain(self, domain: str) -> bool:
        """Determine if a CT-only domain is high-value consumer-facing."""
        main_domain = normalize_domain(self.domain)
        domain_parts = domain.split(".")
        base_domain_parts = main_domain.split(".")
        subdomain_depth = len(domain_parts) - len(base_domain_parts)

        # Only single-depth subdomains
        if subdomain_depth != 1:
            return False

        subdomain = domain_parts[0]

        # High-value consumer patterns (very strict for CT-only)
        high_value_patterns = {
            "store",
            "shop",
            "support",
            "help",
            "docs",
            "api",
            "developer",
            "blog",
            "news",
            "community",
            "auth",
            "calendar",
            "education",
            "mobile",
            "app",
            "apps",
        }

        if subdomain.lower() in high_value_patterns:
            return True

        # Additional checks: longer meaningful names with vowels
        if (
            len(subdomain) >= 6
            and any(vowel in subdomain.lower() for vowel in "aeiou")
            and not self._is_cryptic_code(subdomain)
        ):
            return True

        return False

    def _is_cryptic_code(self, subdomain: str) -> bool:
        """Detect if a subdomain looks like a cryptic internal code."""
        subdomain = subdomain.lower()

        # Skip consumer patterns we know are legitimate
        consumer_patterns = {
            "store",
            "shop",
            "buy",
            "cart",
            "checkout",
            "pay",
            "payments",
            "support",
            "help",
            "docs",
            "documentation",
            "guides",
            "learn",
            "community",
            "forum",
            "blog",
            "news",
            "press",
            "media",
            "api",
            "developer",
            "developers",
            "console",
            "dashboard",
            "admin",
            "manage",
            "partner",
            "partners",
            "business",
            "app",
            "apps",
            "mobile",
            "web",
            "mail",
            "email",
            "calendar",
            "drive",
            "cloud",
            "storage",
            "photos",
            "music",
            "video",
            "education",
            "classroom",
            "training",
            "careers",
            "secure",
        }

        if subdomain in consumer_patterns:
            return False

        # 4-letter codes with mostly consonants or ending in 't' (common in Apple internal codes)
        if len(subdomain) == 4:
            vowel_count = sum(1 for char in subdomain if char in "aeiou")
            # If 4 letters with ≤1 vowel, likely internal code
            if vowel_count <= 1:
                return True
            # Common internal code patterns
            if subdomain.endswith(("at", "mt", "rt", "wt", "ca", "bd")):
                return True

        return False

    def _consolidate_domains(self, domains: set[str]) -> set[str]:
        """Consolidate www and non-www versions of domains."""
        # First filter out internal domains
        domains = self._filter_internal_domains(domains)

        consolidated = set()
        processed_bases = set()

        for domain in domains:
            base_domain = normalize_domain(domain)

            if base_domain in processed_bases:
                continue

            # Check if both www and non-www versions exist
            www_version = f"www.{base_domain}"
            has_www = www_version in domains
            has_base = base_domain in domains

            if has_www and has_base:
                # Both exist, keep both for now - we'll check content availability during analysis
                consolidated.add(www_version)
                consolidated.add(base_domain)
            elif has_www:
                consolidated.add(www_version)
            elif has_base:
                consolidated.add(base_domain)
            else:
                # This shouldn't happen, but add the original domain
                consolidated.add(domain)

            processed_bases.add(base_domain)

        return consolidated

    def _filter_internal_domains(self, domains: set[str]) -> set[str]:
        """Smart filtering to prioritize consumer-facing domains while removing internal infrastructure."""
        filtered = set()

        # Always include the main domain
        main_domain = normalize_domain(self.domain)
        www_main = f"www.{main_domain}"

        # Consumer-facing subdomain patterns (high priority)
        consumer_patterns = {
            # E-commerce and customer-facing
            "store",
            "shop",
            "buy",
            "cart",
            "checkout",
            "pay",
            "payments",
            # Support and help
            "support",
            "help",
            "docs",
            "documentation",
            "guides",
            "learn",
            "community",
            "forum",
            "kb",
            "knowledge",
            "faq",
            # Content and media
            "blog",
            "news",
            "press",
            "media",
            "download",
            "downloads",
            "resources",
            "assets",
            "cdn",
            "static",
            # Developer and business
            "api",
            "developer",
            "dev",
            "developers",
            "console",
            "dashboard",
            "admin",
            "manage",
            "partner",
            "partners",
            "business",
            "enterprise",
            # Product specific
            "app",
            "apps",
            "mobile",
            "web",
            "mail",
            "email",
            "calendar",
            "drive",
            "cloud",
            "storage",
            "photos",
            "music",
            "video",
            # Educational and professional
            "education",
            "edu",
            "classroom",
            "training",
            "careers",
            # Regional/international
            "m",
            "www",
            "secure",
        }

        # Definite internal/infrastructure patterns (exclude these)
        internal_patterns = [
            # Development/testing
            r"^.*-dev",
            r"^.*-test",
            r"^.*-stage",
            r"^.*-staging",
            r"^.*-qa",
            r"^.*-uat",
            r"^.*-int",
            r"^.*-internal",
            r"^.*-prod",
            r"^.*-production",
            # Infrastructure codes (cryptic subdomains)
            r"^[a-z]{1,3}\d*",  # cl1, ade, erp, gs, etc.
            r"^\d+[a-z]*",  # 123a, 5b, etc.
            # Server/cluster identifiers
            r"^[a-z]+\d{2,}",  # server01, node123, etc.
            # Geographic server codes
            r"^[a-z]{2,3}-[a-z]{2,3}\d*",  # us-east1, eu-west2
            # Wildcard domains
            r"^\*",
            # Invalid/escaped characters
            r".*\\\d+\\\d+.*",
        ]

        compiled_internal = [
            re.compile(pattern, re.IGNORECASE) for pattern in internal_patterns
        ]

        for domain in domains:
            # Always include main domain and www variant
            if domain == main_domain or domain == www_main:
                filtered.add(domain)
                continue

            # Only consider single-depth subdomains
            domain_parts = domain.split(".")
            base_domain_parts = main_domain.split(".")
            subdomain_depth = len(domain_parts) - len(base_domain_parts)

            if subdomain_depth > 1:
                continue

            # Extract subdomain part
            if subdomain_depth == 1:
                subdomain = domain_parts[0]

                # Skip if matches internal patterns
                if any(pattern.match(subdomain) for pattern in compiled_internal):
                    continue

                # Skip obvious internal keywords
                if any(
                    keyword in subdomain.lower()
                    for keyword in [
                        "test",
                        "staging",
                        "internal",
                        "corp",
                        "vpn",
                        "intranet",
                    ]
                ):
                    continue

                # Prioritize consumer-facing patterns
                if subdomain.lower() in consumer_patterns:
                    filtered.add(domain)
                    continue

                # Include if it looks like a reasonable public subdomain
                # (longer names, contains vowels, not all consonants, not cryptic codes)
                if (
                    len(subdomain) >= 4
                    and any(vowel in subdomain.lower() for vowel in "aeiou")
                    and not subdomain.isdigit()
                    and not self._is_cryptic_code(subdomain)
                ):
                    filtered.add(domain)

        # Limit to reasonable number for large domains
        if len(filtered) > 30:
            # Prioritize consumer patterns, then shorter names
            def priority_sort(domain):
                subdomain = domain.split(".")[0] if "." in domain else ""
                if subdomain.lower() in consumer_patterns:
                    return (0, len(domain), domain)  # Highest priority
                else:
                    return (1, len(domain), domain)  # Lower priority

            sorted_domains = sorted(filtered, key=priority_sort)
            result = set(sorted_domains[:30])
        else:
            result = filtered

        return result

    async def _filter_redirect_domains(
        self, session: aiohttp.ClientSession, domains: set[str]
    ) -> set[str]:
        """Filter out all domains that redirect (don't serve actual content)."""
        main_domain = normalize_domain(self.domain)
        main_variants = {main_domain, f"www.{main_domain}", self.domain}

        non_redirect_domains = set()
        redirect_tasks = []

        # Create tasks to check each domain for redirects
        for domain in domains:
            if domain in main_variants:
                # Always keep main domain variants
                non_redirect_domains.add(domain)
            else:
                redirect_tasks.append(self._check_domain_redirect(session, domain))

        # Process redirect checks in batches to avoid overwhelming servers
        batch_size = 10
        for i in range(0, len(redirect_tasks), batch_size):
            batch = redirect_tasks[i : i + batch_size]
            results = await asyncio.gather(*batch, return_exceptions=True)

            for result in results:
                if isinstance(result, tuple) and not isinstance(result, Exception):
                    domain, is_redirect = result
                    if not is_redirect:
                        non_redirect_domains.add(domain)
                # If there's an exception or connection error, keep the domain (assume it's valid)

        redirect_count = len(domains) - len(non_redirect_domains)
        if redirect_count > 0:
            print(f"Filtered out {redirect_count} redirect subdomains")

        return non_redirect_domains

    async def _check_domain_redirect(
        self, session: aiohttp.ClientSession, domain: str
    ) -> tuple[str, bool]:
        """Check if a domain returns a redirect status code."""
        protocols = ["https", "http"]

        for protocol in protocols:
            url = f"{protocol}://{domain}/"
            try:
                async with session.get(
                    url, timeout=self.timeout, allow_redirects=False
                ) as response:
                    # Check for redirect status codes - filter out ALL redirects
                    if response.status in [301, 302, 303, 307, 308]:
                        return (domain, True)  # It's a redirect, filter it out

                    # If we get here, it serves actual content
                    return (domain, False)

            except (TimeoutError, aiohttp.ClientError, Exception):
                # If we can't check, assume it's not a redirect (keep the domain)
                continue

        # If all protocols failed, assume it's not a redirect (keep the domain)
        return (domain, False)


async def main():
    """Main entry point for subdomain discovery script."""
    parser = argparse.ArgumentParser(
        description="Discover subdomains using DNS, Certificate Transparency, and sitemap parsing",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Basic discovery
  %(prog)s example.com

  # JSON output
  %(prog)s example.com --json

  # Custom wordlist with verbose output
  %(prog)s example.com --wordlist subdomains.txt --verbose

  # Skip filtering to see all results
  %(prog)s example.com --no-filter --json

  # Save results to file
  %(prog)s example.com > subdomains.txt
  %(prog)s example.com --json > subdomains.json
        """,
    )

    # Required arguments
    parser.add_argument("domain", help="Target domain to discover subdomains for")

    # Optional arguments
    parser.add_argument("--wordlist", help="Custom wordlist file for DNS bruteforce")
    parser.add_argument(
        "--timeout",
        type=float,
        default=10.0,
        help="HTTP request timeout in seconds (default: 10.0)",
    )
    parser.add_argument(
        "--dns-timeout",
        type=float,
        default=5.0,
        help="DNS resolution timeout in seconds (default: 5.0)",
    )
    parser.add_argument(
        "--json", action="store_true", help="Output results in JSON format"
    )
    parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Show detailed progress information",
    )
    parser.add_argument(
        "--no-filter",
        action="store_true",
        help="Skip filtering internal/redirect domains",
    )

    args = parser.parse_args()

    # Load custom wordlist if provided
    wordlist = None
    if args.wordlist:
        try:
            with open(args.wordlist, encoding="utf-8") as f:
                wordlist = [line.strip() for line in f if line.strip()]
        except FileNotFoundError:
            error_output = {
                "success": False,
                "error": {
                    "type": "FileNotFoundError",
                    "message": f"Wordlist file '{args.wordlist}' not found",
                    "suggestions": [
                        "Check the file path is correct",
                        "Ensure the file exists",
                        "Use absolute path if needed",
                    ],
                },
            }
            if args.json:
                print(json.dumps(error_output, indent=2), file=sys.stderr)
            else:
                print(f"Error: {error_output['error']['message']}", file=sys.stderr)
            sys.exit(1)

    try:
        start_time = time.time()

        if not args.json:
            print(f"Starting subdomain discovery for: {args.domain}")

        # Discover subdomains
        scanner = SubdomainScanner(
            args.domain,
            timeout=args.timeout,
            dns_timeout=args.dns_timeout,
            verbose=args.verbose,
        )
        subdomains = await scanner.discover_subdomains(
            wordlist, apply_filters=not args.no_filter
        )

        duration = int(time.time() - start_time)

        # Output results
        if args.json:
            output = {
                "success": True,
                "data": {
                    "domain": args.domain,
                    "discovered_count": len(subdomains),
                    "domains": sorted(subdomains),
                    "duration_seconds": duration,
                },
            }
            print(json.dumps(output, indent=2))
        else:
            print(f"\nFound {len(subdomains)} domains/subdomains:")
            for subdomain in sorted(subdomains):
                print(f"  - {subdomain}")
            print(f"\nDiscovery completed in {duration} seconds")

        sys.exit(0)

    except ValueError as e:
        error_output = {
            "success": False,
            "error": {
                "type": "ValueError",
                "message": str(e),
                "suggestions": [
                    "Check domain name is valid",
                    "Verify DNS configuration",
                    "Try with different options",
                ],
            },
        }
        if args.json:
            print(json.dumps(error_output, indent=2), file=sys.stderr)
        else:
            print(f"Error: {error_output['error']['message']}", file=sys.stderr)
        sys.exit(1)

    except Exception as e:
        error_output = {
            "success": False,
            "error": {
                "type": "UnexpectedError",
                "message": str(e),
                "suggestions": [
                    "Check network connectivity",
                    "Verify domain is accessible",
                    "Try increasing timeout values",
                    "Check DNS server is reachable",
                ],
            },
        }
        if args.json:
            print(json.dumps(error_output, indent=2), file=sys.stderr)
        else:
            print(
                f"Unexpected error: {error_output['error']['message']}", file=sys.stderr
            )
        sys.exit(1)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nDiscovery interrupted by user.")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
