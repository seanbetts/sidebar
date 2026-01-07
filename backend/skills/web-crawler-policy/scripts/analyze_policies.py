#!/usr/bin/env python3
"""
Web Crawler Policy Analyzer

Analyzes robots.txt and llms.txt files across domains to understand
crawler permissions and AI content accessibility. Generates comprehensive
reports including optional LLM-powered marketing intelligence.
"""

import sys
import builtins
import json
import argparse
import asyncio
import csv
import os
import tempfile
import re
from pathlib import Path
from typing import Dict, List, Set, Optional, Any
from collections import defaultdict
from datetime import datetime
from urllib.parse import urlparse

import aiohttp
from tabulate import tabulate

# Add backend root for storage helpers
BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

try:
    from api.services.skill_file_ops_ingestion import (
        create_ingested_file,
        finalize_ingested_file,
        write_ai_markdown,
        write_derivative,
    )
except Exception:
    create_ingested_file = None
    finalize_ingested_file = None
    write_ai_markdown = None
    write_derivative = None
# Try to import subdomain scanner if available
try:
    sys.path.insert(0, str(Path(__file__).parent.parent.parent / "subdomain-discover" / "scripts"))
    from discover_subdomains import SubdomainScanner
    SUBDOMAIN_DISCOVERY_AVAILABLE = True
except ImportError:
    SUBDOMAIN_DISCOVERY_AVAILABLE = False

# Try to import LLM report generator if available
try:
    from llm_report_generator import create_report_generator, ReportConfig, generate_markdown_report
    LLM_AVAILABLE = True
except ImportError:
    LLM_AVAILABLE = False


# Default output directory (R2)
DEFAULT_OUTPUT_DIR = "Reports"


def _slugify(value: str) -> str:
    cleaned = re.sub(r"[^a-zA-Z0-9]+", "_", value.strip())
    return cleaned.strip("_").lower() or "artifact"


def _build_summary_markdown(
    main_domain: str,
    permission_data: Dict[str, Any],
    domains: Set[str],
) -> str:
    summary = permission_data.get("summary", {})
    lines = [
        f"# Crawler policy report for {main_domain}",
        "",
        "## Summary",
        "",
        f"- Domains analyzed: {summary.get('total_domains', len(domains))}",
        f"- Domains with robots.txt: {summary.get('domains_with_robots', 0)}",
        f"- Domains with llms.txt: {summary.get('domains_with_llms', 0)}",
        f"- Traditional crawlers found: {summary.get('traditional_crawlers_found', 0)}",
        f"- LLM crawlers found: {summary.get('llm_crawlers_found', 0)}",
        f"- Dual-purpose crawlers found: {summary.get('dual_purpose_crawlers_found', 0)}",
    ]
    llms_files = summary.get("llm_files_found")
    if llms_files is not None:
        lines.append(f"- Any llms.txt found: {'Yes' if llms_files else 'No'}")
    lines.extend(["", "## Domains", ""])
    lines.extend([f"- {domain}" for domain in sorted(domains)])
    return "\n".join(lines).rstrip() + "\n"


def normalize_domain(domain: str) -> str:
    """Normalize domain by stripping scheme/paths and removing www prefix."""
    cleaned = domain.strip()
    if "://" in cleaned:
        parsed = urlparse(cleaned)
        cleaned = parsed.netloc or parsed.path
    if "/" in cleaned:
        cleaned = cleaned.split("/", 1)[0]
    if ":" in cleaned:
        cleaned = cleaned.split(":", 1)[0]
    cleaned = cleaned.lower()
    if cleaned.startswith("www."):
        cleaned = cleaned[4:]
    return cleaned


class RobotsAnalyzer:
    """Analyzes robots.txt and llms.txt files and extracts crawler permissions."""

    def __init__(self, timeout: float = 10.0, save_robots: bool = False,
                 output_dir: Path = DEFAULT_OUTPUT_DIR, main_domain: str = "",
                 check_llms: bool = True):
        self.timeout = timeout
        self.save_robots = save_robots
        self.check_llms = check_llms
        self.output_dir = output_dir
        self.main_domain = main_domain
        self.robots_data: Dict[str, Dict] = {}

    async def fetch_robots_txt(self, session: aiohttp.ClientSession, domain: str) -> Optional[str]:
        """Fetch robots.txt content for a domain."""
        protocols = ['https', 'http']

        for protocol in protocols:
            robots_url = f"{protocol}://{domain}/robots.txt"
            try:
                async with session.get(robots_url, timeout=self.timeout) as response:
                    if response.status == 200:
                        content = await response.text()
                        return content
            except (aiohttp.ClientError, asyncio.TimeoutError, Exception):
                continue

        return None

    async def fetch_llms_txt(self, session: aiohttp.ClientSession, domain: str) -> Optional[str]:
        """Fetch llms.txt content for a domain."""
        protocols = ['https', 'http']

        for protocol in protocols:
            llms_url = f"{protocol}://{domain}/llms.txt"
            try:
                async with session.get(llms_url, timeout=self.timeout) as response:
                    if response.status == 200:
                        content = await response.text()
                        # Validate that this looks like a real llms.txt file, not HTML
                        if self._is_valid_llms_txt(content):
                            return content
            except (aiohttp.ClientError, asyncio.TimeoutError, Exception):
                continue

        return None

    def _is_valid_llms_txt(self, content: str) -> bool:
        """Check if content looks like a valid llms.txt file, not HTML or other formats."""
        if not content or len(content.strip()) == 0:
            return False

        content = content.strip().lower()

        # Reject HTML content
        if any(html_indicator in content for html_indicator in [
            '<!doctype', '<html', '<head>', '<body>', '<div', '<script', '<style',
            'content-type', 'charset=', '<meta', '<title>'
        ]):
            return False

        # Reject JSON content
        if content.startswith('{') and content.endswith('}'):
            return False

        # Reject XML content
        if content.startswith('<?xml') or '<xml' in content:
            return False

        # Accept content that looks like llms.txt (contains known directives or simple text)
        llms_indicators = [
            'llm-training:', 'ai-training:', 'model-training:',
            'llm-inference:', 'ai-inference:', 'model-inference:',
            'allowed', 'disallowed', 'forbidden', 'permitted',
            'contact:', 'policy:', 'policy-url:', 'llms.txt'
        ]

        # If it contains llms.txt indicators, it's probably valid
        if any(indicator in content for indicator in llms_indicators):
            return True

        # If it looks like markdown (has # headers or - lists) and doesn't contain HTML tags, it's likely valid
        if ('# ' in content or '- ' in content or '## ' in content) and not any(tag in content for tag in ['<html', '<head', '<body', '<script']):
            return True

        # If it's short plain text without HTML tags, might be valid
        if len(content) < 500 and not any(tag in content for tag in ['<', '>', '{', '}']):
            return True

        # Otherwise, probably not a real llms.txt file
        return False

    def parse_robots_txt(self, content: str) -> Dict[str, Dict[str, List[str]]]:
        """Parse robots.txt content and extract rules."""
        if not content:
            return {}

        rules = defaultdict(lambda: {'allow': [], 'disallow': []})
        current_user_agents = ['*']  # Track multiple user agents for shared rules

        for line in content.split('\n'):
            line = line.strip()
            if not line or line.startswith('#'):
                continue

            if line.lower().startswith('user-agent:'):
                user_agent = line.split(':', 1)[1].strip()
                # Check if we need to start a new group
                if (not current_user_agents or
                    any(ua in rules and (rules[ua]['allow'] or rules[ua]['disallow'])
                        for ua in current_user_agents)):
                    current_user_agents = [user_agent]
                else:
                    # Add to current group (no rules have been applied yet)
                    current_user_agents.append(user_agent)
            elif line.lower().startswith('allow:'):
                path = line.split(':', 1)[1].strip()
                for user_agent in current_user_agents:
                    if path:  # Only add non-empty paths
                        rules[user_agent]['allow'].append(path)
            elif line.lower().startswith('disallow:'):
                path = line.split(':', 1)[1].strip()
                for user_agent in current_user_agents:
                    if path:  # Only add non-empty paths
                        rules[user_agent]['disallow'].append(path)
                    # Handle empty disallow by ensuring user agent exists
                    if user_agent not in rules:
                        rules[user_agent] = {'allow': [], 'disallow': []}

        return dict(rules)

    def parse_llms_txt(self, content: str) -> Dict[str, str]:
        """Parse llms.txt content and extract LLM permissions."""
        if not content:
            return {}

        llm_rules = {}

        for line in content.split('\n'):
            line = line.strip()
            if not line or line.startswith('#'):
                continue

            # Parse different llms.txt formats
            if ':' in line:
                key, value = line.split(':', 1)
                key = key.strip().lower()
                value = value.strip()

                # Common llms.txt directives
                if key in ['llm-training', 'ai-training', 'model-training']:
                    llm_rules['training'] = value.lower()
                elif key in ['llm-inference', 'ai-inference', 'model-inference']:
                    llm_rules['inference'] = value.lower()
                elif key in ['contact', 'email']:
                    llm_rules['contact'] = value
                elif key in ['policy', 'policy-url']:
                    llm_rules['policy'] = value
                else:
                    # Store any other directive
                    llm_rules[key] = value
            elif line.lower() in ['allowed', 'disallowed', 'forbidden', 'permitted']:
                # Simple format
                llm_rules['default'] = line.lower()

        return llm_rules

    def save_robots_txt(self, domain: str, content: str, file_type: str = "robots") -> Optional[Path]:
        """Save robots.txt or llms.txt content to file system."""
        if not self.save_robots or not content:
            return None

        # Create single domain folder for all subdomains
        domain_folder = self.output_dir / self.main_domain
        domain_folder.mkdir(parents=True, exist_ok=True)

        # Create filename with subdomain and timestamp
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        # Replace dots with underscores for filename safety
        safe_domain = domain.replace('.', '_')
        output_file = domain_folder / f"{file_type}_{safe_domain}_{timestamp}.txt"

        # Create metadata header
        url_path = f"/{file_type}.txt"
        metadata = f"""# {file_type}.txt for {domain}
# Retrieved: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
# URL: https://{domain}{url_path} or http://{domain}{url_path}
---

"""

        try:
            with open(output_file, 'w', encoding='utf-8') as f:
                f.write(metadata)
                f.write(content)
            return output_file
        except Exception as e:
            print(f"Warning: Could not save {file_type}.txt for {domain}: {e}")
            return None

    async def analyze_domain_robots(self, session: aiohttp.ClientSession, domain: str) -> Dict:
        """Analyze robots.txt and llms.txt for a single domain."""
        # Fetch robots.txt
        robots_content = await self.fetch_robots_txt(session, domain)

        # Fetch llms.txt if enabled
        llms_content = None
        if self.check_llms:
            llms_content = await self.fetch_llms_txt(session, domain)

        # Handle case where neither file exists
        if robots_content is None and (not self.check_llms or llms_content is None):
            return {
                'domain': domain,
                'robots_found': False,
                'llms_found': False,
                'rules': {},
                'llms_rules': {},
                'error': 'No robots.txt or llms.txt found or accessible'
            }

        result = {'domain': domain}

        # Process robots.txt
        if robots_content:
            saved_path = self.save_robots_txt(domain, robots_content, "robots")
            rules = self.parse_robots_txt(robots_content)
            result.update({
                'robots_found': True,
                'rules': rules,
                'robots_content': robots_content
            })
            if saved_path:
                result['robots_saved_to'] = str(saved_path)
        else:
            result.update({
                'robots_found': False,
                'rules': {}
            })

        # Process llms.txt
        if self.check_llms:
            if llms_content:
                saved_path = self.save_robots_txt(domain, llms_content, "llms")
                llms_rules = self.parse_llms_txt(llms_content)
                result.update({
                    'llms_found': True,
                    'llms_rules': llms_rules,
                    'llms_content': llms_content
                })
                if saved_path:
                    result['llms_saved_to'] = str(saved_path)
            else:
                result.update({
                    'llms_found': False,
                    'llms_rules': {}
                })

        return result

    async def analyze_all_domains(self, domains: Set[str]) -> Dict[str, Dict]:
        """Analyze robots.txt for all provided domains."""
        async with aiohttp.ClientSession() as session:
            tasks = [self.analyze_domain_robots(session, domain) for domain in domains]
            results = await asyncio.gather(*tasks, return_exceptions=True)

            for result in results:
                if isinstance(result, dict) and 'domain' in result:
                    domain_key = result['domain']
                    self.robots_data[domain_key] = result

        # Apply consolidation after analysis
        self.robots_data = self._consolidate_after_analysis(self.robots_data)
        return self.robots_data

    def _consolidate_after_analysis(self, robots_data: Dict[str, Any]) -> Dict[str, Any]:
        """Consolidate www/non-www versions after analysis, keeping the one with more content."""
        consolidated_data = {}
        processed_bases = set()

        for domain, data in robots_data.items():
            base_domain = normalize_domain(domain)

            if base_domain in processed_bases:
                continue

            www_version = f"www.{base_domain}"

            # Check if both versions exist in our data
            base_data = robots_data.get(base_domain)
            www_data = robots_data.get(www_version)

            if base_data and www_data:
                # Both exist, choose the one with more content
                base_content = (base_data.get('robots_found', False) or
                              base_data.get('llms_found', False))
                www_content = (www_data.get('robots_found', False) or
                              www_data.get('llms_found', False))

                if base_content and not www_content:
                    consolidated_data[base_domain] = base_data
                elif www_content and not base_content:
                    consolidated_data[base_domain] = www_data
                    consolidated_data[base_domain]['domain'] = base_domain
                elif base_content and www_content:
                    # Both have content, prefer base domain
                    consolidated_data[base_domain] = base_data
                else:
                    # Neither has content, use base domain
                    consolidated_data[base_domain] = base_data
            elif base_data:
                consolidated_data[base_domain] = base_data
            elif www_data:
                consolidated_data[base_domain] = www_data
                consolidated_data[base_domain]['domain'] = base_domain

            processed_bases.add(base_domain)

        return consolidated_data


class CrawlerPermissionAnalyzer:
    """Analyzes and aggregates crawler permissions across domains."""

    def __init__(self, robots_data: Dict[str, Dict], include_llms: bool = True):
        self.robots_data = robots_data
        self.include_llms = include_llms

        # Standard LLM/AI crawlers
        self.standard_llm_crawlers = {
            'gptbot': {'description': 'OpenAI GPT training and research', 'provider': 'OpenAI'},
            'oai-searchbot': {'description': 'OpenAI search and indexing', 'provider': 'OpenAI'},
            'chatgpt-user': {'description': 'OpenAI ChatGPT user queries', 'provider': 'OpenAI'},
            'google-extended': {'description': 'Google AI training (Bard, Gemini)', 'provider': 'Google'},
            'claudebot': {'description': 'Anthropic Claude training and research', 'provider': 'Anthropic'},
            'claude-web': {'description': 'Anthropic Claude web browsing', 'provider': 'Anthropic'},
            'ccbot': {'description': 'Common Crawl (used by many AI companies)', 'provider': 'Common Crawl'},
            'meta-externalagent': {'description': 'Meta AI training and research', 'provider': 'Meta'},
            'perplexitybot': {'description': 'Perplexity AI search and training', 'provider': 'Perplexity'},
            'bytespider': {'description': 'ByteDance AI training', 'provider': 'ByteDance'},
            'amazonbot': {'description': 'Amazon AI services', 'provider': 'Amazon'},
        }

        # LLM crawler patterns to detect
        self.llm_crawler_patterns = {
            'openai', 'openai-crawl', 'bard', 'gemini', 'anthropic',
            'facebookbot', 'meta-ai', 'bing-ai', 'copilot', 'sydney',
            'common-crawl', 'cohere-ai', 'cohere', 'youbot', 'you.com',
            'character.ai', 'semanticscholarbot', 'linkedinbot', 'telegrambot',
            'chatbot', 'llm-crawler', 'ai-crawler', 'bytedance',
            'llm', 'gpt', 'ai-', 'ml-', 'neural', 'training'
        }

        # Dual-purpose crawlers
        self.dual_purpose_crawlers = {
            'googlebot': {'description': 'Google Search & AI Training', 'provider': 'Google'},
            'bingbot': {'description': 'Bing Search & AI Training', 'provider': 'Microsoft'},
            'twitterbot': {'description': 'Twitter Cards & AI Training', 'provider': 'X/Twitter'},
            'facebookexternalhit': {'description': 'Facebook Sharing & AI Training', 'provider': 'Meta'}
        }

    def is_llm_crawler(self, crawler_name: str) -> bool:
        """Check if a crawler should be classified as an LLM/AI crawler."""
        crawler_lower = crawler_name.lower()

        if crawler_lower in self.standard_llm_crawlers:
            return True

        return any(pattern in crawler_lower for pattern in self.llm_crawler_patterns)

    def is_dual_purpose_crawler(self, crawler_name: str) -> bool:
        """Check if a crawler is dual-purpose (search + AI)."""
        return crawler_name.lower() in self.dual_purpose_crawlers

    def get_traditional_crawlers(self) -> Set[str]:
        """Extract traditional (non-LLM) crawler names from robots.txt files."""
        crawlers = set()

        for domain_data in self.robots_data.values():
            if domain_data.get('robots_found'):
                for crawler in domain_data.get('rules', {}).keys():
                    if not self.is_llm_crawler(crawler) and not self.is_dual_purpose_crawler(crawler):
                        crawlers.add(crawler)

        return crawlers

    def get_additional_llm_crawlers(self) -> Set[str]:
        """Get additional LLM/AI crawlers found in robots.txt files beyond standard ones."""
        additional_crawlers = set()

        for domain_data in self.robots_data.values():
            if domain_data.get('robots_found'):
                for crawler in domain_data.get('rules', {}).keys():
                    if self.is_llm_crawler(crawler) and crawler.lower() not in self.standard_llm_crawlers:
                        additional_crawlers.add(crawler)

        return additional_crawlers

    def analyze_llms_files(self) -> Dict[str, Dict]:
        """Analyze llms.txt files separately from robots.txt."""
        llms_analysis = {}

        for domain, domain_data in self.robots_data.items():
            if domain_data.get('llms_found'):
                llms_rules = domain_data.get('llms_rules', {})
                llms_analysis[domain] = {
                    'found': True,
                    'rules': llms_rules,
                    'raw_content': domain_data.get('llms_content', '')
                }
            else:
                llms_analysis[domain] = {
                    'found': False,
                    'rules': {},
                    'raw_content': ''
                }

        return llms_analysis

    def get_dual_purpose_crawlers(self) -> Set[str]:
        """Get dual-purpose crawlers (used for both search and AI) from robots.txt files."""
        dual_crawlers = set()

        for domain_data in self.robots_data.values():
            if domain_data.get('robots_found'):
                for crawler in domain_data.get('rules', {}).keys():
                    if self.is_dual_purpose_crawler(crawler):
                        dual_crawlers.add(crawler)

        return dual_crawlers

    def has_any_llms_files(self) -> bool:
        """Check if any domains have llms.txt files."""
        return any(data.get('llms_found', False) for data in self.robots_data.values())

    def analyze_permissions(self) -> Dict[str, Any]:
        """Analyze permissions for crawlers across all domains."""
        traditional_crawlers = self.get_traditional_crawlers()
        found_dual_purpose_crawlers = self.get_dual_purpose_crawlers()
        found_additional_llm_crawlers = self.get_additional_llm_crawlers()

        results = {
            'robots_analysis': {
                'traditional': [],
                'llm': [],
                'dual_purpose': []
            },
            'llms_analysis': self.analyze_llms_files() if self.include_llms else {},
            'summary': {
                'total_domains': len(self.robots_data),
                'domains_with_robots': sum(1 for data in self.robots_data.values() if data.get('robots_found')),
                'domains_with_llms': sum(1 for data in self.robots_data.values() if data.get('llms_found')),
                'traditional_crawlers_found': len(traditional_crawlers),
                'llm_crawlers_found': len(self.standard_llm_crawlers) + len(found_additional_llm_crawlers),
                'dual_purpose_crawlers_found': len(found_dual_purpose_crawlers),
                'llm_files_found': self.has_any_llms_files()
            }
        }

        # Analyze traditional crawlers
        for crawler in traditional_crawlers:
            crawler_data = self._analyze_single_crawler(crawler, 'traditional')
            results['robots_analysis']['traditional'].append(crawler_data)

        # Always analyze standard LLM crawlers + any additional ones found
        all_llm_crawlers = set(self.standard_llm_crawlers.keys()) | found_additional_llm_crawlers
        for crawler in all_llm_crawlers:
            crawler_data = self._analyze_single_crawler(crawler, 'llm')
            crawler_info = self.standard_llm_crawlers.get(crawler, {'description': 'AI/LLM crawler', 'provider': 'Unknown'})
            crawler_data['description'] = crawler_info['description'] if isinstance(crawler_info, dict) else crawler_info
            crawler_data['provider'] = crawler_info.get('provider', 'Unknown') if isinstance(crawler_info, dict) else 'Unknown'
            results['robots_analysis']['llm'].append(crawler_data)

        # Analyze dual-purpose crawlers
        for crawler in found_dual_purpose_crawlers:
            crawler_data = self._analyze_single_crawler(crawler, 'dual_purpose')
            crawler_info = self.dual_purpose_crawlers.get(crawler.lower(), {'description': 'Dual-purpose crawler', 'provider': 'Unknown'})
            crawler_data['description'] = crawler_info['description'] if isinstance(crawler_info, dict) else crawler_info
            crawler_data['provider'] = crawler_info.get('provider', 'Unknown') if isinstance(crawler_info, dict) else 'Unknown'
            results['robots_analysis']['dual_purpose'].append(crawler_data)

        return results

    def _analyze_single_crawler(self, crawler: str, crawler_type: str) -> Dict:
        """Analyze permissions for a single crawler."""
        crawler_data = {
            'crawler': crawler,
            'type': crawler_type,
            'domains': {}
        }

        for domain, domain_data in self.robots_data.items():
            if not domain_data.get('robots_found'):
                crawler_data['domains'][domain] = 'No robots.txt'
                continue

            rules = domain_data.get('rules', {})

            # Look for specific rules for this crawler (case-insensitive)
            matched_rule = self._find_crawler_rule(crawler, rules)

            if matched_rule:
                rule = rules[matched_rule]
                allow_paths = rule.get('allow', [])
                disallow_paths = rule.get('disallow', [])

                # Handle empty disallow (which means allowed)
                if not disallow_paths and not allow_paths:
                    status = 'Allowed'
                elif disallow_paths == ['/']:
                    status = 'Fully Blocked'
                elif disallow_paths and not allow_paths:
                    status = f"Blocked ({len(disallow_paths)} rules)"
                elif allow_paths and not disallow_paths:
                    status = f"Allowed ({len(allow_paths)} rules)"
                elif allow_paths and disallow_paths:
                    status = f"Mixed ({len(allow_paths)} allow, {len(disallow_paths)} disallow)"
                else:
                    status = 'Allowed'

                crawler_data['domains'][domain] = status
            else:
                # Check if there's a wildcard rule
                if '*' in rules:
                    rule = rules['*']
                    allow_paths = rule.get('allow', [])
                    disallow_paths = rule.get('disallow', [])

                    if disallow_paths == ['/']:
                        status = 'Blocked (wildcard)'
                    elif disallow_paths:
                        status = f"Blocked (wildcard, {len(disallow_paths)} rules)"
                    else:
                        status = 'Allowed (wildcard)'
                else:
                    status = 'Allowed (default)'

                crawler_data['domains'][domain] = status

        return crawler_data

    def _find_crawler_rule(self, crawler: str, rules: Dict[str, Dict]) -> Optional[str]:
        """Find the most specific matching rule for a crawler in robots.txt rules."""
        crawler_lower = crawler.lower()

        # First, try exact case-insensitive match
        for rule_agent in rules.keys():
            if rule_agent.lower() == crawler_lower:
                return rule_agent

        # Define crawler aliases
        crawler_aliases = {
            'googlebot': ['googlebot', 'googlebot-image', 'googlebot-video', 'googlebot-news'],
            'bingbot': ['bingbot', 'msnbot', 'msnbot-media'],
            'gptbot': ['gptbot', 'openai', 'chatgpt-user'],
            'claudebot': ['claudebot', 'claude-web', 'anthropic'],
            'google-extended': ['google-extended', 'bard', 'gemini'],
            'facebookbot': ['facebookbot', 'facebookexternalhit', 'meta-externalagent'],
            'twitterbot': ['twitterbot', 'twitter'],
            'applebot': ['applebot'],
            'ccbot': ['ccbot', 'common-crawl'],
            'perplexitybot': ['perplexitybot', 'perplexity', 'perplexity-user'],
            'bytespider': ['bytespider', 'bytedance'],
            'amazonbot': ['amazonbot'],
            'oai-searchbot': ['oai-searchbot', 'openai-searchbot']
        }

        # Check if our crawler matches any known aliases
        matching_aliases = []
        for base_crawler, aliases in crawler_aliases.items():
            if crawler_lower == base_crawler or crawler_lower in aliases:
                matching_aliases.extend(aliases)
                break

        # Look for rules that match our crawler or its aliases
        if matching_aliases:
            for rule_agent in rules.keys():
                rule_agent_lower = rule_agent.lower()
                if rule_agent_lower in matching_aliases:
                    return rule_agent
                # Also check for partial matches
                for alias in matching_aliases:
                    if alias in rule_agent_lower or rule_agent_lower in alias:
                        return rule_agent

        return None


def prioritize_domains(domains: Set[str], main_domain: str) -> List[str]:
    """Sort domains with main domain first, then important subdomains."""
    domain_list = list(domains)
    prioritized = []

    # 1. Main domain first
    if main_domain in domain_list:
        prioritized.append(main_domain)
        domain_list.remove(main_domain)

    # 2. www version of main domain second
    www_main = f"www.{main_domain}"
    if www_main in domain_list:
        prioritized.append(www_main)
        domain_list.remove(www_main)

    # 3. Important public-facing subdomains
    important_patterns = ['docs.', 'api.', 'shop.', 'store.', 'support.', 'blog.', 'console.', 'status.', 'help.']
    important_domains = []
    remaining_domains = []

    for domain in domain_list:
        if any(domain.startswith(pattern) for pattern in important_patterns):
            important_domains.append(domain)
        else:
            remaining_domains.append(domain)

    # Sort each group alphabetically
    important_domains.sort()
    remaining_domains.sort()

    return prioritized + important_domains + remaining_domains


def create_output_summary(permission_data: Dict, domains: Set[str]) -> str:
    """Create a summary of the scan results."""
    summary = permission_data.get('summary', {})

    output = []
    output.append("\n" + "=" * 60)
    output.append("SCAN SUMMARY")
    output.append("=" * 60)
    output.append(f"Total domains analyzed: {summary.get('total_domains', 0)}")
    output.append(f"Domains with robots.txt: {summary.get('domains_with_robots', 0)}")
    output.append(f"Domains with llms.txt: {summary.get('domains_with_llms', 0)}")
    output.append(f"Traditional crawlers found: {summary.get('traditional_crawlers_found', 0)}")
    output.append(f"LLM/AI crawlers found: {summary.get('llm_crawlers_found', 0)}")
    output.append(f"Dual-purpose crawlers found: {summary.get('dual_purpose_crawlers_found', 0)}")
    output.append(f"LLM files discovered: {'Yes' if summary.get('llm_files_found') else 'No'}")
    output.append("=" * 60)

    return "\n".join(output)


def create_output_table(permission_data: Dict, domains: Set[str], main_domain: str = "") -> str:
    """Create a formatted table showing crawler permissions across domains."""
    if not permission_data:
        return "No crawler data found."

    ordered_domains = prioritize_domains(domains, main_domain)
    output_parts = []

    # ROBOTS.TXT ANALYSIS SECTION
    output_parts.append("\n" + "=" * 100)
    output_parts.append("ROBOTS.TXT ANALYSIS")
    output_parts.append("=" * 100)

    robots_analysis = permission_data.get('robots_analysis', {})

    # Traditional web crawlers
    traditional_crawlers = robots_analysis.get('traditional', [])
    if traditional_crawlers:
        output_parts.append("\nTraditional Web Crawlers:")
        output_parts.append("-" * 50)
        headers = ['Crawler'] + ordered_domains
        rows = []
        for crawler_info in traditional_crawlers:
            row = [crawler_info['crawler']]
            for domain in ordered_domains:
                status = crawler_info['domains'].get(domain, 'No robots.txt')
                row.append(status)
            rows.append(row)
        output_parts.append(tabulate(rows, headers=headers, tablefmt='grid'))

    # AI/LLM crawlers
    llm_crawlers = robots_analysis.get('llm', [])
    output_parts.append("\nAI/LLM Crawlers:")
    output_parts.append("-" * 50)
    headers = ['Provider', 'Crawler', 'Description'] + ordered_domains
    rows = []

    sorted_crawlers = sorted(llm_crawlers, key=lambda x: (x.get('provider', ''), x['crawler']))

    for crawler_info in sorted_crawlers:
        row = [crawler_info.get('provider', ''), crawler_info['crawler'], crawler_info.get('description', '')]
        for domain in ordered_domains:
            status = crawler_info['domains'].get(domain, 'No robots.txt')
            row.append(status)
        rows.append(row)
    output_parts.append(tabulate(rows, headers=headers, tablefmt='grid'))

    # Dual-purpose crawlers
    dual_purpose_crawlers = robots_analysis.get('dual_purpose', [])
    if dual_purpose_crawlers:
        output_parts.append("\nDual-Purpose Crawlers (Search + AI):")
        output_parts.append("-" * 50)
        headers = ['Provider', 'Crawler', 'Description'] + ordered_domains
        rows = []

        sorted_crawlers = sorted(dual_purpose_crawlers, key=lambda x: (x.get('provider', ''), x['crawler']))

        for crawler_info in sorted_crawlers:
            row = [crawler_info.get('provider', ''), crawler_info['crawler'], crawler_info.get('description', '')]
            for domain in ordered_domains:
                status = crawler_info['domains'].get(domain, 'No robots.txt')
                row.append(status)
            rows.append(row)
        output_parts.append(tabulate(rows, headers=headers, tablefmt='grid'))

    # LLMS.TXT ANALYSIS SECTION
    llms_analysis = permission_data.get('llms_analysis', {})
    if llms_analysis:
        output_parts.append("\n" + "=" * 100)
        output_parts.append("LLMS.TXT ANALYSIS")
        output_parts.append("=" * 100)

        domains_with_llms = [domain for domain, data in llms_analysis.items() if data.get('found')]

        if domains_with_llms:
            # Collect all unique directives
            all_directives = set()
            for domain_data in llms_analysis.values():
                if domain_data.get('found'):
                    all_directives.update(domain_data.get('rules', {}).keys())

            if all_directives:
                output_parts.append("\nLLMs.txt Directives Found:")
                output_parts.append("-" * 30)
                headers = ['Directive'] + ordered_domains
                rows = []

                for directive in sorted(all_directives):
                    row = [directive]
                    for domain in ordered_domains:
                        if domain in llms_analysis and llms_analysis[domain].get('found'):
                            rules = llms_analysis[domain].get('rules', {})
                            value = rules.get(directive, '-')
                            row.append(value)
                        else:
                            row.append('No llms.txt')
                    rows.append(row)

                output_parts.append(tabulate(rows, headers=headers, tablefmt='grid'))
        else:
            output_parts.append("\nNo llms.txt files found on any analyzed domains.")

    return "\n".join(output_parts)


def export_to_csv(permission_data: Dict, domains: Set[str], output_file: str,
                  output_dir: Path = DEFAULT_OUTPUT_DIR, main_domain: str = ""):
    """Export the analysis results to a CSV file."""
    # If output_file is just a filename, save it in the domain folder
    if not os.path.dirname(output_file) and main_domain:
        domain_folder = output_dir / main_domain
        domain_folder.mkdir(parents=True, exist_ok=True)
        output_file = str(domain_folder / output_file)

    with open(output_file, 'w', newline='', encoding='utf-8') as csvfile:
        ordered_domains = prioritize_domains(domains, main_domain)
        headers = ['analysis_type', 'crawler_type', 'provider', 'crawler', 'description'] + ordered_domains
        writer = csv.DictWriter(csvfile, fieldnames=headers)

        writer.writeheader()

        robots_analysis = permission_data.get('robots_analysis', {})

        # Export traditional crawlers
        for crawler_info in robots_analysis.get('traditional', []):
            row = {
                'analysis_type': 'robots.txt',
                'crawler_type': 'Traditional',
                'provider': '',
                'crawler': crawler_info['crawler'],
                'description': ''
            }
            for domain in ordered_domains:
                status = crawler_info['domains'].get(domain, 'No robots.txt')
                row[domain] = status
            writer.writerow(row)

        # Export LLM crawlers
        llm_crawlers = robots_analysis.get('llm', [])
        sorted_llm_crawlers = sorted(llm_crawlers, key=lambda x: (x.get('provider', ''), x['crawler']))

        for crawler_info in sorted_llm_crawlers:
            row = {
                'analysis_type': 'robots.txt',
                'crawler_type': 'LLM/AI',
                'provider': crawler_info.get('provider', ''),
                'crawler': crawler_info['crawler'],
                'description': crawler_info.get('description', '')
            }
            for domain in ordered_domains:
                status = crawler_info['domains'].get(domain, 'No robots.txt')
                row[domain] = status
            writer.writerow(row)

        # Export dual-purpose crawlers
        dual_purpose_crawlers = robots_analysis.get('dual_purpose', [])
        sorted_dual_purpose_crawlers = sorted(dual_purpose_crawlers, key=lambda x: (x.get('provider', ''), x['crawler']))

        for crawler_info in sorted_dual_purpose_crawlers:
            row = {
                'analysis_type': 'robots.txt',
                'crawler_type': 'Dual-Purpose',
                'provider': crawler_info.get('provider', ''),
                'crawler': crawler_info['crawler'],
                'description': crawler_info.get('description', '')
            }
            for domain in ordered_domains:
                status = crawler_info['domains'].get(domain, 'No robots.txt')
                row[domain] = status
            writer.writerow(row)

        # Export llms.txt analysis
        llms_analysis = permission_data.get('llms_analysis', {})
        if llms_analysis:
            # Collect all unique directives
            all_directives = set()
            for domain_data in llms_analysis.values():
                if domain_data.get('found'):
                    all_directives.update(domain_data.get('rules', {}).keys())

            # Export each directive as a row
            for directive in sorted(all_directives):
                row = {
                    'analysis_type': 'llms.txt',
                    'crawler_type': 'Directive',
                    'provider': '',
                    'crawler': directive,
                    'description': 'LLM policy directive'
                }
                for domain in ordered_domains:
                    if domain in llms_analysis and llms_analysis[domain].get('found'):
                        rules = llms_analysis[domain].get('rules', {})
                        value = rules.get(directive, 'Not specified')
                        row[domain] = value
                    else:
                        row[domain] = 'No llms.txt'
                writer.writerow(row)


async def main():
    """Main entry point for policy analysis script."""
    parser = argparse.ArgumentParser(
        description='Analyze robots.txt and llms.txt policies across domains',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=f"""
Default Output Directory: {DEFAULT_OUTPUT_DIR}

Examples:
  # Analyze domain with subdomain discovery
  %(prog)s example.com

  # Analyze specific domains (no discovery)
  %(prog)s --domains example.com api.example.com docs.example.com

  # Full analysis with all outputs
  %(prog)s example.com --all

  # Generate LLM marketing report
  %(prog)s example.com --report

  # Save robots.txt files
  %(prog)s example.com --save-robots

  # Custom output location
  %(prog)s example.com --output-dir ~/my-reports --all

Requirements:
  - OPENAI_API_KEY for LLM reports (set via Doppler or environment variable)
        """
    )

    # Domain input (mutually exclusive)
    domain_group = parser.add_mutually_exclusive_group(required=True)
    domain_group.add_argument('domain', nargs='?', help='Target domain to analyze (discovers subdomains)')
    domain_group.add_argument('--domains', nargs='+', help='Specific domains to analyze (skips discovery)')

    # Discovery options
    parser.add_argument('--no-discover', action='store_true', help='Skip subdomain discovery')
    parser.add_argument('--wordlist', help='Custom wordlist for subdomain discovery')
    parser.add_argument('--dns-timeout', type=float, default=5.0, help='DNS timeout in seconds (default: 5.0)')

    # Analysis options
    parser.add_argument('--timeout', type=float, default=10.0, help='HTTP timeout in seconds (default: 10.0)')
    parser.add_argument('--no-llms', action='store_true', help='Skip checking llms.txt files')
    parser.add_argument('--save-robots', action='store_true', help='Save robots.txt and llms.txt files to disk')
    parser.add_argument('--output-dir', default=DEFAULT_OUTPUT_DIR, help=f'R2 output folder (default: {DEFAULT_OUTPUT_DIR})')

    # Output options
    parser.add_argument('--json', action='store_true', help='Output results in JSON format to stdout')
    parser.add_argument('--output', '-o', help='Export results to CSV file')
    parser.add_argument('--json-output', help='Export raw data to JSON file')
    parser.add_argument('--no-table', action='store_true', help='Skip console table output')
    parser.add_argument('--all', action='store_true', help='Save all output formats with default names')

    # LLM report options
    parser.add_argument('--report', action='store_true', help='Generate LLM-powered marketing intelligence report')
    parser.add_argument('--llm-model', default='gpt-4o', help='LLM model to use (default: gpt-4o)')
    parser.add_argument('--llm-api-key', help='OpenAI API key (or use OPENAI_API_KEY from Doppler/env)')
    parser.add_argument('--report-output', help='Output path for markdown report')
    parser.add_argument('--user-id', required=True, help='User id for storage access')

    args = parser.parse_args()

    # Handle --all option
    if args.all:
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        args.save_robots = True
        args.report = True
        if not args.output:
            args.output = f"crawler_analysis_{timestamp}.csv"
        if not args.json_output:
            args.json_output = f"scan_results_{timestamp}.json"
        if not args.report_output:
            args.report_output = f"analysis_report_{timestamp}.md"

    if args.json:
        args.no_table = True
        args.output = None
        args.json_output = None
        args.save_robots = False
        args.report = False

        original_print = builtins.print

        def _print(*values, **kwargs):
            if "file" not in kwargs:
                kwargs["file"] = sys.stderr
            return original_print(*values, **kwargs)

        builtins.print = _print

    # Validate report options
    if args.report and not LLM_AVAILABLE:
        print("Error: --report requires llm_report_generator.py module", file=sys.stderr)
        sys.exit(1)

    # Determine main domain for output organization
    if args.domain:
        main_domain = args.domain
    elif args.domains:
        # Use first domain as main domain
        main_domain = args.domains[0]
    else:
        print("Error: Must specify either domain or --domains", file=sys.stderr)
        sys.exit(1)

    main_domain = normalize_domain(main_domain)
    r2_base = (args.output_dir or DEFAULT_OUTPUT_DIR).strip("/")
    local_output_dir = Path(tempfile.mkdtemp(prefix="crawler-reports-"))

    try:
        # Determine which domains to analyze
        if args.domains:
            # Use specified domains
            domains_to_analyze = {normalize_domain(domain) for domain in args.domains}
            print(f"Analyzing {len(domains_to_analyze)} specified domains")
        elif args.no_discover:
            # Just analyze the main domain
            domains_to_analyze = {main_domain}
            print(f"Analyzing domain: {main_domain}")
        else:
            # Discover subdomains
            if not SUBDOMAIN_DISCOVERY_AVAILABLE:
                print("Error: Subdomain discovery not available. Use --domains or --no-discover", file=sys.stderr)
                sys.exit(1)

            print(f"Starting subdomain discovery for: {main_domain}")

            # Load wordlist if provided
            wordlist = None
            if args.wordlist:
                try:
                    with open(args.wordlist, 'r', encoding='utf-8') as f:
                        wordlist = [line.strip() for line in f if line.strip()]
                except FileNotFoundError:
                    print(f"Error: Wordlist file '{args.wordlist}' not found", file=sys.stderr)
                    sys.exit(1)

            # Discover subdomains
            scanner = SubdomainScanner(main_domain, timeout=args.timeout, dns_timeout=args.dns_timeout)
            discovered = await scanner.discover_subdomains(wordlist)
            domains_to_analyze = {normalize_domain(domain) for domain in discovered}

            print(f"Found {len(domains_to_analyze)} domains/subdomains:")
            for subdomain in sorted(domains_to_analyze):
                print(f"  - {subdomain}")

        print("\nAnalyzing robots.txt files...")
        if not args.no_llms:
            print("Also checking for llms.txt files...")
        if args.save_robots:
            file_types = "robots.txt and llms.txt files" if not args.no_llms else "robots.txt files"
            print(f"{file_types} will be saved to: {r2_base}/{main_domain}/")

        # Analyze robots.txt files
        output_dir = local_output_dir
        analyzer = RobotsAnalyzer(
            timeout=args.timeout,
            save_robots=args.save_robots,
            output_dir=output_dir,
            main_domain=main_domain,
            check_llms=not args.no_llms
        )
        robots_data = await analyzer.analyze_all_domains(domains_to_analyze)

        # Update domains to match consolidated results
        domains_to_analyze = set(robots_data.keys())

        # Report saved files
        if args.save_robots:
            robots_saved = sum(1 for data in robots_data.values() if data.get('robots_saved_to'))
            llms_saved = sum(1 for data in robots_data.values() if data.get('llms_saved_to')) if not args.no_llms else 0
            if not args.no_llms and llms_saved > 0:
                print(f"Saved {robots_saved} robots.txt and {llms_saved} llms.txt files to disk.")
            else:
                print(f"Saved {robots_saved} robots.txt files to disk.")

        # Analyze crawler permissions
        permission_analyzer = CrawlerPermissionAnalyzer(robots_data, include_llms=not args.no_llms)
        permission_data = permission_analyzer.analyze_permissions()
        output_data = {
            'domain': main_domain,
            'discovered_domains': sorted(domains_to_analyze),
            'robots_data': robots_data,
            'permission_analysis': permission_data
        }

        # Output results
        if args.json:
            args.no_table = True

        if not args.no_table:
            print(create_output_summary(permission_data, domains_to_analyze))
            print(create_output_table(permission_data, domains_to_analyze, main_domain))

        # Export to CSV
        if args.output:
            export_to_csv(permission_data, domains_to_analyze, args.output, output_dir, main_domain)
            if not os.path.dirname(args.output):
                actual_output_path = f"{r2_base}/{main_domain}/{args.output}"
            else:
                actual_output_path = args.output
            print(f"\nResults exported to: {actual_output_path}")

        # Export raw data to JSON
        if args.json_output:
            json_output_path = args.json_output
            if not os.path.dirname(args.json_output):
                domain_folder = output_dir / main_domain
                domain_folder.mkdir(parents=True, exist_ok=True)
                json_output_path = str(domain_folder / args.json_output)

            with open(json_output_path, 'w', encoding='utf-8') as f:
                json.dump(output_data, f, indent=2)
            if not os.path.dirname(args.json_output):
                print(f"Raw data exported to: {r2_base}/{main_domain}/{args.json_output}")
            else:
                print(f"Raw data exported to: {json_output_path}")

        # Generate LLM-powered report if requested
        if args.report:
            print("\nGenerating intelligent analysis report...")
            try:
                # Prepare full scan data
                full_scan_data = {
                    'domain': main_domain,
                    'discovered_domains': sorted(domains_to_analyze),
                    'robots_data': robots_data,
                    'permission_analysis': permission_data
                }

                # Get API key from Doppler or environment
                api_key = args.llm_api_key or os.getenv('OPENAI_API_KEY')

                # Configure LLM
                llm_config = ReportConfig(
                    provider='openai',
                    model=args.llm_model,
                    api_key=api_key,
                    temperature=0.1,
                    max_tokens=4000
                )

                # Generate report
                report_generator = create_report_generator(llm_config)
                analysis_result = await report_generator.generate_report_analysis(full_scan_data)

                # Generate markdown report
                markdown_report = generate_markdown_report(analysis_result, full_scan_data)

                # Save reports
                report_output_path = args.report_output
                if not report_output_path:
                    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                    report_output_path = f"analysis_report_{timestamp}.md"

                # Handle relative paths - save in domain folder
                if not os.path.dirname(report_output_path):
                    domain_folder = output_dir / main_domain
                    domain_folder.mkdir(parents=True, exist_ok=True)
                    report_output_path = str(domain_folder / report_output_path)

                    # Also save the analysis JSON
                    analysis_json_path = str(domain_folder / Path(report_output_path).stem) + '_analysis.json'
                    with open(analysis_json_path, 'w', encoding='utf-8') as f:
                        json.dump(analysis_result, f, indent=2)
                    print(f"Analysis data saved to: {r2_base}/{main_domain}/{Path(analysis_json_path).name}")

                # Save markdown report
                with open(report_output_path, 'w', encoding='utf-8') as f:
                    f.write(markdown_report)

                if not os.path.dirname(report_output_path):
                    print(f"Intelligence report generated: {r2_base}/{main_domain}/{Path(report_output_path).name}")
                else:
                    print(f"Intelligence report generated: {report_output_path}")

            except Exception as e:
                print(f"Error generating report: {e}", file=sys.stderr)
                print("Continuing with standard output...")

        # Write outputs to ingestion-backed storage
        if create_ingested_file is None or write_derivative is None or write_ai_markdown is None:
            raise RuntimeError("Storage dependencies are unavailable")

        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        report_filename = f"crawler_policy_{timestamp}.md"
        report_path = f"{r2_base}/{main_domain}/{report_filename}".strip("/")
        summary_markdown = _build_summary_markdown(main_domain, permission_data, domains_to_analyze)

        record = create_ingested_file(
            args.user_id,
            report_filename,
            "text/markdown",
            size=len(summary_markdown.encode("utf-8")),
            source_url=f"https://{main_domain}",
            source_metadata={
                "provider": "web-crawler-policy",
                "domain": main_domain,
                "domains_analyzed": sorted(domains_to_analyze),
            },
            path=report_path,
        )

        derivatives: list[dict[str, Any]] = []
        domain_folder = output_dir / main_domain
        if domain_folder.exists():
            for file_path in sorted(domain_folder.rglob("*")):
                if not file_path.is_file():
                    continue
                filename = file_path.name
                stem = _slugify(file_path.stem)
                kind = None
                if filename.startswith("robots_"):
                    kind = f"robots_txt_{stem}"
                elif filename.startswith("llms_"):
                    kind = f"llms_txt_{stem}"
                elif filename.endswith(".csv"):
                    kind = "analysis_csv"
                elif filename.endswith(".json"):
                    kind = "analysis_json" if "analysis" in filename else f"scan_json_{stem}"
                elif filename.endswith(".md"):
                    kind = "report_md"
                else:
                    kind = f"artifact_{stem}"
                derivatives.append(
                    write_derivative(
                        args.user_id,
                        record,
                        file_path,
                        kind=kind,
                    )
                )

        frontmatter = {
            "source_url": f"https://{main_domain}",
            "source_type": "web-crawler-policy",
            "ingestion": {
                "skill": "web-crawler-policy",
                "model": args.llm_model if args.report else None,
                "language": None,
                "duration_seconds": None,
                "size_bytes": len(summary_markdown.encode("utf-8")),
            },
        }
        ai_derivative = write_ai_markdown(
            args.user_id,
            record,
            summary_markdown,
            frontmatter=frontmatter,
            derivative_items=[
                {
                    "kind": item["kind"],
                    "path": item["storage_key"],
                    "content_type": item.get("content_type") or item.get("mime"),
                }
                for item in derivatives
            ],
        )
        derivatives.append(ai_derivative)
        payload = finalize_ingested_file(args.user_id, record, derivatives)

        print(f"\nScan complete. Analyzed {len(domains_to_analyze)} domains.")
        if args.json:
            sys.stdout.write(json.dumps({"success": True, "data": payload}, indent=2))
        sys.exit(0)

    except Exception as e:
        error_output = {
            'success': False,
            'error': {
                'type': 'UnexpectedError',
                'message': str(e),
                'suggestions': [
                    'Check network connectivity',
                    'Verify domain is accessible',
                    'Check Doppler configuration for API keys',
                    'Try with --verbose for more details'
                ]
            }
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nAnalysis interrupted by user.")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
