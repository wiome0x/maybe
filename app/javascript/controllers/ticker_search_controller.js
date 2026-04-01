import { Controller } from "@hotwired/stimulus";

// Debounced ticker search that loads trend chart data via Turbo Frame
export default class extends Controller {
  static targets = ["input", "startDate", "endDate"];

  search() {
    clearTimeout(this.timeout);
    this.timeout = setTimeout(() => {
      this.#submitSearch();
    }, 400);
  }

  disconnect() {
    clearTimeout(this.timeout);
  }

  #submitSearch() {
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
