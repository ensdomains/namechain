#!/usr/bin/env bun

import { Command } from "commander";
import { writeFileSync, appendFileSync } from "node:fs";
import {
  Logger,
  green,
  cyan,
  bold,
  dim,
} from "./logger.js";

// Types
interface ENSRegistration {
  id: string;
  labelName: string;
  registrant: {
    id: string;
  };
  expiryDate: string;
  registrationDate: string;
  domain: {
    name: string;
    labelhash: string;
    parent: {
      id: string;
    };
  };
}

interface GraphQLResponse {
  data: {
    registrations: ENSRegistration[];
  };
  errors?: Array<{ message: string }>;
}

interface ExportConfig {
  thegraphApiKey: string;
  batchSize: number;
  startIndex: number;
  limit: number | null;
  outputFile: string;
}

// Constants
const SUBGRAPH_ID = "5XqPmWe6gjyrJtFn9cLy237i4cWw2j9HcUJEXsP5qGtH";
const GATEWAY_ENDPOINT = `https://gateway.thegraph.com/api/{API_KEY}/subgraphs/id/${SUBGRAPH_ID}`;
const RATE_LIMIT_DELAY_MS = 200;

const logger = new Logger();

async function fetchRegistrations(
  config: ExportConfig,
  skip: number,
  first: number,
  fetchFn: typeof fetch = fetch
): Promise<ENSRegistration[]> {
  const endpoint = GATEWAY_ENDPOINT.replace("{API_KEY}", config.thegraphApiKey);

  const query = `
    query GetEthRegistrations($first: Int!, $skip: Int!) {
      registrations(
        first: $first
        skip: $skip
        orderBy: registrationDate
        orderDirection: desc
      ) {
        id
        labelName
        registrant {
          id
        }
        expiryDate
        registrationDate
        domain {
          name
          labelhash
          parent {
            id
          }
        }
      }
    }
  `;

  const response = await fetchFn(endpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      query,
      variables: { first, skip },
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`HTTP error! status: ${response.status}, body: ${errorText}`);
  }

  const result: GraphQLResponse = await response.json();

  if (result.errors) {
    throw new Error(
      `GraphQL error: ${result.errors.map((e) => e.message).join(", ")}`
    );
  }

  if (!result.data || !result.data.registrations) {
    throw new Error(`Invalid response structure from TheGraph: missing data.registrations`);
  }

  return result.data.registrations;
}

function escapeCSV(value: string): string {
  if (value.includes(',') || value.includes('"') || value.includes('\n')) {
    return `"${value.replace(/"/g, '""')}"`;
  }
  return value;
}

function registrationToCSVRow(reg: ENSRegistration): string {
  return [
    escapeCSV(reg.domain.name),
    escapeCSV(reg.labelName),
    escapeCSV(reg.domain.labelhash),
    escapeCSV(reg.registrant.id),
    escapeCSV(reg.expiryDate),
    escapeCSV(reg.registrationDate),
  ].join(',');
}

async function exportRegistrations(config: ExportConfig): Promise<void> {
  let skip = config.startIndex;
  let hasMore = true;
  let totalCount = 0;

  const csvHeader = 'name,label,labelhash,registrant,expiryDate,registrationDate\n';
  writeFileSync(config.outputFile, csvHeader, 'utf-8');

  logger.info(`CSV file created: ${cyan(config.outputFile)}`);
  logger.info(`Fetching registrations from TheGraph Gateway...\n`);

  while (hasMore) {
    try {
      let registrations = await fetchRegistrations(
        config,
        skip,
        config.batchSize
      );

      if (registrations.length === 0) {
        hasMore = false;
        break;
      }

      if (config.limit && totalCount + registrations.length > config.limit) {
        registrations = registrations.slice(0, config.limit - totalCount);
        hasMore = false;
      }

      const csvRows = registrations.map(registrationToCSVRow).join('\n') + '\n';
      appendFileSync(config.outputFile, csvRows, 'utf-8');

      totalCount += registrations.length;
      skip += registrations.length;

      logger.info(
        cyan(`Fetched and wrote ${registrations.length} registrations`) +
        dim(` (total: ${totalCount})`)
      );

      if (config.limit && totalCount >= config.limit) {
        hasMore = false;
        break;
      }

      await new Promise((resolve) => setTimeout(resolve, RATE_LIMIT_DELAY_MS));
    } catch (error) {
      logger.error(`Failed to fetch registrations at skip=${skip}: ${error}`);
      throw error;
    }
  }

  logger.info(`\nTotal registrations exported: ${bold(totalCount.toString())}`);
  logger.success(`Successfully exported to ${config.outputFile}`);
}

export async function main(argv = process.argv): Promise<void> {
  const program = new Command()
    .name("export-registrations")
    .description("Export ENS .eth 2LD registrations from TheGraph to CSV")
    .requiredOption("--thegraph-api-key <key>", "TheGraph Gateway API key (get from https://thegraph.com/studio/apikeys/)")
    .option("--batch-size <number>", "Number of names to fetch per TheGraph API request", "1000")
    .option("--start-index <number>", "Starting index for pagination", "0")
    .option("--limit <number>", "Maximum total number of names to fetch")
    .option("--output <file>", "Output CSV file path", `ens-registrations-${new Date().toISOString().split('T')[0]}.csv`);

  program.parse(argv);
  const opts = program.opts();

  const config: ExportConfig = {
    thegraphApiKey: opts.thegraphApiKey,
    batchSize: parseInt(opts.batchSize) || 1000,
    startIndex: parseInt(opts.startIndex) || 0,
    limit: opts.limit ? parseInt(opts.limit) : null,
    outputFile: opts.output,
  };

  try {
    logger.header("ENS Registration Export");
    logger.divider();

    logger.info(`Configuration:`);
    logger.config('TheGraph API Key', `${config.thegraphApiKey.substring(0, 8)}...`);
    logger.config('Batch Size', config.batchSize);
    logger.config('Start Index', config.startIndex);
    logger.config('Limit', config.limit ?? "none");
    logger.config('Output File', config.outputFile);
    logger.info("");

    await exportRegistrations(config);

    logger.success("\nExport completed successfully!");
  } catch (error) {
    logger.error(`Fatal error: ${error}`);
    console.error(error);
    process.exit(1);
  }
}

if (import.meta.main) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}
