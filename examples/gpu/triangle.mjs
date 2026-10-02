// Checks a screenshot for the triangle Triangle.hx draws.
//
//     node triangle.mjs <frame.png> [x y width height]
//
// The optional rectangle, in image pixels, is the drawn area; without it the
// whole image is. Exits 0 when the triangle is there.
//
// The triangle's corners are (-0.8,-0.65), (0.8,-0.65) and (0,0.8) in clip
// space, so its bounding box spans 0.8 of the area's width and 0.725 of its
// height, it fills half of that box, and it narrows towards the top. Orange is
// matched loosely: an sRGB surface and a linear one put different values on
// screen for the same shader output.
import { readFileSync } from "node:fs";
import { inflateSync } from "node:zlib";
import { fileURLToPath } from "node:url";

/** Decodes an 8-bit, non-interlaced RGB or RGBA PNG. */
export function decodePng(png) {
  if (png.readUInt32BE(0) !== 0x89504e47) throw new Error("not a PNG");
  let offset = 8, width, height, channels;
  const data = [];
  while (offset < png.length) {
    const length = png.readUInt32BE(offset);
    const type = png.toString("latin1", offset + 4, offset + 8);
    const body = png.subarray(offset + 8, offset + 8 + length);
    if (type === "IHDR") {
      width = body.readUInt32BE(0);
      height = body.readUInt32BE(4);
      const depth = body[8], colour = body[9], interlace = body[12];
      if (depth !== 8 || (colour !== 2 && colour !== 6) || interlace !== 0) {
        throw new Error(`unsupported PNG: depth ${depth}, colour type ${colour}, interlace ${interlace}`);
      }
      channels = colour === 6 ? 4 : 3;
    } else if (type === "IDAT") {
      data.push(body);
    } else if (type === "IEND") {
      break;
    }
    offset += 12 + length;
  }
  const raw = inflateSync(Buffer.concat(data));
  const stride = width * channels;
  const pixels = Buffer.alloc(height * stride);
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    const line = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    const out = y * stride;
    for (let i = 0; i < stride; i++) {
      const a = i >= channels ? pixels[out + i - channels] : 0;
      const b = y > 0 ? pixels[out - stride + i] : 0;
      const c = i >= channels && y > 0 ? pixels[out - stride + i - channels] : 0;
      let v = line[i];
      switch (filter) {
        case 0: break;
        case 1: v += a; break;
        case 2: v += b; break;
        case 3: v += (a + b) >> 1; break;
        case 4: {
          const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
          v += pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
          break;
        }
        default: throw new Error(`bad PNG filter ${filter}`);
      }
      pixels[out + i] = v & 0xff;
    }
  }
  return { width, height, channels, pixels };
}

const orange = (r, g, b) => r > 180 && r - b > 100 && g > b + 30 && g < r - 30;

/** Returns { ok, report } for the triangle in `rect` of the decoded image. */
export function checkTriangle(image, rect) {
  const { width, height, channels, pixels } = image;
  const x0 = Math.max(0, Math.round(rect?.x ?? 0));
  const y0 = Math.max(0, Math.round(rect?.y ?? 0));
  const w = Math.min(width - x0, Math.round(rect?.width ?? width));
  const h = Math.min(height - y0, Math.round(rect?.height ?? height));
  let count = 0, left = w, right = -1, top = h, bottom = -1;
  const rows = new Array(h).fill(0);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const p = ((y0 + y) * width + x0 + x) * channels;
      if (!orange(pixels[p], pixels[p + 1], pixels[p + 2])) continue;
      count++;
      rows[y]++;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
  }
  const failures = [];
  if (count < 1000) {
    return { ok: false, report: `area ${w}x${h}: ${count} orange pixels, no triangle` };
  }
  const boxW = right - left + 1, boxH = bottom - top + 1;
  const spanX = boxW / w, spanY = boxH / h, fill = count / (boxW * boxH);
  const near = rows[top + Math.floor(boxH * 0.1)], far = rows[top + Math.floor(boxH * 0.9)];
  if (Math.abs(spanX - 0.8) > 0.06) failures.push(`width span ${spanX.toFixed(3)}, expected 0.8`);
  if (Math.abs(spanY - 0.725) > 0.06) failures.push(`height span ${spanY.toFixed(3)}, expected 0.725`);
  if (Math.abs(fill - 0.5) > 0.08) failures.push(`fills ${fill.toFixed(3)} of its box, expected 0.5`);
  if (!(near * 3 < far)) failures.push(`rows near the top ${near} px and near the base ${far} px wide, expected it to narrow upwards`);
  const report = `area ${w}x${h}: triangle box ${boxW}x${boxH} at ${left},${top}` +
    ` (span ${spanX.toFixed(3)} x ${spanY.toFixed(3)}, fill ${fill.toFixed(3)})` +
    (failures.length ? `; ${failures.join("; ")}` : "");
  return { ok: failures.length === 0, report };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [file, ...box] = process.argv.slice(2);
  if (!file) {
    console.error("usage: node triangle.mjs <frame.png> [x y width height]");
    process.exit(2);
  }
  const rect = box.length === 4 ? { x: +box[0], y: +box[1], width: +box[2], height: +box[3] } : undefined;
  const { ok, report } = checkTriangle(decodePng(readFileSync(file)), rect);
  console.log(`${ok ? "triangle found" : "no triangle"}: ${file}, ${report}`);
  process.exit(ok ? 0 : 1);
}
