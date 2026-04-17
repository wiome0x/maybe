import { Controller } from "@hotwired/stimulus";
import { geoEquirectangular } from "d3-geo";

export default class extends Controller {
  static targets = ["map"];

  MARKETS = [
    { name: "道琼斯", symbol: "^DJI", lon: -74.0, lat: 40.7, dx: -68, dy: -98, compactDx: -52, compactDy: -82, align: "center" },
    { name: "纳斯达克", symbol: "^IXIC", lon: -74.0, lat: 40.7, dx: -122, dy: -8, compactDx: -98, compactDy: -6, align: "right" },
    { name: "标普", symbol: "^GSPC", lon: -76.5, lat: 38.9, dx: 18, dy: 8, compactDx: 18, compactDy: 10, align: "left" },
    { name: "英国富时", symbol: "^FTSE", lon: -0.1, lat: 51.5, dx: -24, dy: -108, compactDx: -12, compactDy: -90, align: "center" },
    { name: "德国DAX", symbol: "^GDAXI", lon: 8.7, lat: 50.1, dx: 42, dy: -76, compactDx: 32, compactDy: -60, align: "left" },
    { name: "法国CAC", symbol: "^FCHI", lon: 2.3, lat: 48.9, dx: 6, dy: 18, compactDx: 2, compactDy: 14, align: "center" },
    { name: "上证", symbol: "000001.SS", lon: 121.5, lat: 31.2, dx: -26, dy: -82, compactDx: -26, compactDy: -64, align: "center" },
    { name: "北证", symbol: "899050.BJ", lon: 116.4, lat: 39.9, dx: 52, dy: -118, compactDx: 42, compactDy: -96, align: "left" },
    { name: "恒生", symbol: "^HSI", lon: 114.2, lat: 22.3, dx: 54, dy: 6, compactDx: 52, compactDy: 6, align: "left" },
    { name: "日经", symbol: "^N225", lon: 139.7, lat: 35.7, dx: 40, dy: -20, compactDx: 28, compactDy: -12, align: "left" },
    { name: "深成", symbol: "399001.SZ", lon: 114.2, lat: 22.9, dx: -44, dy: 42, compactDx: -42, compactDy: 34, align: "center" },
    { name: "印度", symbol: "^NSEI", lon: 78.0, lat: 22.6, dx: -46, dy: -6, compactDx: -34, compactDy: -8, align: "center" },
    { name: "越南", symbol: "^VNINDEX", lon: 105.8, lat: 16.1, dx: -20, dy: 58, compactDx: -14, compactDy: 46, align: "center" },
    { name: "澳大利亚", symbol: "^AXJO", lon: 133.8, lat: -25.3, dx: 14, dy: -70, compactDx: 8, compactDy: -58, align: "center" },
    { name: "巴西", symbol: "^BVSP", lon: -47.9, lat: -15.8, dx: -12, dy: -88, compactDx: -10, compactDy: -72, align: "center" },
  ];

  connect() {
    this.prepareOverlay();
    this.renderMarkets({});
    this.loadMarkets();
    this.refreshTimer = setInterval(() => this.loadMarkets(), 60000);

    this.resizeObserver = new ResizeObserver(() => {
      this.prepareOverlay();
      this.renderMarkets(this.latestPriceMap || {});
    });
    this.resizeObserver.observe(this.mapTarget);
  }

  disconnect() {
    clearInterval(this.refreshTimer);
    this.resizeObserver?.disconnect();
  }

  async loadMarkets() {
    try {
      const res = await fetch("/markets/indices.json");
      if (res.ok) {
        const data = await res.json();
        if (data && Object.keys(data).length > 0) {
          this.latestPriceMap = data;
          this.renderMarkets(data);
          return;
        }
      }
    } catch {
      // fall through to placeholder rendering
    }

    this.renderMarkets(this.latestPriceMap || {});
  }

  prepareOverlay() {
    const width = this.mapTarget.clientWidth || 1;
    const height = this.mapTarget.clientHeight || 1;

    this.projection = geoEquirectangular()
      .scale(width / (2 * Math.PI))
      .translate([width / 2, height / 2]);

    this.mapTarget.innerHTML = `
      <div class="absolute inset-0 pointer-events-none" data-global-markets-map-markers></div>
    `;

    this.markersLayer = this.mapTarget.querySelector("[data-global-markets-map-markers]");
  }

  renderMarkets(priceMap) {
    const isRedUp = document.body.dataset.trendColor === "red_up";
    const width = this.mapTarget.clientWidth || 1;
    const height = this.mapTarget.clientHeight || 1;

    const markers = this.MARKETS.map((market) => {
      const quote = priceMap[market.symbol];
      const pct = quote?.change_percent;
      const price = quote?.price;
      const pctStr = pct != null
        ? `${pct >= 0 ? "+" : ""}${Number(pct).toFixed(2)}%`
        : "--";
      const priceStr = price != null
        ? Number(price).toLocaleString("en-US", { maximumFractionDigits: 2 })
        : null;

      let color = "#6b7280";
      if (pct != null) {
        const up = pct >= 0;
        color = isRedUp
          ? (up ? "#ef4444" : "#16a34a")
          : (up ? "#16a34a" : "#ef4444");
      }

      const projected = this.projection([market.lon, market.lat]) || [width / 2, height / 2];
      const [x, y] = projected;
      const { dx, dy } = this.labelOffsetFor(market, width);
      const alignClass = market.align === "right"
        ? "items-end text-right"
        : market.align === "left"
          ? "items-start text-left"
          : "items-center text-center";

      return `
        <div
          class="absolute pointer-events-none"
          style="left:${x}px; top:${y}px; transform: translate(${dx}px, ${dy}px);"
        >
          <div class="flex flex-col gap-1 leading-none ${alignClass}">
            <div class="rounded-[22px] px-1.5 py-1" style="color:${color}; text-shadow: 0 1px 1px rgba(255,255,255,.9);">
              <div class="text-[clamp(12px,1.45vw,18px)] font-medium tracking-[-0.02em] whitespace-nowrap text-slate-800/95" style="color:${pct != null ? "#1f2937" : "#667085"}">${market.name}</div>
              ${priceStr ? `<div class="mt-1 text-[clamp(11px,1.1vw,14px)] font-medium whitespace-nowrap text-slate-500" style="color:#667085">${priceStr}</div>` : ""}
              <div class="mt-1 text-[clamp(15px,1.7vw,22px)] font-medium tracking-[-0.03em] whitespace-nowrap" style="color:${color}">${pctStr}</div>
            </div>
            <span class="h-3.5 w-3.5 rounded-full shadow-[0_0_0_5px_rgba(255,255,255,.72),0_10px_18px_rgba(15,23,42,.08)]" style="background-color:${color};"></span>
          </div>
        </div>
      `;
    }).join("");

    if (this.markersLayer) {
      this.markersLayer.innerHTML = markers;
    }
  }

  labelOffsetFor(market, width) {
    if (width <= 720) {
      return {
        dx: market.compactDx ?? market.dx,
        dy: market.compactDy ?? market.dy,
      };
    }

    return { dx: market.dx, dy: market.dy };
  }
}
