import { Controller } from "@hotwired/stimulus";

// Connects to Binance WebSocket combined stream for real-time crypto ticker updates.
// Usage:
//   <div data-controller="binance-ticker"
//        data-binance-ticker-symbols-value='["BTC","ETH","BNB"]'>
//     <span data-binance-ticker-target="price" data-symbol="BTC">$105,000</span>
//     <span data-binance-ticker-target="change" data-symbol="BTC">+2.34%</span>
//   </div>
export default class extends Controller {
  static values = { symbols: Array };
  static targets = ["price", "change"];

  connect() {
    if (this.symbolsValue.length === 0) return;
    this.#openSocket();
  }

  disconnect() {
    this.#closeSocket();
  }

  // ─── Private ──────────────────────────────────────────────────────────────

  #openSocket() {
    const streams = this.symbolsValue
      .map((s) => `${s.toLowerCase()}usdt@ticker`)
      .join("/");

    this.ws = new WebSocket(
      `wss://stream.binance.com:9443/stream?streams=${streams}`
    );

    this.ws.onmessage = (event) => {
      const { data } = JSON.parse(event.data);
      if (!data) return;
      this.#update(data.s, data.c, data.P);
    };

    this.ws.onerror = () => {
      // Silently retry after 5 s on error
      this.#scheduleReconnect();
    };

    this.ws.onclose = (event) => {
      // 1000 = normal close (disconnect() called), don't retry
      if (event.code !== 1000) this.#scheduleReconnect();
    };
  }

  #closeSocket() {
    clearTimeout(this.reconnectTimer);
    if (this.ws) {
      this.ws.onclose = null; // prevent reconnect loop
      this.ws.close(1000);
      this.ws = null;
    }
  }

  #scheduleReconnect() {
    clearTimeout(this.reconnectTimer);
    this.reconnectTimer = setTimeout(() => this.#openSocket(), 5000);
  }

  // symbol from Binance is e.g. "BTCUSDT" — strip the USDT suffix for matching
  #update(rawSymbol, priceStr, changePctStr) {
    const symbol = rawSymbol.replace(/USDT$/i, "").toUpperCase();
    const price = Number.parseFloat(priceStr);
    const changePct = Number.parseFloat(changePctStr);

    if (Number.isNaN(price)) return;

    const isRedUp = document.body.dataset.trendColor === "red_up";
    const positive = changePct >= 0;
    const upColor = isRedUp ? "text-red-600" : "text-green-600";
    const downColor = isRedUp ? "text-green-600" : "text-red-600";
    const colorClass = positive ? upColor : downColor;

    for (const el of this.priceTargets) {
      if (el.dataset.symbol?.toUpperCase() !== symbol) continue;
      el.textContent = `$${this.#formatPrice(price)}`;
    }

    for (const el of this.changeTargets) {
      if (el.dataset.symbol?.toUpperCase() !== symbol) continue;
      // Remove previous color classes before applying new ones
      el.classList.remove("text-red-600", "text-green-600");
      el.classList.add(colorClass);
      el.textContent = `${positive ? "+" : ""}${changePct.toFixed(2)}%`;
    }
  }

  #formatPrice(price) {
    if (price >= 1000) return price.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    if (price >= 1) return price.toFixed(4);
    return price.toFixed(6);
  }
}
