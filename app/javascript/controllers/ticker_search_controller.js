import { Controller } from "@hotwired/stimulus";

// Ticker search that loads trend chart data via Turbo Frame on button click
export default class extends Controller {
  static targets = ["input", "startDate", "endDate", "list", "chip"];

  connect() {
    this.filter();
  }

  filter() {
    if (!this.hasChipTarget || !this.hasInputTarget) return;

    const query = this.inputTarget.value.trim().toLowerCase();
    this.chipTargets.forEach((chip) => {
      const searchText = chip.dataset.searchText || "";
      chip.classList.toggle("hidden", query.length > 0 && !searchText.includes(query));
    });
  }

  selectTicker(event) {
    const ticker = event.currentTarget.dataset.ticker;
    if (!ticker || !this.hasInputTarget) return;

    this.inputTarget.value = ticker;
    this.filter();
    this.search();
  }

  search() {
    const ticker = this.inputTarget.value.trim().toUpperCase();
    if (!ticker) return;

    const url = new URL("/data_tracking/trend", window.location.origin);
    url.searchParams.set("ticker", ticker);

    if (this.hasStartDateTarget && this.startDateTarget.value) {
      url.searchParams.set("start_date", this.startDateTarget.value);
    }

    if (this.hasEndDateTarget && this.endDateTarget.value) {
      url.searchParams.set("end_date", this.endDateTarget.value);
    }

    const frame = document.getElementById("trend_chart");
    if (frame) {
      frame.src = url.toString();
    }
  }
}
