import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["indices", "clocks"];

  INDICES = [
    { name: "S&P 500", symbol: "SPX",   flag: "🇺🇸" },
    { name: "NASDAQ",  symbol: "IXIC",  flag: "🇺🇸" },
    { name: "DOW",     symbol: "DJI",   flag: "🇺🇸" },
    { name: "日经225", symbol: "NI225", flag: "🇯🇵" },
    { name: "上证",    symbol: "SHCOMP",flag: "🇨🇳" },
    { name: "恒生",    symbol: "HSI",   flag: "🇭🇰" },
    { name: "DAX",     symbol: "DAX",   flag: "🇩🇪" },
    { name: "FTSE100", symbol: "UKX",   flag: "🇬🇧" },
  ];

  EXCHANGES = [
    { flag: "🇨🇳", city: "北京",      tz: "Asia/Shanghai",    open: "09:30", close: "15:00" },
    { flag: "🇯🇵", city: "东京",      tz: "Asia/Tokyo",       open: "09:00", close: "15:00" },
    { flag: "🇬🇧", city: "伦敦",      tz: "Europe/London",    open: "08:00", close: "16:30" },
    { flag: "🇪🇺", city: "法兰克福",  tz: "Europe/Berlin",    open: "09:00", close: "17:30" },
    { flag: "🇺🇸", city: "纽约",      tz: "America/New_York", open: "09:30", close: "16:00" },
  ];

  connect() {
    this.renderClocks();
    this.updateClocks();
    this.loadIndices();
    this.clockTimer = setInterval(() => this.updateClocks(), 1000);
    this.indicesTimer = setInterval(() => this.loadIndices(), 60000);
  }

  disconnect() {
    clearInterval(this.clockTimer);
    clearInterval(this.indicesTimer);
  }

  renderClocks() {
    this.clocksTarget.innerHTML = this.EXCHANGES.map((ex, i) => `
      <div class="flex items-center gap-2 shrink-0">
        <span class="text-lg">${ex.flag}</span>
        <div>
          <p class="text-primary font-medium text-sm" id="clock-time-${i}"></p>
          <p class="text-xs text-secondary" id="clock-status-${i}"></p>
        </div>
      </div>
    `).join("");
  }

  updateClocks() {
    const now = new Date();
    this.EXCHANGES.forEach((ex, i) => {
      const timeEl = document.getElementById(`clock-time-${i}`);
      const statusEl = document.getElementById(`clock-status-${i}`);
      if (!timeEl || !statusEl) return;

      const localTime = new Intl.DateTimeFormat("zh-CN", {
        timeZone: ex.tz, month: "2-digit", day: "2-digit",
        hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: false,
      }).format(now);

      timeEl.textContent = `${ex.city} ${localTime}`;

      const parts = new Intl.DateTimeFormat("en-US", {
        timeZone: ex.tz, hour: "2-digit", minute: "2-digit", hour12: false, weekday: "short",
      }).formatToParts(now);

      const weekday = parts.find(p => p.type === "weekday")?.value;
      const hour = parseInt(parts.find(p => p.type === "hour")?.value || "0");
      const minute = parseInt(parts.find(p => p.type === "minute")?.value || "0");
      const current = hour * 60 + minute;

      const [oh, om] = ex.open.split(":").map(Number);
      const [ch, cm] = ex.close.split(":").map(Number);
      const openMin = oh * 60 + om;
      const closeMin = ch * 60 + cm;

      const isWeekend = weekday === "Sat" || weekday === "Sun";
      const isOpen = !isWeekend && current >= openMin && current < closeMin;

      if (isOpen) {
        const r = closeMin - current;
        statusEl.textContent = `开市中 · ${Math.floor(r/60)}h${r%60}m`;
        statusEl.className = "text-xs text-green-500";
      } else if (!isWeekend && current < openMin) {
        const w = openMin - current;
        statusEl.textContent = `休市 · ${Math.floor(w/60)}h${w%60}m 后开市`;
        statusEl.className = "text-xs text-secondary";
      } else {
        statusEl.textContent = isWeekend ? "周末休市" : "已收盘";
        statusEl.className = "text-xs text-secondary";
      }
    });
  }

  async loadIndices() {
    const symbols = this.INDICES.map(i => i.symbol).join(",");
    try {
      const res = await fetch(
        `https://query1.finance.yahoo.com/v7/finance/quote?symbols=${symbols}&fields=regularMarketPrice,regularMarketChangePercent`,
        { headers: { Accept: "application/json" } }
      );
      if (!res.ok) throw new Error("fetch failed");
      const data = await res.json();
      const results = data?.quoteResponse?.result || [];
      const map = {};
      results.forEach(q => { map[q.symbol] = q; });
      this.renderIndices(map);
    } catch {
      this.renderIndices({});
    }
  }

  renderIndices(priceMap) {
    const isRedUp = document.body.dataset.trendColor === "red_up";
    const html = this.INDICES.map(idx => {
      const q = priceMap[idx.symbol];
      const price = q?.regularMarketPrice;
      const pct = q?.regularMarketChangePercent;
      const priceStr = price != null ? price.toLocaleString("en-US", { maximumFractionDigits: 2 }) : "--";
      const pctStr = pct != null ? `${pct >= 0 ? "+" : ""}${pct.toFixed(2)}%` : "";
      let color = "text-secondary";
      if (pct != null) {
        const up = pct >= 0;
        color = isRedUp ? (up ? "text-red-500" : "text-green-500") : (up ? "text-green-500" : "text-red-500");
      }
      return `<span class="flex items-center gap-1.5">
        <span class="text-secondary">${idx.flag} ${idx.name}</span>
        <span class="font-medium text-primary">${priceStr}</span>
        ${pctStr ? `<span class="font-medium ${color}">${pctStr}</span>` : ""}
      </span>`;
    }).join('<span class="text-subdued">·</span>');
    this.indicesTarget.innerHTML = html;
  }
}
