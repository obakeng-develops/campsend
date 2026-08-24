import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source", "button"]

  copy() {
    navigator.clipboard.writeText(this.sourceTarget.textContent.trim()).then(
      () => this.confirm("Copied"),
      () => this.confirm("Press ⌘C")
    )
  }

  confirm(message) {
    clearTimeout(this.timeout)
    this.buttonTarget.textContent = message
    this.timeout = setTimeout(() => { this.buttonTarget.textContent = "Copy" }, 1600)
  }

  disconnect() {
    clearTimeout(this.timeout)
  }
}
