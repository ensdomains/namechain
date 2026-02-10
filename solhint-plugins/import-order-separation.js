// Solhint plugin: import-order-separation
// Recreates the idea of `importOrderSeparation` from prettier-plugin-sort-imports
// for Solidity imports using Solhint's class-based rules API.

/**
 * @typedef {Object} ImportDirectiveNode
 * @property {string} type
 * @property {Object} loc
 * @property {Object} path
 * @property {Array} range
 * @property {Array} symbolAliases
 */

// Grouping helper: first matching regex wins
/**
 * @description Selects the group index for a given import path
 * @param {string} importPath
 * @param {string[] | undefined} patterns
 * @returns {number}
 */
function selectGroupIndex(importPath, patterns) {
  if (Array.isArray(patterns) && patterns.length > 0) {
    for (let i = 0; i < patterns.length; i++) {
      const raw = patterns[i];
      if (typeof raw !== "string") continue;
      try {
        const re = new RegExp(raw);
        if (re.test(importPath)) return i;
      } catch {
        // Ignore invalid regex; continue
      }
    }
    // Non-matching imports go last
    return patterns.length;
  }
  // Default grouping similar to JS: external vs relative
  return importPath.startsWith(".") ? 1 : 0;
}

/**
 * @description Gets the source path for a given import directive node
 * @param {ImportDirectiveNode} node
 * @returns {string | undefined}
 */
function sourcePath(node) {
  const anyNode = node;
  const p = anyNode.path;
  if (typeof p === "string") return p;
  if (p && typeof p.value === "string") return p.value;
  if (p && typeof p.name === "string") return p.name;
  return undefined;
}

// Rule implemented as a class per Solhint's plugin guide
class ImportOrderSeparationRule {
  ruleId = "import-order-separation";
  meta = { fixable: true };
  /**
   * @type {Object}
   * // Solhint's reporter accepts an optional fixer function; use any for broad compatibility
   * @property {(node: any, ruleId: string, message: string, fix?: (fixer: any) => any) => void} error
   */
  reporter;
  /**
   * @type {string[] | undefined}
   */
  importOrder;
  /**
   * @type {ImportDirectiveNode[]}
   */
  imports = [];
  /**
   * @type {Array<{ node: any; insertPos: number }>}
   */
  violations = [];
  /**
   * @type {Array<{ range: [number, number]; path: string; fullSentence: string }>}
   */
  fromContractImports = [];
  /**
   * @type {Array<{ range: [number, number]; path: string; fullSentence: string }>}
   */
  orderedImports = [];

  /**
   * @param {any} reporter
   * @param {any} config
   */
  constructor(reporter, config) {
    this.reporter = reporter;
    this.importOrder =
      config && config.getObject(`contracts-v2/${this.ruleId}`, {}).importOrder;
  }

  /**
   * Visitor: collect imports
   * @param {ImportDirectiveNode} node
   */
  ImportDirective(node) {
    if (node && node.type === "ImportDirective") {
      this.imports.push(node);
    }
  }

  // Visitor exit: analyze spacing between groups
  ["SourceUnit:exit"]() {
    if (this.imports.length < 2) {
      this.imports = [];
      return;
    }

    this.imports.sort(
      (a, b) => (a.loc?.start.line ?? 0) - (b.loc?.start.line ?? 0),
    );

    // Build import entries with ranges and normalized paths
    this.fromContractImports = this.imports
      .filter((n) => n && n.type === "ImportDirective")
      .map((n) => {
        const p = sourcePath(n) ?? "";
        const normalized = this.normalizePath(p);
        const fullSentence = n.symbolAliases
          ? `${this.getFullSentence(n.symbolAliases)}'${normalized}';`
          : `import '${normalized}';`;
        /**
         * @type {[number, number]}
         */
        const range = Array.isArray(n.range) ? n.range : [0, 0];
        return { range, path: normalized, fullSentence };
      });

    // Prepare ordered copy
    this.orderedImports = JSON.parse(JSON.stringify(this.fromContractImports));
    this.orderedImports = this.sortImports(this.orderedImports);

    // If order differs, rewrite the import block with correct order and separation
    if (!this.arePathsEqual(this.fromContractImports, this.orderedImports)) {
      // Determine separation between groups based on configured importOrder
      const groupFor = (/** @type {string} */ p) =>
        selectGroupIndex(p, this.importOrder);
      const groups = this.orderedImports.map((imp) => groupFor(imp.path));

      let currentStart = Math.min(
        ...this.fromContractImports.map((imp) => imp.range[0]),
      );
      const replacements = this.orderedImports.map((orderedImport, i) => {
        const newText = orderedImport.fullSentence.replace(/'/g, '"');
        const sep =
          i < this.orderedImports.length - 1
            ? groups[i] !== groups[i + 1]
              ? "\n\n"
              : "\n"
            : "";
        const rangeEnd = currentStart + newText.length + sep.length; // account for sep when slicing ranges
        const replacement = {
          range: [currentStart, rangeEnd],
          newText,
          sep,
        };
        currentStart = rangeEnd;
        return replacement;
      });

      const lastRangeEnd =
        this.fromContractImports[this.fromContractImports.length - 1].range[1];
      // Apply fixes from bottom to top
      for (let i = replacements.length - 1; i >= 0; i--) {
        const rep = replacements[i];
        if (!rep) continue;
        const node = this.imports[i];
        const isLast = i === replacements.length - 1;
        if (isLast) {
          this.reporter.error(
            node,
            this.ruleId,
            "Wrong import order",
            (fixer) =>
              fixer.replaceTextRange([rep.range[0], lastRangeEnd], rep.newText),
          );
        } else {
          this.reporter.error(
            node,
            this.ruleId,
            "Wrong import order",
            (fixer) => fixer.replaceTextRange(rep.range, rep.newText + rep.sep),
          );
        }
      }

      // Reset state and stop (spacing handled by our constructed separators)
      this.imports = [];
      this.violations = [];
      this.fromContractImports = [];
      this.orderedImports = [];
      return;
    }

    /**
     * @type {number | undefined}
     */
    let prevGroup;
    /**
     * @type {number | undefined}
     */
    let prevEndLine;

    // Track violations to report bottom-to-top for safe fixing
    this.violations = [];

    for (let i = 0; i < this.imports.length; i++) {
      const node = this.imports[i];
      const p = sourcePath(node);
      if (!p || !node.loc) continue;
      const group = selectGroupIndex(p, this.importOrder);

      if (
        prevGroup !== undefined &&
        group !== prevGroup &&
        prevEndLine !== undefined
      ) {
        const currentStart = node.loc.start.line;
        if (currentStart < prevEndLine + 2) {
          // Prefer inserting a newline before the current import start.
          const range = Array.isArray(node.range) ? node.range : undefined;
          if (range) {
            this.violations.push({ node, insertPos: range[0] });
          } else {
            // Fallback: report without fix if range is unavailable
            this.reporter.error(
              node,
              this.ruleId,
              "Expected a blank line between import groups",
            );
          }
        }
      }

      prevGroup = group;
      prevEndLine = node.loc.end.line;
    }

    // Report fixes from bottom to top to avoid range shifting issues
    for (let i = this.violations.length - 1; i >= 0; i--) {
      const v = this.violations[i];
      if (!v) continue;
      this.reporter.error(
        v.node,
        this.ruleId,
        "Expected a blank line between import groups",
        (fixer) => fixer.replaceTextRange([v.insertPos, v.insertPos], "\n"),
      );
    }

    // Reset for next file
    this.imports = [];
    this.violations = [];
    this.fromContractImports = [];
    this.orderedImports = [];
  }

  // ----- Helpers borrowed and adapted from Solhint's imports-order -----
  /**
   * @param {Array<{ range: [number, number]; path: string; fullSentence: string }>} unorderedImports
   * @returns {Array<{ range: [number, number]; path: string; fullSentence: string }>}
   */
  sortImports(unorderedImports) {
    /**
     * @param {string} path
     * @returns {number}
     */
    const regexOrder = this.importOrder.map((regex, i, arr) => [
      new RegExp(regex),
      (arr.length - i) * -10000,
    ]);
    function getHierarchyLevel(path) {
      for (const [regex, order] of regexOrder) {
        if (regex.test(path)) {
          return order;
        }
      }
      return Infinity;
    }
    const orderedImports = unorderedImports.sort((a, b) => {
      const levelA = getHierarchyLevel(a.path);
      const levelB = getHierarchyLevel(b.path);
      if (levelA !== levelB) return levelA - levelB;
      return a.path.localeCompare(b.path, undefined, { sensitivity: "base" });
    });
    return orderedImports;
  }

  /**
   * @param {Array<[string, string?]>} elements
   * @returns {string}
   */
  getFullSentence(elements) {
    const importParts = elements.map(([name, alias]) =>
      alias ? `${name} as ${alias}` : name,
    );
    return `import {${importParts.join(", ")}} from `;
  }

  /**
   * @param {string} path
   * @returns {string}
   */
  normalizePath(path) {
    return path;
  }

  /**
   * @param {Array<{ path: string }>} arr1
   * @param {Array<{ path: string }>} arr2
   * @returns {boolean}
   */
  arePathsEqual(arr1, arr2) {
    if (arr1.length !== arr2.length) return false;
    for (let i = 0; i < arr1.length; i++) {
      if (!arr1[i] || !arr2[i]) return false;
      if (arr1[i].path !== arr2[i].path) return false;
    }
    return true;
  }
}

module.exports = ImportOrderSeparationRule;
