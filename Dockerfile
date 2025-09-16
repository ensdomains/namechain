FROM oven/bun:1.2.22

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

# install node_modules in a docker layer
WORKDIR /app
COPY package.json bun.lock .
COPY contracts/package.json ./contracts/
RUN bun i

COPY . .
WORKDIR /app/contracts
RUN forge i
RUN bun run compile

# Run devnet
ENV FOUNDRY_DISABLE_NIGHTLY_WARNING=true
CMD ["bun", "run", "devnet"]
