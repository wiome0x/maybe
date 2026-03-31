import { Controller } from "@hotwired/stimulus";

// Simple drag-and-drop sortable list using native HTML5 drag API
export default class extends Controller {
  static values = { url: String };
  static targets = ["item"];

  connect() {
    this.itemTargets.forEach((el) => {
      el.setAttribute("draggable", "true");
      el.addEventListener("dragstart", this.dragStart.bind(this));
      el.addEventListener("dragover", this.dragOver.bind(this));
      el.addEventListener("drop", this.drop.bind(this));
      el.addEventListener("dragend", this.dragEnd.bind(this));
    });
  }

  dragStart(e) {
    this.draggedEl = e.currentTarget;
    e.currentTarget.classList.add("opacity-50");
    e.dataTransfer.effectAllowed = "move";
  }

  dragOver(e) {
    e.preventDefault();
    e.dataTransfer.dropEffect = "move";

    const target = e.currentTarget;
    if (target === this.draggedEl) return;

    const rect = target.getBoundingClientRect();
    const midY = rect.top + rect.height / 2;

    if (e.clientY < midY) {
      target.parentNode.insertBefore(this.draggedEl, target);
    } else {
      target.parentNode.insertBefore(this.draggedEl, target.nextSibling);
    }
  }

  drop(e) {
    e.preventDefault();
    this.saveOrder();
  }

  dragEnd(e) {
    e.currentTarget.classList.remove("opacity-50");
  }

  saveOrder() {
    const ids = this.itemTargets.map((el) => el.dataset.itemId);
    const token = document.querySelector('meta[name="csrf-token"]')?.content;

    fetch(this.urlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": token,
        Accept: "application/json",
      },
      body: JSON.stringify({ item_ids: ids }),
    });
  }
}
