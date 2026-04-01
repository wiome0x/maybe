import { Controller } from "@hotwired/stimulus";

// Renders a simple SVG line chart from historical price data
export default class extends Controller {
  static values = { prices: Array };
  static targets = ["canvas"];

  connect() {
    if (!this.hasCanvasTarget) return;
    if (!this.pricesValue || this.pricesValue.length === 0) return;

    this.#render();
  }

  #render() {
    // Downsample to max 500 points for rendering performance
    const prices = this.#downsample(this.pricesValue, 500);
    if (prices.length === 0) return;

    const isDark = document.documentElement.dataset.theme === "dark";

    const width = 700;
    const height = 240;
    const padding = { top: 20, right: 60, bottom: 40, left: 10 };
    const chartWidth = width - padding.left - padding.right;
    const chartHeight = height - padding.top - padding.bottom;

    const closes = prices.map((p) => p.close);
    const minClose = Math.min(...closes);
    const maxClose = Math.max(...closes);
    const range = maxClose - minClose || 1;

    const xScale = (i) => padding.left + (i / (prices.length - 1)) * chartWidth;
    const yScale = (val) => padding.top + chartHeight - ((val - minClose) / range) * chartHeight;

    // Build polyline points
    const points = prices
      .map((p, i) => `${xScale(i)},${yScale(p.close)}`)
      .join(" ");

    const lineColor = isDark ? "#60a5fa" : "#2563eb";
    const textColor = isDark ? "#a1a1aa" : "#71717a";
    const gridColor = isDark ? "rgba(255,255,255,0.08)" : "rgba(0,0,0,0.06)";

    // Build Y-axis labels (5 ticks)
    const yTicks = 5;
    let yLabels = "";
    let gridLines = "";
    for (let i = 0; i <= yTicks; i++) {
      const val = minClose + (range * i) / yTicks;
      const y = yScale(val);
      yLabels += `<text x="${width - padding.right + 8}" y="${y + 4}" fill="${textColor}" font-size="11" font-family="var(--font-mono)">${val.toFixed(2)}</text>`;
      gridLines += `<line x1="${padding.left}" y1="${y}" x2="${width - padding.right}" y2="${y}" stroke="${gridColor}" stroke-width="1"/>`;
    }

    // Build X-axis labels (up to 6 date labels)
    const maxXLabels = Math.min(6, prices.length);
    let xLabels = "";
    for (let i = 0; i < maxXLabels; i++) {
      const idx = Math.round((i / (maxXLabels - 1)) * (prices.length - 1));
      const x = xScale(idx);
      xLabels += `<text x="${x}" y="${height - 6}" fill="${textColor}" font-size="11" text-anchor="middle" font-family="var(--font-mono)">${prices[idx].date}</text>`;
    }

    const svg = `
      <svg viewBox="0 0 ${width} ${height}" class="w-full h-full" preserveAspectRatio="xMidYMid meet">
        ${gridLines}
        <polyline fill="none" stroke="${lineColor}" stroke-width="2" stroke-linejoin="round" stroke-linecap="round" points="${points}"/>
        ${yLabels}
        ${xLabels}
      </svg>
    `;

    this.canvasTarget.innerHTML = svg;
  }

  // Largest-Triangle-Three-Buckets downsampling to keep chart shape accurate
  #downsample(data, threshold) {
    if (data.length <= threshold) return data;

    const sampled = [data[0]];
    const bucketSize = (data.length - 2) / (threshold - 2);

    let prevIndex = 0;

    for (let i = 1; i < threshold - 1; i++) {
      const avgStart = Math.floor(i * bucketSize) + 1;
      const avgEnd = Math.min(Math.floor((i + 1) * bucketSize) + 1, data.length);

      let avgClose = 0;
      for (let j = avgStart; j < avgEnd; j++) {
        avgClose += data[j].close;
      }
      avgClose /= (avgEnd - avgStart);

      const rangeStart = Math.floor((i - 1) * bucketSize) + 1;
      const rangeEnd = Math.min(Math.floor(i * bucketSize) + 1, data.length);

      let maxArea = -1;
      let maxIndex = rangeStart;

      for (let j = rangeStart; j < rangeEnd; j++) {
        const area = Math.abs(
          (prevIndex - (avgEnd - 1)) * (data[j].close - data[prevIndex].close) -
          (prevIndex - j) * (avgClose - data[prevIndex].close)
        );
        if (area > maxArea) {
          maxArea = area;
          maxIndex = j;
        }
      }

      sampled.push(data[maxIndex]);
      prevIndex = maxIndex;
    }

    sampled.push(data[data.length - 1]);
    return sampled;
  }
}
