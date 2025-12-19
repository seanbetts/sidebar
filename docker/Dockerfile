FROM python:3.11-slim

# Install essential Unix tools for skill development and CA certificates
RUN apt-get update && apt-get install -y \
    git \
    curl \
    vim \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install uv (Python package manager)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Create app directory for installing dependencies
RUN mkdir -p /app
WORKDIR /app

# Copy dependency files
COPY pyproject.toml ./

# Install project dependencies (not dev dependencies)
# Note: Using pip instead of uv because uv lacks --trusted-host equivalent for
# handling corporate proxies/firewalls with self-signed certificates
RUN pip install --no-cache-dir --trusted-host pypi.org --trusted-host pypi.python.org --trusted-host files.pythonhosted.org -e .

# Skills will be mounted at /skills
RUN mkdir -p /skills
WORKDIR /skills

# Default command: interactive bash
CMD ["/bin/bash"]
