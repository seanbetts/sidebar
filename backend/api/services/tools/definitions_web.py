"""Web tool definitions."""
from __future__ import annotations

from api.services.tools import parameter_mapper as pm


def get_web_definitions() -> dict:
    return {
        "Discover Subdomains": {
            "description": "Discover subdomains for a given domain.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "domain": {"type": "string"},
                    "wordlist": {"type": "string"},
                    "timeout": {"type": "integer"},
                    "dns_timeout": {"type": "integer"},
                    "no_filter": {"type": "boolean"},
                    "verbose": {"type": "boolean"},
                },
                "required": ["domain"],
            },
            "skill": "subdomain-discover",
            "script": "discover_subdomains.py",
            "build_args": pm.build_subdomain_discover_args,
        },
        "Crawler Policy Check": {
            "description": "Analyze a site's crawler policy for robots.txt and llms.txt.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "domain": {"type": "string"},
                    "no_discover": {"type": "boolean"},
                    "wordlist": {"type": "string"},
                    "timeout": {"type": "integer"},
                    "dns_timeout": {"type": "integer"},
                    "no_llms": {"type": "boolean"},
                },
                "required": ["domain"],
            },
            "skill": "web-crawler-policy",
            "script": "analyze_policies.py",
            "build_args": pm.build_crawler_policy_args,
        },
        "Save Website": {
            "description": "Save a website to the database (visible in UI).",
            "input_schema": {
                "type": "object",
                "properties": {
                    "url": {"type": "string", "description": "Website URL"},
                },
                "required": ["url"],
            },
            "skill": "web-save",
            "script": "save_url.py",
            "build_args": pm.build_website_save_args,
        },
        "Delete Website": {
            "description": "Delete a website in the database by ID.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "website_id": {"type": "string", "description": "Website UUID"},
                },
                "required": ["website_id"],
            },
            "skill": "web-save",
            "script": "delete_website.py",
            "build_args": pm.build_website_delete_args,
        },
        "Pin Website": {
            "description": "Pin or unpin a website in the database.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "website_id": {"type": "string"},
                    "pinned": {"type": "boolean"},
                },
                "required": ["website_id", "pinned"],
            },
            "skill": "web-save",
            "script": "pin_website.py",
            "build_args": pm.build_website_pin_args,
        },
        "Archive Website": {
            "description": "Archive or unarchive a website in the database.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "website_id": {"type": "string"},
                    "archived": {"type": "boolean"},
                },
                "required": ["website_id", "archived"],
            },
            "skill": "web-save",
            "script": "archive_website.py",
            "build_args": pm.build_website_archive_args,
        },
        "Read Website": {
            "description": "Fetch a website by ID.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "website_id": {"type": "string"},
                },
                "required": ["website_id"],
            },
            "skill": "web-save",
            "script": "read_website.py",
            "build_args": pm.build_website_read_args,
        },
        "List Websites": {
            "description": "List websites with optional filters.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "domain": {"type": "string"},
                    "pinned": {"type": "boolean"},
                    "archived": {"type": "boolean"},
                    "created_after": {"type": "string"},
                    "created_before": {"type": "string"},
                    "updated_after": {"type": "string"},
                    "updated_before": {"type": "string"},
                    "opened_after": {"type": "string"},
                    "opened_before": {"type": "string"},
                    "published_after": {"type": "string"},
                    "published_before": {"type": "string"},
                    "title": {"type": "string"},
                },
            },
            "skill": "web-save",
            "script": "list_websites.py",
            "build_args": pm.build_website_list_args,
        },
    }
