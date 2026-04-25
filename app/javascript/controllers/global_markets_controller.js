import { Controller } from "@hotwired/stimulus";
import { geoEquirectangular } from "d3-geo";

// Trading sessions: open/close in local exchange time, expressed as UTC offsets (standard time)
// We account for DST manually per region where needed.
const SESSIONS = [
  {
    name: "美股",
    tz: "America/New_York",
    openH: 9, openM: 30,
    closeH: 16, closeM: 0,
    // Mon–Fri only
  },
  {
    name: "沪深",
    tz: "Asia/Shanghai",
    openH: 9, openM: 30,
    closeH: 15, closeM: 0,
    // Morning: 9:30–11:30, Afternoon: 13:00–15:00
    lunchBreak: { startH: 11, startM: 30, endH: 13, endM: 0 },
  },
  {
    name: "港股",
    tz: "Asia/Hong_Kong",
    openH: 9, openM: 30,
    closeH: 16, closeM: 0,
    lunchBreak: { startH: 12, startM: 0, endH: 13, endM: 0 },
  },
  {
    name: "日经",
    tz: "Asia/Tokyo",
    openH: 9, openM: 0,
    closeH: 15, closeM: 30,
    lunchBreak: { startH: 11, startM: 30, endH: 12, endM: 30 },
  },
  {
    name: "英股",
    tz: "Europe/London",
    openH: 8, openM: 0,
    closeH: 16, closeM: 30,
  },
  {
    name: "德股",
    tz: "Europe/Berlin",
    openH: 9, openM: 0,
    closeH: 17, closeM: 30,
  },
];

export default class extends Controller {
  static targets = ["map", "sessions", "mapContainer"];

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
    { name: "越南", symbol: "^VNINDEX", lon: 105.8, lat: 16.1, dx: -18, dy: 88, compactDx: -12, compactDy: 72, align: "center" },
    { name: "澳大利亚", symbol: "^AXJO", lon: 133.8, lat: -25.3, dx: 18, dy: -34, compactDx: 12, compactDy: -24, align: "center" },
    { name: "巴西", symbol: "^BVSP", lon: -47.9, lat: -15.8, dx: -12, dy: -88, compactDx: -10, compactDy: -72, align: "center" },
  ];

  connect() {
    this.prepareOverlay();
    this.renderMarkets({});
    this.loadMarkets();
    this.refreshTimer = setInterval(() => this.loadMarkets(), 60000);

    // Update session clocks every 30 seconds
    this.renderSessions();
    this.sessionTimer = setInterval(() => this.renderSessions(), 30000);

    this.resizeObserver = new ResizeObserver(() => {
      this.prepareOverlay();
      this.renderMarkets(this.latestPriceMap || {});
    });
    this.resizeObserver.observe(this.mapContainerTarget);
  }

  disconnect() {
    clearInterval(this.refreshTimer);
    clearInterval(this.sessionTimer);
    this.resizeObserver?.disconnect();
  }

  // ─── Session clock rendering ──────────────────────────────────────────────

  renderSessions() {
    if (!this.hasSessionsTarget) return;

    const now = new Date();
    const html = SESSIONS.map((session) => this.#sessionBadge(session, now)).join("");
    this.sessionsTarget.innerHTML = html;
  }

  #sessionBadge(session, now) {
    const { open, minutesUntilOpen, minutesUntilClose, inLunch } = this.#sessionStatus(session, now);

    let dotColor;
    let statusText;
    let timeText;

    if (open && !inLunch) {
      dotColor = "#16a34a";
      statusText = "盘中";
      timeText = minutesUntilClose != null ? `${this.#fmtMins(minutesUntilClose)}后收盘` : "";
    } else if (inLunch) {
      dotColor = "#f59e0b";
      statusText = "午休";
      timeText = minutesUntilClose != null ? `${this.#fmtMins(minutesUntilClose)}后开盘` : "";
    } else {
      dotColor = "#cbd5e1";
      statusText = "休市";
      timeText = minutesUntilOpen != null ? `${this.#fmtMins(minutesUntilOpen)}后开盘` : "周末休市";
    }

    return `
      <div style="display:flex; align-items:center; justify-content:space-between; padding:6px 0; border-bottom:1px solid rgba(0,0,0,0.05);">
        <div style="display:flex; align-items:center; gap:7px;">
          <span style="width:6px; height:6px; border-radius:50%; background:${dotColor}; flex-shrink:0; box-shadow:0 0 0 2.5px ${dotColor}30;"></span>
          <span style="font-size:12px; font-weight:600; color:#374151;">${session.name}</span>
          <span style="font-size:10px; font-weight:500; color:${dotColor}; background:${dotColor}15; padding:1px 5px; border-radius:4px;">${statusText}</span>
        </div>
        <span style="font-size:10px; color:#94a3b8; white-space:nowrap; padding-left:6px;">${timeText}</span>
      </div>
    `;
  }

  /**
   * Returns session status relative to `now`.
   * All times are computed in the exchange's local timezone.
   */
  #sessionStatus(session, now) {
    // Get local time in exchange timezone
    const localStr = now.toLocaleString("en-US", { timeZone: session.tz, hour12: false,
      year: "numeric", month: "2-digit", day: "2-digit",
      hour: "2-digit", minute: "2-digit", weekday: "short" });

    // Parse: "Mon, 04/25/2026, 09:35"
    const parts = localStr.match(/(\w+),\s+(\d+)\/(\d+)\/(\d+),\s+(\d+):(\d+)/);
    if (!parts) return { open: false };

    const [, weekday, month, day, year, hourStr, minStr] = parts;
    const hour = Number.parseInt(hourStr === "24" ? "0" : hourStr, 10);
    const minute = Number.parseInt(minStr, 10);
    const dayOfWeek = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"].indexOf(weekday);

    // Weekend = closed
    if (dayOfWeek === 0 || dayOfWeek === 6) {
      // Find minutes until Monday open
      const daysUntilMon = dayOfWeek === 6 ? 2 : 1;
      const minsUntilOpen = daysUntilMon * 24 * 60
        - (hour * 60 + minute)
        + (session.openH * 60 + session.openM);
      return { open: false, minutesUntilOpen: minsUntilOpen };
    }

    const nowMins = hour * 60 + minute;
    const openMins = session.openH * 60 + session.openM;
    const closeMins = session.closeH * 60 + session.closeM;

    // Lunch break check
    let inLunch = false;
    let lunchEndMins = null;
    if (session.lunchBreak) {
      const lbStart = session.lunchBreak.startH * 60 + session.lunchBreak.startM;
      const lbEnd = session.lunchBreak.endH * 60 + session.lunchBreak.endM;
      if (nowMins >= lbStart && nowMins < lbEnd) {
        inLunch = true;
        lunchEndMins = lbEnd - nowMins;
      }
    }

    if (nowMins >= openMins && nowMins < closeMins) {
      return {
        open: true,
        inLunch,
        minutesUntilClose: inLunch ? lunchEndMins : (closeMins - nowMins),
      };
    }

    // Before open today
    if (nowMins < openMins) {
      return { open: false, minutesUntilOpen: openMins - nowMins };
    }

    // After close — next trading day open
    const minsUntilTomorrow = 24 * 60 - nowMins + openMins;
    // If tomorrow is Saturday, add 2 more days
    const nextDayOfWeek = (dayOfWeek + 1) % 7;
    const extraDays = nextDayOfWeek === 6 ? 2 : nextDayOfWeek === 0 ? 1 : 0;
    return { open: false, minutesUntilOpen: minsUntilTomorrow + extraDays * 24 * 60 };
  }

  /** Format minutes into "Xh Ym" or "Ym" */
  #fmtMins(totalMins) {
    if (totalMins == null || totalMins < 0) return "";
    const h = Math.floor(totalMins / 60);
    const m = totalMins % 60;
    if (h > 0 && m > 0) return `${h}h${m}m`;
    if (h > 0) return `${h}h`;
    return `${m}m`;
  }

  // ─── Map rendering (unchanged) ────────────────────────────────────────────

  async loadMarkets() {
    try {
      const res = await fetch("/markets/indices.json");
      if (!res.ok) {
        console.warn(`[global-markets] indices request failed with status ${res.status}`);
        this.renderMarkets(this.latestPriceMap || {});
        return;
      }

      const data = await res.json();
      if (data && Object.keys(data).length > 0) {
        this.latestPriceMap = data;
        this.renderMarkets(data);
        return;
      }

      console.warn("[global-markets] indices request returned empty payload");
    } catch {
      console.warn("[global-markets] indices request raised an exception");
      // fall through to placeholder rendering
    }

    this.renderMarkets(this.latestPriceMap || {});
  }

  prepareOverlay() {
    if (!this.hasMapContainerTarget) return;

    const container = this.mapContainerTarget;
    const cw = container.clientWidth || 1;
    const ch = container.clientHeight || 1;
    const padding = this.mapPadding(cw);
    const availableW = Math.max(cw - padding.left - padding.right, 1);
    const availableH = Math.max(ch - padding.top - padding.bottom, 1);

    container.style.setProperty("--gm-pad-top", `${padding.top}px`);
    container.style.setProperty("--gm-pad-right", `${padding.right}px`);
    container.style.setProperty("--gm-pad-bottom", `${padding.bottom}px`);
    container.style.setProperty("--gm-pad-left", `${padding.left}px`);

    // SVG intrinsic size
    const svgW = 1440;
    const svgH = 560;

    // Compute the rendered size of the SVG within a padded safe area so
    // market labels with negative offsets don't get clipped by the card.
    const scale = Math.min(availableW / svgW, availableH / svgH);
    const renderedW = svgW * scale;
    const renderedH = svgH * scale;

    // Center the map inside the padded safe area.
    const offsetX = padding.left + (availableW - renderedW) / 2;
    const offsetY = padding.top + (availableH - renderedH) / 2;

    // Map lon/lat → pixel using the rendered SVG dimensions
    this.projection = geoEquirectangular()
      .scale(renderedW / (2 * Math.PI))
      .translate([renderedW / 2 + offsetX, renderedH / 2 + offsetY]);

    this.mapTarget.innerHTML = `
      <div class="absolute inset-0 pointer-events-none" data-global-markets-map-markers></div>
    `;

    this.markersLayer = this.mapTarget.querySelector("[data-global-markets-map-markers]");
  }

  mapPadding(width) {
    if (width <= 720) {
      return { top: 28, right: 24, bottom: 20, left: 24 };
    }

    if (width <= 1080) {
      return { top: 52, right: 44, bottom: 26, left: 44 };
    }

    return { top: 72, right: 64, bottom: 32, left: 64 };
  }

  renderMarkets(priceMap) {
    if (!this.hasMapContainerTarget) return;

    const isRedUp = document.body.dataset.trendColor === "red_up";
    const container = this.mapContainerTarget;
    const cw = container.clientWidth || 1;

    const markers = this.MARKETS.map((market) => {
      const quote = priceMap[market.symbol];
      const pct = quote?.change_percent;
      const pctStr = pct != null
        ? `${pct >= 0 ? "+" : ""}${Number(pct).toFixed(2)}%`
        : "--";

      let color = "#6b7280";
      if (pct != null) {
        const up = pct >= 0;
        color = isRedUp
          ? (up ? "#ef4444" : "#16a34a")
          : (up ? "#16a34a" : "#ef4444");
      }

      const projected = this.projection([market.lon, market.lat]);
      if (!projected) return "";
      const [x, y] = projected;
      const { dx, dy } = this.labelOffsetFor(market, cw);
      const alignClass = market.align === "right"
        ? "items-end text-right"
        : market.align === "left"
          ? "items-start text-left"
          : "items-center text-center";

      return `
        <div
          class="absolute pointer-events-none z-10"
          style="left:${x}px; top:${y}px; transform: translate(${dx}px, ${dy}px);"
        >
          <div class="flex flex-col gap-1.5 leading-none ${alignClass}">
            <div class="px-1 py-0.5">
              <div
                class="text-[clamp(12px,1.35vw,17px)] font-semibold tracking-[-0.02em] whitespace-nowrap"
                style="color:#0f172a; text-shadow: 0 1px 0 rgba(255,255,255,0.92);"
              >${market.name}</div>
              <div
                class="mt-1 text-[clamp(14px,1.7vw,20px)] font-semibold whitespace-nowrap"
                style="color:${color}; text-shadow: 0 1px 0 rgba(255,255,255,0.9), 0 0 12px rgba(255,255,255,0.28);"
              >${pctStr}</div>
            </div>
            <span
              class="h-3 w-3 rounded-full"
              style="background-color:${color}; box-shadow: 0 0 0 4px rgba(255,255,255,0.92), 0 10px 18px rgba(15,23,42,0.12);"
            ></span>
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
