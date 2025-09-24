FROM oven/bun:1.2.13

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Install Foundry
RUN curl -L https://foundry.paradigm.xyz | bash
ENV PATH="/root/.foundry/bin:${PATH}"
RUN foundryup

# Set working directory
WORKDIR /app

# Copy the root package.json and bun.lock
COPY package.json bun.lock ./

# Copy the package.json for each workspace.
COPY contracts/package.json ./contracts/

COPY solhint-plugins/ordering/package.json ./solhint-plugins/ordering/

# Copy patches for post script execution
#COPY /patches ./patches

# Install all dependencies
RUN bun i

# Copy the rest of the application source
COPY . .

# Build Contracts
WORKDIR /app/contracts

# Initialize git in contracts dir and install forge dependencies
RUN git config --global init.defaultBranch main && \
    cd /app && \
    git init && \
    git submodule update --init --recursive && \
    cd contracts && \
    forge i

# Build Contracts
RUN bun run compile:hardhat

# Expose ports for L1 and L2
EXPOSE 8545
EXPOSE 8546
EXPOSE 8547

# Run devnet
WORKDIR /app/contracts
ENV FOUNDRY_DISABLE_NIGHTLY_WARNING=true
CMD ["bun", "run", "devnet"]
