// Run anywhere with Node 18+:  ANTHROPIC_API_KEY=sk-ant-... node server.js
const http = require("http"), fs = require("fs"), path = require("path"), handler = require("./api/chat.js");
http.createServer((req, res) => {
  if (req.url.split("?")[0] === "/api/chat") {
    let b = ""; req.on("data", c => (b += c)); req.on("end", () => {
      try { req.body = b ? JSON.parse(b) : {}; } catch { req.body = {}; }
      res.status = c => { res.statusCode = c; return res; };
      res.json = o => { res.setHeader("content-type", "application/json"); res.end(JSON.stringify(o)); };
      handler(req, res);
    });
  } else {
    res.setHeader("content-type", "text/html; charset=utf-8");
    fs.createReadStream(path.join(__dirname, "index.html")).pipe(res);
  }
}).listen(process.env.PORT || 3000, () => console.log("Musta-SHARE on http://localhost:" + (process.env.PORT || 3000)));
