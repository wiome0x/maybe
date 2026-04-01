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
    ];

    const total = data.reduce((s, d) => s + d.value, 0);
    if (total <= 0) return;

    const size = 180;
    const cx = size / 2;
    const cy = size / 2;
    const outerR = 75;
    const innerR = 45;
    const gap = isDark ? "#1f2937" : "#ffffff";
    const textColor = isDark ? "#d1d5db" : "#374151";

    let paths = "";
    let cumAngle = -90;

    data.forEach((item, i) => {
      const sliceDeg = (item.value / total) * 360;
      const startRad = (cumAngle * Math.PI) / 180;
      const endRad = ((cumAngle + sliceDeg) * Math.PI) / 180;
      const largeArc = sliceDeg > 180 ? 1 : 0;
      const color = colors[i % colors.length];

      // Outer arc start/end
      const ox1 = cx + outerR * Math.cos(startRad);
      const oy1 = cy + outerR * Math.sin(startRad);
      const ox2 = cx + outerR * Math.cos(endRad);
      const oy2 = cy + outerR * Math.sin(endRad);
      // Inner arc end/start (reverse)
      const ix1 = cx + innerR * Math.cos(endRad);
      const iy1 = cy + innerR * Math.sin(endRad);
      const ix2 = cx + innerR * Math.cos(startRad);
      const iy2 = cy + innerR * Math.sin(startRad);

      paths += `<path d="M${ox1} ${oy1} A${outerR} ${outerR} 0 ${largeArc} 1 ${ox2} ${oy2} L${ix1} ${iy1} A${innerR} ${innerR} 0 ${largeArc} 0 ${ix2} ${iy2} Z" fill="${color}" stroke="${gap}" stroke-width="2"/>`;

      cumAngle += sliceDeg;
    });

    // Build legend items
    const legendItems = data.map((item, i) => {
      const color = colors[i % colors.length];
      return `<div style="display:flex;align-items:center;gap:6px;padding:2px 0">
        <span style="width:10px;height:10px;border-radius:2px;background:${color};flex-shrink:0"></span>
        <span style="font-size:12px;color:${textColor}">${item.label}</span>
        <span style="font-size:12px;font-weight:600;color:${textColor};margin-left:auto">${item.value}%</span>
      </div>`;
    }).join("");

    this.canvasTarget.innerHTML = `
      <div style="display:flex;align-items:center;gap:24px;flex-wrap:wrap;justify-content:center">
        <svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" style="flex-shrink:0">
          ${paths}
        </svg>
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:4px 24px">
          ${legendItems}
        </div>
      </div>
    `;
  }
}
