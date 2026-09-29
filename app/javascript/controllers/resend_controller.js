import { Controller } from "@hotwired/stimulus"

// Holds the resend button for a minute and counts it down, so the first thing
// a waiting person does is look in their inbox rather than ask again.
export default class extends Controller {
  static targets = ["button"]
  static values = { seconds: { type: Number, default: 60 } }

  connect() {
    this.label = this.buttonTarget.textContent.trim()
    this.remaining = this.secondsValue
    this.tick()
    this.timer = setInterval(() => this.tick(), 1000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  tick() {
    if (this.remaining <= 0) {
      clearInterval(this.timer)
      this.buttonTarget.disabled = false
      this.buttonTarget.textContent = this.label
      return
    }
    this.buttonTarget.disabled = true
    this.buttonTarget.textContent = `${this.label} (0:${String(this.remaining).padStart(2, "0")})`
    this.remaining -= 1
  }
}
