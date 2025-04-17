FROM oven/bun:1.0.35

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g tsx

# Install Foundry
RUN curl -L https://foundry.paradigm.xyz | bash
ENV PATH="/root/.foundry/bin:${PATH}"
RUN foundryup

# Set working directory
WORKDIR /app

# Copy all source files
COPY . .

# Install dependencies
RUN bun i && \
    cd contracts && \
    git init && \
    forge i && \
    forge build && \
    cd ..

# Expose ports for L1 and L2
EXPOSE 8545
EXPOSE 8546

# Run devnet
WORKDIR /app/contracts
ENV FOUNDRY_DISABLE_NIGHTLY_WARNING=true
CMD ["bun", "run", "devnet"]
