// Runs Triangle in Ash's page in a Chrome started with --remote-debugging-port,
// screenshots the canvas once frames are drawing, and checks the picture.
//
//     node page.mjs <page url> <debugging port> <frame.png> [minimum frames]
//
// Prints what the program wrote to the page and exits 0 when the program
// presented at least the minimum number of frames (default 1), exited 0, and
// the screenshot shows the triangle.
import { writeFileSync } from "node:fs";
import { checkTriangle, decodePng } from "./triangle.mjs";

const [url, port, shot, least = "1"] = process.argv.slice(2);
if (!shot) {
  console.error("usage: node page.mjs <page url> <debugging port> <frame.png> [minimum frames]");
  process.exit(2);
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let target;
for (let i = 0; i < 100 && !target; i++) {
  try {
    const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
    target = list.find((t) => t.type === "page");
  } catch {}
  if (!target) await sleep(200);
}
if (!target) {
  console.error(`no page target on debugging port ${port}`);
  process.exit(1);
}

const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
let id = 0;
const pending = new Map();
ws.onmessage = ({ data }) => {
  const msg = JSON.parse(data);
  if (msg.id && pending.has(msg.id)) {
    const { resolve, reject } = pending.get(msg.id);
    pending.delete(msg.id);
    if (msg.error) reject(new Error(JSON.stringify(msg.error)));
    else resolve(msg.result);
  } else if (msg.method === "Runtime.consoleAPICalled" && /error|warn/.test(msg.params.type)) {
    console.log(`[page console.${msg.params.type}]`, msg.params.args.map((a) => a.value ?? a.description).join(" "));
  } else if (msg.method === "Runtime.exceptionThrown") {
    const details = msg.params.exceptionDetails;
    console.log("[page exception]", details.exception?.description ?? details.text);
  }
};
const send = (method, params = {}) => new Promise((resolve, reject) => {
  const n = ++id;
  pending.set(n, { resolve, reject });
  ws.send(JSON.stringify({ id: n, method, params }));
});
const evaluate = async (expression) =>
  (await send("Runtime.evaluate", { expression, returnByValue: true })).result.value;
const out = async () => (await evaluate("document.getElementById('out')?.textContent")) ?? "";
// The page titles itself "<module> — done" or "— trapped" when the program ends.
const ended = async () => /— (done|trapped)$/.test(await evaluate("document.title"));
const until = async (test, ms) => {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    if (await test()) return true;
    await sleep(100);
  }
  return false;
};

await send("Runtime.enable");
await send("Page.enable");
await send("Page.navigate", { url });

let pictured = null;
if (await until(async () => /GPU: /.test(await out()) || await ended(), 60000) && /GPU: /.test(await out())) {
  await sleep(1500);
  const { data } = await send("Page.captureScreenshot", { format: "png" });
  const png = Buffer.from(data, "base64");
  writeFileSync(shot, png);
  const box = await evaluate(`(() => {
    const r = document.getElementById('screen').getBoundingClientRect();
    return { x: r.x, y: r.y, width: r.width, height: r.height, scale: devicePixelRatio };
  })()`);
  const rect = { x: box.x * box.scale, y: box.y * box.scale, width: box.width * box.scale, height: box.height * box.scale };
  pictured = checkTriangle(decodePng(png), rect);
}
const finished = await until(ended, 60000);
const title = await evaluate("document.title");
const text = await out();
ws.close();

console.log("---- program output ----");
console.log(text.trimEnd());
console.log("------------------------");
console.log(`page title: ${title}`);
const frames = Number(/presented (\d+) frame/.exec(text)?.[1] ?? 0);
const failures = [];
if (!finished) failures.push("the program did not end");
if (/trapped$/.test(title)) failures.push("the program trapped");
const status = /exited with (-?\d+)/.exec(text)?.[1];
if (finished && status !== "0") failures.push(`the program exited with ${status ?? "no status"}`);
if (/FAIL/.test(text)) failures.push("the program reported a failure");
if (frames < Number(least)) failures.push(`${frames} frame(s) presented, expected at least ${least}`);
if (!pictured) failures.push("no screenshot was taken");
else console.log(`${pictured.ok ? "triangle found" : "no triangle"}: ${shot}, ${pictured.report}`);
if (pictured && !pictured.ok) failures.push("the screenshot does not show the triangle");
if (failures.length) {
  console.log(`page: FAIL: ${failures.join("; ")}`);
  process.exit(1);
}
console.log(`page: PASS, ${frames} frame(s)`);
