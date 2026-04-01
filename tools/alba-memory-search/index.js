#!/usr/bin/env node
"use strict";

const path = require("path");
const os = require("os");
const Database = require("better-sqlite3");
const { Server } = require("@modelcontextprotocol/sdk/server/index.js");
const {
  StdioServerTransport,
} = require("@modelcontextprotocol/sdk/server/stdio.js");
const {
  ListToolsRequestSchema,
  CallToolRequestSchema,
} = require("@modelcontextprotocol/sdk/types.js");

// -- Config -------------------------------------------------------------------

const DB_PATH =
  process.env.ALBA_MEMORY_DB ||
  path.join(os.homedir(), ".alba", "alba-memory.db");

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 100;

// -- Help mode ----------------------------------------------------------------

if (process.argv.includes("--help") || process.argv.includes("-h")) {
  console.error(`alba-memory-search — MCP server for querying alba-memory.db

Usage:
  node index.js          Start MCP server on stdio
  node index.js --help   Show this help

Environment:
  ALBA_MEMORY_DB   Path to SQLite database (default: ~/.alba/alba-memory.db)

Tools exposed:
  search              FTS5 full-text search on observations (returns compact index)
  get_observations    Fetch full observation details by ID list
  timeline            Chronological context window around an anchor observation
`);
  process.exit(0);
}

// -- Database -----------------------------------------------------------------

let db;

function openDb() {
  if (db) return db;
  try {
    db = new Database(DB_PATH, { readonly: true, fileMustExist: true });
    db.pragma("journal_mode = WAL");
    return db;
  } catch (err) {
    throw new Error(
      `Cannot open alba-memory.db at ${DB_PATH}: ${err.message}`
    );
  }
}

// -- Tool: search -------------------------------------------------------------

const TOOL_SEARCH = {
  name: "search",
  description:
    "Full-text search across observations. Returns a compact index: ID, timestamp, type, title, and estimated token count. Use get_observations to retrieve full details for specific IDs.",
  inputSchema: {
    type: "object",
    properties: {
      query: {
        type: "string",
        description:
          "FTS5 search query (supports AND, OR, NOT, phrase matching with double quotes)",
      },
      limit: {
        type: "number",
        description: `Max results to return (default: ${DEFAULT_LIMIT}, max: ${MAX_LIMIT})`,
      },
      type: {
        type: "string",
        enum: [
          "decision",
          "bugfix",
          "feature",
          "refactor",
          "discovery",
          "change",
        ],
        description: "Filter by observation type",
      },
      date_from: {
        type: "string",
        description: "ISO-8601 date lower bound (inclusive)",
      },
      date_to: {
        type: "string",
        description: "ISO-8601 date upper bound (inclusive)",
      },
    },
    required: ["query"],
  },
};

function handleSearch(args) {
  const database = openDb();
  const limit = Math.min(Math.max(1, args.limit || DEFAULT_LIMIT), MAX_LIMIT);

  // Build WHERE clauses
  const conditions = ["observations_fts MATCH ?"];
  const params = [args.query];

  if (args.type) {
    conditions.push("o.type = ?");
    params.push(args.type);
  }
  if (args.date_from) {
    conditions.push("o.created_at >= ?");
    params.push(args.date_from);
  }
  if (args.date_to) {
    conditions.push("o.created_at <= ?");
    params.push(args.date_to);
  }

  params.push(limit);

  const sql = `
    SELECT
      o.id,
      o.created_at,
      o.type,
      o.title,
      o.session_id,
      length(coalesce(o.title,'')) + length(coalesce(o.subtitle,'')) +
        length(coalesce(o.narrative,'')) + length(coalesce(o.facts,'')) +
        length(coalesce(o.concepts,'')) AS approx_chars,
      rank
    FROM observations_fts
    JOIN observations o ON o.id = observations_fts.rowid
    WHERE ${conditions.join(" AND ")}
    ORDER BY rank
    LIMIT ?
  `;

  const rows = database.prepare(sql).all(...params);

  const results = rows.map((r) => ({
    id: r.id,
    time: r.created_at,
    type: r.type,
    title: r.title,
    session_id: r.session_id,
    approx_tokens: Math.ceil(r.approx_chars / 4),
  }));

  return {
    content: [
      {
        type: "text",
        text: JSON.stringify(
          { count: results.length, results },
          null,
          2
        ),
      },
    ],
  };
}

// -- Tool: get_observations ---------------------------------------------------

const TOOL_GET_OBSERVATIONS = {
  name: "get_observations",
  description:
    "Retrieve full observation details by ID. Use after search to get complete content for specific observations.",
  inputSchema: {
    type: "object",
    properties: {
      ids: {
        type: "array",
        items: { type: "number" },
        description: "Array of observation IDs to retrieve",
      },
    },
    required: ["ids"],
  },
};

function handleGetObservations(args) {
  const database = openDb();
  const ids = args.ids;

  if (!Array.isArray(ids) || ids.length === 0) {
    return {
      content: [{ type: "text", text: JSON.stringify({ error: "ids must be a non-empty array of numbers" }) }],
      isError: true,
    };
  }

  if (ids.length > MAX_LIMIT) {
    return {
      content: [{ type: "text", text: JSON.stringify({ error: `Maximum ${MAX_LIMIT} IDs per request` }) }],
      isError: true,
    };
  }

  const placeholders = ids.map(() => "?").join(",");
  const sql = `
    SELECT
      id, session_id, type, title, subtitle, narrative,
      facts, concepts, files_read, files_modified,
      tokens_cost, created_at
    FROM observations
    WHERE id IN (${placeholders})
    ORDER BY created_at ASC
  `;

  const rows = database.prepare(sql).all(...ids);

  // Parse JSON fields
  const observations = rows.map((r) => ({
    ...r,
    facts: safeParseJSON(r.facts),
    concepts: safeParseJSON(r.concepts),
    files_read: safeParseJSON(r.files_read),
    files_modified: safeParseJSON(r.files_modified),
  }));

  return {
    content: [
      {
        type: "text",
        text: JSON.stringify({ count: observations.length, observations }, null, 2),
      },
    ],
  };
}

// -- Tool: timeline -----------------------------------------------------------

const TOOL_TIMELINE = {
  name: "timeline",
  description:
    "Get a chronological context window around an anchor observation. Shows observations before and after the anchor, useful for understanding what happened in sequence.",
  inputSchema: {
    type: "object",
    properties: {
      anchor_id: {
        type: "number",
        description: "Observation ID to center the timeline on",
      },
      depth_before: {
        type: "number",
        description: "Number of observations to include before the anchor (default: 5)",
      },
      depth_after: {
        type: "number",
        description: "Number of observations to include after the anchor (default: 5)",
      },
    },
    required: ["anchor_id"],
  },
};

function handleTimeline(args) {
  const database = openDb();
  const anchorId = args.anchor_id;
  const before = Math.min(Math.max(0, args.depth_before ?? 5), 50);
  const after = Math.min(Math.max(0, args.depth_after ?? 5), 50);

  // Get the anchor's session and timestamp
  const anchor = database
    .prepare("SELECT id, session_id, created_at FROM observations WHERE id = ?")
    .get(anchorId);

  if (!anchor) {
    return {
      content: [{ type: "text", text: JSON.stringify({ error: `Observation ${anchorId} not found` }) }],
      isError: true,
    };
  }

  // Get observations before (same session, ordered desc, limit before)
  const beforeRows = database
    .prepare(
      `SELECT id, type, title, created_at
       FROM observations
       WHERE session_id = ? AND created_at < ?
       ORDER BY created_at DESC
       LIMIT ?`
    )
    .all(anchor.session_id, anchor.created_at, before)
    .reverse();

  // Get anchor row
  const anchorRow = database
    .prepare(
      `SELECT id, type, title, subtitle, narrative, created_at
       FROM observations WHERE id = ?`
    )
    .get(anchorId);

  // Get observations after (same session, ordered asc, limit after)
  const afterRows = database
    .prepare(
      `SELECT id, type, title, created_at
       FROM observations
       WHERE session_id = ? AND created_at > ?
       ORDER BY created_at ASC
       LIMIT ?`
    )
    .all(anchor.session_id, anchor.created_at, after);

  const timeline = {
    session_id: anchor.session_id,
    before: beforeRows.map((r) => ({
      id: r.id,
      type: r.type,
      title: r.title,
      time: r.created_at,
    })),
    anchor: {
      id: anchorRow.id,
      type: anchorRow.type,
      title: anchorRow.title,
      subtitle: anchorRow.subtitle,
      narrative: anchorRow.narrative,
      time: anchorRow.created_at,
    },
    after: afterRows.map((r) => ({
      id: r.id,
      type: r.type,
      title: r.title,
      time: r.created_at,
    })),
  };

  return {
    content: [
      { type: "text", text: JSON.stringify(timeline, null, 2) },
    ],
  };
}

// -- Helpers ------------------------------------------------------------------

function safeParseJSON(val) {
  if (!val) return null;
  try {
    return JSON.parse(val);
  } catch {
    return val;
  }
}

// -- MCP Server ---------------------------------------------------------------

const TOOLS = [TOOL_SEARCH, TOOL_GET_OBSERVATIONS, TOOL_TIMELINE];

const server = new Server(
  { name: "alba-memory-search", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: TOOLS,
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    switch (name) {
      case "search":
        return handleSearch(args || {});
      case "get_observations":
        return handleGetObservations(args || {});
      case "timeline":
        return handleTimeline(args || {});
      default:
        return {
          content: [{ type: "text", text: `Unknown tool: ${name}` }],
          isError: true,
        };
    }
  } catch (err) {
    return {
      content: [
        {
          type: "text",
          text: JSON.stringify({
            error: err.message,
            tool: name,
          }),
        },
      ],
      isError: true,
    };
  }
});

// -- Start --------------------------------------------------------------------

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("alba-memory-search MCP server running on stdio");
}

main().catch((err) => {
  console.error("Fatal:", err.message);
  process.exit(1);
});
