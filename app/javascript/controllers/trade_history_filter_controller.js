import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["button", "item", "empty"];

  filter(event) {
    const selectedKind = event.currentTarget.dataset.kind;
    let visibleCount = 0;

    this.itemTargets.forEach((item) => {
      const shouldDisplay = selectedKind === "all" || item.dataset.kind === selectedKind;
      item.classList.toggle("hidden", !shouldDisplay);

      if (shouldDisplay) {
        visibleCount += 1;
      }
    });

    this.buttonTargets.forEach((button) => {
      const isActive = button.dataset.kind === selectedKind;
      button.setAttribute("aria-pressed", isActive);
      button.classList.toggle("bg-container", isActive);
      button.classList.toggle("text-primary", isActive);
      button.classList.toggle("text-secondary", !isActive);
    });

    this.emptyTarget.classList.toggle("hidden", visibleCount > 0);
  }
}
