import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="plaid"
export default class extends Controller {
  static values = {
    linkToken: String,
    region: { type: String, default: "us" },
    isUpdate: { type: Boolean, default: false },
    itemId: String,
  };

  connect() {
    this.open();
  }

  open() {
    const handler = Plaid.create({
      token: this.linkTokenValue,
      onSuccess: this.handleSuccess,
      onLoad: this.handleLoad,
      onExit: this.handleExit,
      onEvent: this.handleEvent,
    });

    handler.open();
  }

  handleSuccess = (public_token, metadata) => {
    const institution = metadata?.institution?.name || "unknown";
    console.info(`[Plaid] onSuccess | institution=${institution} region=${this.regionValue} isUpdate=${this.isUpdateValue}`);

    if (this.isUpdateValue) {
      console.info(`[Plaid] Update mode — triggering sync for item=${this.itemIdValue}`);
      // Trigger a sync to verify the connection and update status
      fetch(`/plaid_items/${this.itemIdValue}/sync`, {
        method: "POST",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('[name="csrf-token"]').content,
        },
      }).then(() => {
        window.location.href = "/accounts";
      });
      return;
    }

    console.info(`[Plaid] New connection — creating PlaidItem | institution=${institution}`);
    // For new connections, create a new Plaid item
    fetch("/plaid_items", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('[name="csrf-token"]').content,
      },
      body: JSON.stringify({
        plaid_item: {
          public_token: public_token,
          metadata: metadata,
          region: this.regionValue,
        },
      }),
    }).then((response) => {
      if (response.redirected) {
        window.location.href = response.url;
      }
    });
  };

  handleExit = (err, metadata) => {
    if (err) {
      console.warn(`[Plaid] onExit with error | error_type=${err.error_type} error_code=${err.error_code} message=${err.error_message} status=${metadata?.status}`);
    } else {
      console.info(`[Plaid] onExit (user closed) | status=${metadata?.status} institution=${metadata?.institution?.name}`);
    }

    // If there was an error during update mode, refresh the page to show latest status
    if (err && metadata.status === "requires_credentials") {
      window.location.href = "/accounts";
    }
  };

  handleEvent = (eventName, metadata) => {
    console.info(`[Plaid] onEvent | event=${eventName} institution=${metadata?.institution_name} view=${metadata?.view_name} error=${metadata?.error_code || "none"}`);
  };

  handleLoad = () => {
    console.info("[Plaid] Link loaded successfully");
  };
}
