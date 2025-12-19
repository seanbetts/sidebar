FROM python:3.11-slim

# Install essential Unix tools for skill development
RUN apt-get update && apt-get install -y \
    git \
    curl \
    vim \
    && rm -rf /var/lib/apt/lists/*

# Create skills directory
RUN mkdir -p /skills

# Set working directory
WORKDIR /skills

# Default command: interactive bash
CMD ["/bin/bash"]
