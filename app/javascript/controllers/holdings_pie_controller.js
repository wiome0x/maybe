import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = { data: Array };
  static targets = ["canvas"];

  connect() {
    if (!this.hasCanvasTarget || !this.dataValue.length) return;
    this.#render();
  }

  #render() {
    const data = this.dataValue;
    const isDark = document.documentElement.dataset.theme === "dark";
    const colors = [
      "#6B7280", "#3B82F6", "#10B981", "#F59E0B", "#EF4444",
      "#8B5CF6", "#EC4899", "#14B8A6", "#F97316", "#6366F1",
      "#84CC16", "#06B6D4",
    ];

    const total = data.reduce((s, d) => s + d.value, 0);
    if (total === 0) return;

    // Donut dimensions
    const cx = 100;
    const cy = 100;
    const r = 80;
    const ir = 50;
    const bg = isDark ? "#1f2937" : "#ffffff";
    const textColor = isDark ? "#d1d5db" : "#374151";

    let paths = "";
    let startAngle = -Math.PI / 2;

    data.forEach((item, i) => {
      const pct = item.value / total;
      const sweep = pct * 2 * Math.PI;
      const endAngle = startAngle + sweep;
      const large = sweep > Math.PI ? 1 : 0;
      const color = colors[i % colors.length];

      const x1 = cx + r * Math.cos(startAngle);
      const y1 = cy + r * Math.sin(startAngle);
      const x2 = cx + r * Math.cos(endAngle);
      const y2 = cy + r * Math.sin(endAngle);
      const x3 = cx + ir * Math.cos(endAngle);
      const y3 = cy + ir * Math.sin(endAngle);
      const x4 = cx + ir * Math.cos(startAngle);
      const y4 = cy + ir * Math.sin(startAngle);

      paths += `<path d="M${x1},${y1} A${r},${r} 0 ${large} 1 ${x2},${y2} L${x3},${y3} A${ir},${ir} 0 ${large} 0 ${x4},${y4}Z" fill="${color}" stroke="${bg}" stroke-width="2"/>`;
      startAngle = endAngle;
    });

    // Legend as HTML for better layout
    let legend = "";
    data.forEach((item, i) => {
      const color = colors[i % colors.length];
      legend += `<div class="flex items-center gap-2">
        <span class="w-2.5 h-2.5 rounded-sm shrink-0" style="background:${color}"></span>
        <span class="text-xs" style="color:${textColor}">${item.label}</span>
        <span class="text-xs font-medium ml-auto" style="color:${textColor}">${item.value}%</span>
      </div>`;
    });

    this.canvasTarget.innerHTML = `
      <div class="flex flex-col sm:flex-row items-center gap-6 w-full">
        <svg viewBox="0 0 200 200" width="200" height="200" class="shrink-0">
          ${paths}
        </svg>
        <div class="grid grid-cols-2 gap-x-6 gap-y-2 w-full max-w-xs">
          ${legend}
        </div>
      </div>
    `;
  }
}
