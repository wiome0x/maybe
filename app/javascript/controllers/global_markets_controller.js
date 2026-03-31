import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="global-markets"
// Displays global market indices and exchange clocks
export default class extends Controller {
  static targets = ["indices", "clock", "clockTime", "clockStatus"];

  // Major global indices with TradingView symbols
  INDICES = [
    { name: "S&P 500",  symbol: "SPX",       flag: "🇺🇸" },
    { name: "NASDAQ",   symbol: "IXIC",      flag: "🇺🇸" },
    { name: "DOW",      symbol: "DJI",       flag: "🇺🇸" },
    { name: "日经225",  symbol: "NI225",     flag: "🇯🇵" },
    { name: "上证",     symbol: "SHCOMP",    flag: "🇨🇳" },
    { name: "恒生",     symbol: "HSI",       flag: "🇭🇰" },
    { name: "DAX",      symbol: "DAX",       flag: "🇩🇪" },
    { name: "FTSE100",  symbol: "UKX",       flag: "🇬🇧" },
  ];

  connect() {
    this.updateClocks();
    this.loadIndices();

    // Update clocks every second
    this.clockTimer = setInterval(() => this.updateClocks(), 1000);
    // Refresh indices every 60 seconds
    this.indicesTimer = setInterval(() => this.loadIndices(), 60000);
  }

  disconnect() {
    clearInterval(this.clockTimer);
    clearInterval(this.indicesTimer);
  }

  // ── Clocks ──────────────────────────────────────────────────────────────

  updateClocks() {
    const now = new Date();

    this.clockTargets.forEach((el, i) => {
      const tz       = el.dataset.timezone;
      const city     = el.dataset.city;
      const openStr  = el.dataset.open;
      const closeStr = el.dataset.close;

      const timeEl   = this.clockTimeTargets[i];
      const statusEl = this.clockStatusTargets[i];

      if (!timeEl || !statusEl) return;

      // Format local time in that timezone
      const localTime = new Intl.DateTimeFormat("zh-CN", {
        timeZone: tz,
        month: "2-digit",
        day:   "2-digit",
        hour:  "2-digit",
        minute:"2-digit",
        second:"2-digit",
        hour12: false,
      }).format(now);

      timeEl.textContent = `${city} ${localTime}`;

      // Determine open/closed status
      const localHHMM = new Intl.DateTimeFormat("en-US", {
        timeZone: tz,
        hour:   "2-digit",
        minute: "2-digit",
        hour12: false,
        weekday: "short",
      }).formatToParts(now);

      const weekday = localHHMM.find(p => p.type === "weekday")?.value;
      const hour    = parseInt(localHHMM.find(p => p.type === "hour")?.value || "0");
      const minute  = parseInt(localHHMM.find(p => p.type === "minute")?.value || "0");
      const current = hour * 60 + minute;

      const [oh, om] = openStr.split(":").map(Number);
      const [ch, cm] = closeStr.split(":").map(Number);
      const openMin  = oh * 60 + om;
      const closeMin = ch * 60 + cm;

      const isWeekend = weekday === "Sat" || weekday === "Sun";
      const isOpen    = !isWeekend && current >= openMin && current < closeMin;

      if (isOpen) {
        const remaining = closeMin - current;
        const rh = Math.floor(remaining / 60);
        const rm = remaining % 60;
        statusEl.textContent = `开市中 · 收盘还剩 ${rh}h${rm}m`;
        statusEl.className = "text-xs text-green-500";
      } else if (!isWeekend && current < openMin) {
        const wait = openMin - current;
        const wh = Math.floor(wait / 60);
        const wm = wait % 60;
        statusEl.textContent = `休市 · ${wh}h${wm}m 后开市`;
        statusEl.className = "text-xs text-secondary";
      } else {
        statusEl.textContent = isWeekend ? "周末休市" : "已收盘";
        statusEl.className = "text-xs text-secondary";
      }
    });
  }

  // ── Indices ──────────────────────────────────────────────────────────────

  async loadIndices() {
    // Use Yahoo Finance public API (no key needed)
    const symbols = this.INDICES.map(i => i.symbol).join(",");
    const url = `https://query1.finance.yahoo.com/v7/finance/quote?symbols=${symbols}&fields=regularMarketPrice,regularMarketChangePercent`;

    try {
      const res = await fetch(url, { headers: { "Accept": "application/json" } });
      if (!res.ok) throw new Error("fetch failed");
      const data = await res.json();
      const results = data?.quoteResponse?.result || [];

      const priceMap = {};
      results.forEach(q => { priceMap[q.symbol] = q; });

      this.renderIndices(priceMap);
    } catch {
      // Fallback: show static labels without prices
      this.renderIndices({});
    }
  }

  renderIndices(priceMap) {
    const isRedUp = document.body.dataset.trendColor === "red_up";

    const html = this.INDICES.map(idx => {
      const q = priceMap[idx.symbol];
      const price = q?.regularMarketPrice;
      const pct   = q?.regularMarketChangePercent;

      const priceStr = price != null ? price.toLocaleString("en-US", { maximumFractionDigits: 2 }) : "--";
      const pctStr   = pct   != null ? `${pct >= 0 ? "+" : ""}${pct.toFixed(2)}%` : "";

      let colorClass = "text-secondary";
      if (pct != null) {
        const up = pct >= 0;
        colorClass = isRedUp
          ? (up ? "text-red-500" : "text-green-500")
          : (up ? "text-green-500" : "text-red-500");
      }

      return `
        <span class="flex items-center gap-1.5">
          <span class="text-secondary">${idx.flag} ${idx.name}</span>
          <span class="font-medium text-primary">${priceStr}</span>
          ${pctStr ? `<span class="font-medium ${colorClass}">${pctStr}</span>` : ""}
        </span>
      `;
    }).join('<span class="text-subdued">·</span>');

    this.indicesTarget.innerHTML = html;
  }
}
