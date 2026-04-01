import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "fileName", "uploadArea", "uploadText"]

  connect() {
    if (this.hasInputTarget) {
      this.inputTarget.addEventListener("change", this.fileSelected.bind(this))
    }
    
    // Find the form element
    this.form = this.element.closest("form")
    if (this.form) {
      this.form.addEventListener("turbo:submit-start", this.formSubmitting.bind(this))
    }
  }

  disconnect() {
    if (this.hasInputTarget) {
      this.inputTarget.removeEventListener("change", this.fileSelected.bind(this))
    }
    
    if (this.form) {
      this.form.removeEventListener("turbo:submit-start", this.formSubmitting.bind(this))
    }
  }

  triggerFileInput() {
    if (this.hasInputTarget) {
      this.inputTarget.click()
    }
  }

  fileSelected() {
    if (this.hasInputTarget && this.inputTarget.files.length > 0) {
      const file = this.inputTarget.files[0];

      // Reject files larger than 10MB
      const maxSize = 10 * 1024 * 1024;
      if (file.size > maxSize) {
        const sizeMB = (file.size / (1024 * 1024)).toFixed(1);
        alert(`File is too large (${sizeMB}MB). Maximum allowed size is 10MB.`);
        this.inputTarget.value = "";
        return;
      }

      if (this.hasFileNameTarget) {
        const fileNameText = this.fileNameTarget.querySelector("p");
        if (fileNameText) {
          fileNameText.textContent = file.name;
        }
        this.fileNameTarget.classList.remove("hidden");
      }

      if (this.hasUploadTextTarget) {
        this.uploadTextTarget.classList.add("hidden");
      }
    }
  }
  
  formSubmitting() {
    if (this.hasFileNameTarget && this.hasInputTarget && this.inputTarget.files.length > 0) {
      const fileNameText = this.fileNameTarget.querySelector("p");
      if (fileNameText) {
        fileNameText.textContent = `Uploading ${this.inputTarget.files[0].name}...`;
      }

      const iconContainer = this.fileNameTarget.querySelector(".lucide-file-text");
      if (iconContainer) {
        iconContainer.classList.add("animate-pulse");
      }
    }

    if (this.hasUploadAreaTarget) {
      this.uploadAreaTarget.classList.add("opacity-70");
    }
  }
} 