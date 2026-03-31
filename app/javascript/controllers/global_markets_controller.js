import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["indices", "clocks"];

  INDICES = [
    { name: "上证",    symbol: "000001.SS", flag: "🇨🇳" },
    { name: "恒生",    symbol: "^HSI",      flag: "🇭🇰" },
    { name: "S&P 500", symbol: "^GSPC",     flag: "🇺🇸" },
    { name: "NASDAQ",  symbol: "^IXIC",     flag: "🇺🇸" },
    { name: "DOW",     symbol: "^DJI",      flag: "🇺🇸" },
    { name: "DAX",     symbol: "^GDAXI",    flag: "🇩🇪" },
    { name: "FTSE100", symbol: "^FTSE",     flag: "🇬🇧" },
    { name: "日经225", symbol: "^N225",     flag: "🇯🇵" },
  ];

  EXCHANGES = [
    { flag: "🇨🇳", city: "北京",     tz: "Asia/Shanghai",    open: "09:30", close: "15:00" },
    { flag: "🇺🇸", city: "纽约",     tz: "America/New_York", open: "09:30", close: "16:00" },
    { flag: "🇬🇧", city: "伦敦",     tz: "Europe/London",    open: "08:00", close: "16:30" },
    { flag: "🇪🇺", city: "法兰克福", tz: "Europe/Berlin",    open: "09:00", close: "17:30" },
    { flag: "🇯🇵", city: "东京",     tz: "Asia/Tokyo",       open: "09:00", close: "15:00" },
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
      <div class="flex items-center gap-2">
        <span class="text-base">${ex.flag}</span>
        <div class="min-w-0">
          <p class="text-primary font-medium text-sm whitespace-nowrap" id="clock-time-${i}"></p>
          <p class="text-xs whitespace-nowrap" id="clock-status-${i}"></p>
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
        const rh = Math.floor(r / 60);
        const rm = r % 60;
        statusEl.textContent = `交易中 · ${rh}小时${rm}分后收盘`;
        statusEl.className = "text-xs whitespace-nowrap text-green-500";
      } else if (isWeekend) {
        statusEl.textContent = "周末休市";
        statusEl.className = "text-xs whitespace-nowrap text-secondary";
      } else if (current < openMin) {
        const w = openMin - current;
        const wh = Math.floor(w / 60);
        const wm = w % 60;
        statusEl.textContent = `未开盘 · ${wh}小时${wm}分后开盘`;
        statusEl.className = "text-xs whitespace-nowrap text-secondary";
      } else {
        statusEl.textContent = "已收盘";
        statusEl.className = "text-xs whitespace-nowrap text-secondary";
      }
    });
  }

  async loadIndices() {
    try {
      const res = await fetch("/markets/indices.json");
      if (res.ok) {
        const data = await res.json();
        if (data && Object.keys(data).length > 0) {
          this.renderIndices(data);
          return;
        }
      }
    } catch { /* fall through */ }
    this.renderIndices({});
  }

  renderIndices(priceMap) {
    const isRedUp = document.body.dataset.trendColor === "red_up";

    const html = this.INDICES.map(idx => {
      const q = priceMap[idx.symbol];
      const price = q?.price;
      const pct = q?.change_percent;
      const priceStr = price != null
        ? Number(price).toLocaleString("en-US", { maximumFractionDigits: 2 })
        : "--";
      const pctStr = pct != null
        ? `${pct >= 0 ? "+" : ""}${Number(pct).toFixed(2)}%`
        : "";

      let color = "text-secondary";
      if (pct != null) {
        const up = pct >= 0;
        color = isRedUp
          ? (up ? "text-red-500" : "text-green-500")
          : (up ? "text-green-500" : "text-red-500");
      }

      return `<div class="flex items-baseline gap-1.5 whitespace-nowrap">
        <span class="text-secondary">${idx.flag} ${idx.name}</span>
        <span class="font-medium text-primary">${priceStr}</span>
        ${pctStr ? `<span class="font-medium ${color}">${pctStr}</span>` : ""}
      </div>`;
    }).join("");

    this.indicesTarget.innerHTML = html;
  }
}
