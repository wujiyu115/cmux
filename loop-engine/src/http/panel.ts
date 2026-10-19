import type { FastifyInstance } from "fastify";

/**
 * Zero-dependency observation panel served at GET /panel: an auto-refreshing
 * work board over the /work API. Kept as a single static string (no template
 * engine, no client deps); the HTML/JS below intentionally avoids any
 * dynamic string interpolation, so there is no injection surface.
 */
export const PANEL_HTML = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>loop-engine panel</title>
<style>
  :root { color-scheme: dark; }
  body { font: 14px/1.5 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
         background: #101418; color: #d7dde3; margin: 0; padding: 24px; }
  h1 { font-size: 16px; margin: 0 0 16px; font-weight: 600; }
  h1 .sub { color: #6b7681; font-weight: 400; margin-left: 12px; }
  .empty { color: #6b7681; padding: 32px 0; }
  table { border-collapse: collapse; width: 100%; }
  th, td { text-align: left; padding: 6px 10px; border-bottom: 1px solid #212830;
           vertical-align: top; white-space: nowrap; }
  th { color: #6b7681; font-weight: 500; font-size: 12px; text-transform: uppercase; }
  td.wrap { white-space: normal; min-width: 240px; }
  .status { display: inline-block; padding: 1px 8px; border-radius: 10px; font-size: 12px; }
  .claimed, .planning, .executing, .verifying, .retrying { background: #2b4a77; }
  .awaiting_review { background: #6b5b1e; }
  .done { background: #22523a; }
  .failed { background: #6b2b2b; }
  .error { color: #e08383; max-width: 320px; overflow: hidden; text-overflow: ellipsis; }
  a { color: #7ab0e8; text-decoration: none; }
  .usage { color: #6b7681; font-size: 12px; }
  .refresh { color: #6b7681; font-size: 12px; margin-top: 16px; }
</style>
</head>
<body>
<h1>loop-engine <span class="sub" id="health"></span></h1>
<div id="content"><div class="empty">loading…</div></div>
<div class="refresh" id="refresh"></div>
<script>
(function () {
  var lastUpdated = "";
  function fmtCount(n) { return n == null ? "-" : String(n); }
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function row(w) {
    var ticket = w.ticket || {};
    var usage = w.usage || {};
    return "<tr>"
      + "<td><span class='status " + esc(w.status) + "'>" + esc(w.status) + "</span></td>"
      + "<td class='wrap'><a href='" + esc(ticket.url) + "' target='_blank'>" + esc(ticket.title) + "</a>"
      + "<div class='usage'>" + esc(ticket.project) + "</div></td>"
      + "<td>" + fmtCount(w.attempt) + "</td>"
      + "<td>" + fmtCount(usage.inputTokens) + " in / " + fmtCount(usage.outputTokens) + " out</td>"
      + "<td>" + (w.prUrl ? "<a href='" + esc(w.prUrl) + "' target='_blank'>PR</a>" : "-") + "</td>"
      + "<td class='error' title='" + esc(w.lastError) + "'>" + esc(w.lastError || "-") + "</td>"
      + "<td>" + esc(w.updatedAt) + "</td>"
      + "</tr>";
  }
  function render() {
    fetch("/healthz").then(function (r) {
      document.getElementById("health").textContent = r.ok ? "up" : "down";
    }).catch(function () { document.getElementById("health").textContent = "down"; });
    fetch("/work").then(function (r) { return r.json(); }).then(function (works) {
      if (!Array.isArray(works) || works.length === 0) {
        document.getElementById("content").innerHTML = "<div class='empty'>no work records yet</div>";
        return;
      }
      var counts = {};
      works.forEach(function (w) { counts[w.status] = (counts[w.status] || 0) + 1; });
      var summary = Object.keys(counts).sort().map(function (k) { return k + ":" + counts[k]; }).join("  ");
      document.getElementById("content").innerHTML =
        "<table><thead><tr><th>status</th><th>ticket</th><th>attempt</th><th>tokens</th><th>pr</th><th>last error</th><th>updated</th></tr></thead>"
        + "<tbody>" + works.map(row).join("") + "</tbody></table>"
        + "<div class='refresh'>" + esc(summary) + "</div>";
    }).catch(function () {
      document.getElementById("content").innerHTML = "<div class='empty'>failed to load /work</div>";
    });
  }
  render();
  setInterval(render, 5000);
})();
</script>
</body>
</html>`;

export function registerPanelRoutes(app: FastifyInstance): void {
  app.get("/panel", async (_request, reply) => {
    reply.header("content-type", "text/html; charset=utf-8");
    return PANEL_HTML;
  });
}
