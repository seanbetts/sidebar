FROM python:3.11-slim

# Install essential Unix tools and Doppler CLI dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    vim \
    ca-certificates \
    apt-transport-https \
    gnupg \
    && rm -rf /var/lib/apt/lists/*

# Doppler CLI installation skipped due to corporate firewall restrictions
# DOPPLER_TOKEN is available as environment variable (configured in docker-compose.yml)
# You can use doppler run from the host, or manually install doppler in the container if needed:
#   docker cp $(which doppler) agent-smith:/usr/local/bin/doppler

# Create app directory for installing dependencies
RUN mkdir -p /app
WORKDIR /app

# Copy dependency files
COPY pyproject.toml ./

# Install project dependencies (not dev dependencies)
# Note: Using pip instead of uv because uv lacks --trusted-host equivalent for
# handling corporate proxies/firewalls with self-signed certificates
RUN pip install --no-cache-dir --trusted-host pypi.org --trusted-host pypi.python.org --trusted-host files.pythonhosted.org -e .

# Install pytest for testing (minimal, doesn't need full dev group)
RUN pip install --no-cache-dir --trusted-host pypi.org --trusted-host pypi.python.org --trusted-host files.pythonhosted.org pytest>=8.0.0

# Skills will be mounted at /skills
RUN mkdir -p /skills
# Tests will be mounted at /tests
RUN mkdir -p /tests

WORKDIR /skills

# Default command: interactive bash
CMD ["/bin/bash"]
