"use strict";

/**
 * The reasons picked on a report. The app lets someone pick several and
 * writes them as a list (`reasons`) plus the same list as one line of text
 * (`reason`). A report that only has the text counts as that one reason.
 * @param {Record<string, any> | null | undefined} report
 * @return {string[]}
 */
function reasonsOf(report) {
  const r = report || {};
  if (Array.isArray(r.reasons)) {
    const list = r.reasons.filter((x) => typeof x === "string" && x);
    if (list.length > 0) return list;
  }
  return typeof r.reason === "string" && r.reason ? [r.reason] : [];
}

module.exports = {reasonsOf};
