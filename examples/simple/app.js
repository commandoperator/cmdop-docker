// A deliberately boring application. It exists so the example has something to
// keep running as PID 1 — the point of this directory is the two lines in the
// Dockerfile, not this file.
//
// It also prints its own signal handling, which is the property `sidecar`
// preserves: `docker stop` reaches YOUR app, not the agent.

const http = require("http");

const port = process.env.PORT || 3000;

http
  .createServer((_req, res) => {
    res.writeHead(200, { "Content-Type": "text/plain" });
    res.end("hello from the app that keeps PID 1\n");
  })
  .listen(port, () => console.log(`listening on :${port} as pid ${process.pid}`));

for (const signal of ["SIGTERM", "SIGINT"]) {
  process.on(signal, () => {
    console.log(`${signal} received by the app — shutting down normally`);
    process.exit(0);
  });
}
