#!/usr/bin/env python3
"""
LLM-powered Report Generator for Robots.txt Analysis

Provides an abstraction layer for generating intelligent reports
from subdomain and robots.txt scanning data using various LLM providers.
"""

import json
import time
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Dict, List, Optional, Any
import os
import openai
from openai import OpenAI


@dataclass
class ReportConfig:
    """Configuration for report generation."""
    provider: str = "openai"
    model: str = "gpt-4o-2024-08-06"
    temperature: float = 0.1
    max_tokens: int = 4000
    timeout: int = 60
    max_retries: int = 3
    retry_delay: float = 1.0
    api_key: Optional[str] = None


class LLMReportGenerator(ABC):
    """Abstract base class for LLM report generators."""
    
    def __init__(self, config: ReportConfig):
        self.config = config
        
    @abstractmethod
    async def generate_report_analysis(self, scan_data: Dict[str, Any]) -> Dict[str, Any]:
        """Generate a structured analysis report from scan data."""
        pass
    
    def prepare_data_for_llm(self, scan_data: Dict[str, Any]) -> Dict[str, Any]:
        """Prepare and potentially summarize data for LLM consumption."""
        # Extract key information while reducing size
        prepared_data = {
            'domain': scan_data.get('domain'),
            'total_domains': len(scan_data.get('discovered_domains', [])),
            'discovered_domains': scan_data.get('discovered_domains', [])[:20],
            'summary': scan_data.get('permission_analysis', {}).get('summary', {}),
        }
        
        # Summarize robots data
        robots_data = scan_data.get('robots_data', {})
        prepared_robots = {}
        
        for domain, data in robots_data.items():
            prepared_robots[domain] = {
                'robots_found': data.get('robots_found', False),
                'llms_found': data.get('llms_found', False),
                'rule_count': sum(len(rules.get('allow', [])) + len(rules.get('disallow', [])) 
                                for rules in data.get('rules', {}).values()),
                'user_agents': list(data.get('rules', {}).keys())[:10],
                'has_llm_specific_rules': any('llm' in ua.lower() or 'gpt' in ua.lower() or 
                                            'claude' in ua.lower() or 'openai' in ua.lower()
                                            for ua in data.get('rules', {}).keys()),
                'sample_disallows': self._get_sample_rules(data.get('rules', {}), 'disallow'),
                'sample_allows': self._get_sample_rules(data.get('rules', {}), 'allow')
            }
        
        prepared_data['robots_summary'] = prepared_robots
        
        # Include permission analysis
        permission_analysis = scan_data.get('permission_analysis', {})
        prepared_data['permission_analysis'] = {
            'summary': permission_analysis.get('summary', {}),
            'llm_crawler_count': len(permission_analysis.get('robots_analysis', {}).get('llm', [])),
            'traditional_crawler_count': len(permission_analysis.get('robots_analysis', {}).get('traditional', [])),
            'llm_crawler_examples': [crawler['crawler'] for crawler in 
                                   permission_analysis.get('robots_analysis', {}).get('llm', [])[:10]],
            'llms_files_found': permission_analysis.get('llms_analysis', {})
        }
        
        return prepared_data
    
    def _get_sample_rules(self, rules_dict: Dict[str, Dict], rule_type: str, max_samples: int = 5) -> List[str]:
        """Extract sample rules of a given type."""
        samples = []
        for user_agent, rules in rules_dict.items():
            paths = rules.get(rule_type, [])
            for path in paths[:max_samples]:
                if len(samples) >= max_samples:
                    break
                samples.append(f"{user_agent}: {path}")
            if len(samples) >= max_samples:
                break
        return samples


class OpenAIReportGenerator(LLMReportGenerator):
    """OpenAI-based report generator using GPT-4o with structured outputs."""
    
    def __init__(self, config: ReportConfig):
        super().__init__(config)
        api_key = config.api_key or os.getenv('OPENAI_API_KEY')
        if not api_key:
            raise ValueError("OpenAI API key required. Set OPENAI_API_KEY environment variable or pass in config.")
        self.client = OpenAI(api_key=api_key)
    
    async def generate_report_analysis(self, scan_data: Dict[str, Any]) -> Dict[str, Any]:
        """Generate structured analysis using OpenAI's Structured Outputs."""
        prepared_data = self.prepare_data_for_llm(scan_data)
        
        # Simplified JSON schema for reliable Structured Outputs
        response_schema = {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "brand_analysis_overview": {
                    "type": "string",
                    "description": "Executive summary of how this brand's content policies affect AI representation"
                },
                "ai_content_accessibility": {
                    "type": "string",
                    "enum": ["highly_accessible", "moderately_accessible", "restricted", "heavily_restricted"],
                    "description": "Overall accessibility of brand content to AI training systems"
                },
                "key_findings": {
                    "type": "array",
                    "description": "Top 3-5 most important insights about brand AI representation",
                    "items": {
                        "type": "object",
                        "additionalProperties": False,
                        "properties": {
                            "finding": {"type": "string"},
                            "impact": {"type": "string", "enum": ["high", "medium", "low"]},
                            "business_implication": {"type": "string"}
                        },
                        "required": ["finding", "impact", "business_implication"]
                    }
                },
                "content_gaps": {
                    "type": "array",
                    "description": "What important content types are blocked from AI training",
                    "items": {"type": "string"}
                },
                "competitive_implications": {
                    "type": "string",
                    "description": "How current policies might affect competitive positioning in AI-powered discovery"
                },
                "strategic_recommendations": {
                    "type": "array",
                    "description": "Top actionable recommendations for improving AI brand presence",
                    "items": {"type": "string"}
                },
                "likely_ai_representation": {
                    "type": "string",
                    "description": "How complete and accurate the brand's representation likely is in current LLMs"
                }
            },
            "required": ["brand_analysis_overview", "ai_content_accessibility", "key_findings", "content_gaps", 
                        "competitive_implications", "strategic_recommendations", "likely_ai_representation"]
        }
        
        prompt = self._build_analysis_prompt(prepared_data)
        
        for attempt in range(self.config.max_retries):
            try:
                response = self.client.chat.completions.create(
                    model=self.config.model,
                    messages=[
                        {
                            "role": "system",
                            "content": "You are a brand marketing consultant and AI strategy expert specializing in analyzing how brands' content policies affect their representation in large language models."
                        },
                        {
                            "role": "user", 
                            "content": prompt
                        }
                    ],
                    response_format={
                        "type": "json_schema",
                        "json_schema": {
                            "name": "brand_ai_analysis",
                            "strict": True,
                            "schema": response_schema
                        }
                    },
                    temperature=self.config.temperature,
                    max_tokens=self.config.max_tokens,
                    timeout=self.config.timeout
                )
                
                result = json.loads(response.choices[0].message.content)
                
                print("✅ Structured Outputs validation successful - received all required fields")
                return result
                
            except (openai.APITimeoutError, openai.RateLimitError) as e:
                if attempt < self.config.max_retries - 1:
                    wait_time = self.config.retry_delay * (2 ** attempt)
                    print(f"Rate limited or timeout, retrying in {wait_time}s... (attempt {attempt + 1})")
                    time.sleep(wait_time)
                    continue
                raise Exception(f"OpenAI API failed after {self.config.max_retries} attempts: {e}")
            
            except json.JSONDecodeError as e:
                if attempt < self.config.max_retries - 1:
                    print(f"Invalid JSON response, retrying... (attempt {attempt + 1})")
                    continue
                raise Exception(f"Failed to parse JSON response after {self.config.max_retries} attempts: {e}")
            
            except Exception as e:
                if attempt < self.config.max_retries - 1:
                    print(f"API error, retrying... (attempt {attempt + 1}): {e}")
                    time.sleep(self.config.retry_delay)
                    continue
                raise Exception(f"OpenAI API failed: {e}")
        
        raise Exception("All retry attempts exhausted")
    
    def _build_analysis_prompt(self, data: Dict[str, Any]) -> str:
        """Build the marketing-focused analysis prompt for the LLM."""
        domain = data.get('domain', 'Unknown')
        total_domains = data.get('total_domains', 0)
        summary = data.get('summary', {})
        
        prompt = f"""Analyze the following robots.txt scan data for {domain} from a BRAND MARKETING and AI REPRESENTATION perspective.

BRAND & DOMAIN OVERVIEW:
- Target Brand/Domain: {domain}
- Total Brand Subdomains Discovered: {total_domains}
- Subdomains with robots.txt policies: {summary.get('domains_with_robots', 0)}
- Subdomains with llms.txt (AI-specific policies): {summary.get('domains_with_llms', 0)}
- AI/LLM Crawlers Analyzed: {summary.get('llm_crawlers_found', 0)}

BRAND CONTENT DOMAINS DISCOVERED:
{json.dumps(data.get('discovered_domains', []), indent=2)}

CONTENT ACCESS POLICIES SUMMARY:
{json.dumps(data.get('robots_summary', {}), indent=2)}

Focus your analysis on MARKETING VALUE and BRAND REPRESENTATION. Return a comprehensive JSON analysis."""
        
        return prompt


def generate_markdown_report(analysis: Dict[str, Any], scan_data: Dict[str, Any]) -> str:
    """Generate a comprehensive marketing-focused markdown report."""
    domain = scan_data.get('domain', 'Unknown')
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S UTC")
    
    md = []
    
    # Header
    md.append(f"# Brand AI Representation Analysis: {domain}")
    md.append("**Comprehensive Marketing Intelligence Report**")
    md.append(f"*Generated: {timestamp}*")
    md.append("")
    
    # Executive Summary
    md.append("## Executive Summary")
    md.append(analysis.get('brand_analysis_overview', 'No overview available'))
    md.append("")
    
    # Key Metrics
    ai_accessibility = analysis.get('ai_content_accessibility', 'unknown').replace('_', ' ').title()
    md.append("### Key Performance Indicators")
    md.append("| Metric | Status |")
    md.append("|--------|--------|")
    md.append(f"| **AI Content Accessibility** | {ai_accessibility} |")
    md.append("")
    
    # Key Findings
    findings = analysis.get('key_findings', [])
    if findings:
        md.append("## Key Strategic Findings")
        for i, finding in enumerate(findings, 1):
            impact = finding.get('impact', '').upper()
            md.append(f"### Finding #{i}: {finding.get('finding', 'Unknown')} [{impact} IMPACT]")
            md.append(finding.get('business_implication', 'No implications'))
            md.append("")
    
    # Content Gaps
    gaps = analysis.get('content_gaps', [])
    if gaps:
        md.append("## Content Gaps")
        for gap in gaps:
            md.append(f"- {gap}")
        md.append("")
    
    # Competitive Implications
    md.append("## Competitive Positioning Impact")
    md.append(analysis.get('competitive_implications', 'No analysis available'))
    md.append("")
    
    # Recommendations
    recommendations = analysis.get('strategic_recommendations', [])
    if recommendations:
        md.append("## Strategic Recommendations")
        for i, rec in enumerate(recommendations, 1):
            md.append(f"{i}. {rec}")
        md.append("")
    
    # AI Representation
    md.append("## How LLMs Currently Represent Your Brand")
    md.append(analysis.get('likely_ai_representation', 'No assessment available'))
    md.append("")
    
    return "\n".join(md)


def create_report_generator(config: ReportConfig) -> LLMReportGenerator:
    """Factory function to create appropriate report generator."""
    if config.provider.lower() == "openai":
        return OpenAIReportGenerator(config)
    else:
        raise ValueError(f"Unsupported provider: {config.provider}")
