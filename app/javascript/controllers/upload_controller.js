import { Controller } from "@hotwired/stimulus"
import SparkMD5 from "spark-md5"

// Uploads the form's files before letting it submit, in parts when the server
// says the file is too big for one PUT. Emits the same direct-upload:* events
// @rails/activestorage does, so progress and header hooks are unchanged.
const CHECKSUM_SHARE = 10
const UPLOAD_SHARE = 80
const CHECKSUM_CHUNK = 2 * 1024 * 1024
const PART_CONCURRENCY = 4
const PARTS_PER_REQUEST = 100

let lastId = 0

export default class extends Controller {
  static targets = ["input"]

  async submit(event) {
    if (this.resubmitting) return

    const pending = this.inputTargets.flatMap((input) => Array.from(input.files).map((file) => ({ input, file })))
    if (pending.length === 0) return

    event.preventDefault()

    try {
      for (const { input, file } of pending) await this.upload(input, file)
      // Disabled rather than cleared, so the browser omits them from the
      // resubmit and `required` does not block it.
      this.inputTargets.forEach((input) => { input.disabled = true })
      this.resubmitting = true
      this.submitForm()
    } catch {
      this.resubmitting = false
    }
  }

  submitForm() {
    const button = this.element.querySelector("input[type=submit], button[type=submit]")
    if (!button) return this.element.requestSubmit()

    const disabled = button.disabled
    button.disabled = false
    button.click()
    button.disabled = disabled
  }

  async upload(input, file) {
    const id = ++lastId
    const hidden = this.insertHidden(input)
    this.emit(input, "start", { id, file })

    try {
      const checksum = await this.checksum(file, (share) => this.emit(input, "progress", { id, file, progress: share * CHECKSUM_SHARE }))
      const blob = await this.reserve(input, file, checksum, id)
      const onProgress = (share) => this.emit(input, "progress", { id, file, progress: CHECKSUM_SHARE + share * UPLOAD_SHARE })

      if (blob.multipart) await this.uploadParts(file, blob.multipart, onProgress)
      else await this.uploadWhole(input, file, blob, id, onProgress)

      hidden.value = blob.signed_id
      this.emit(input, "end", { id, file })
    } catch (error) {
      hidden.remove()
      const dispatched = this.emit(input, "error", { id, file, error: error.message })
      if (!dispatched.defaultPrevented) alert(error.message)
      this.emit(input, "end", { id, file })
      throw error
    }
  }

  async checksum(file, onProgress) {
    const spark = new SparkMD5.ArrayBuffer()
    for (let start = 0; start < file.size; start += CHECKSUM_CHUNK) {
      spark.append(await file.slice(start, start + CHECKSUM_CHUNK).arrayBuffer())
      onProgress(Math.min(start + CHECKSUM_CHUNK, file.size) / file.size)
    }
    return btoa(spark.end(true))
  }

  reserve(input, file, checksum, id) {
    return new Promise((resolve, reject) => {
      const xhr = new XMLHttpRequest()
      xhr.open("POST", input.dataset.uploadUrl, true)
      xhr.responseType = "json"
      xhr.setRequestHeader("Content-Type", "application/json")
      xhr.setRequestHeader("Accept", "application/json")
      xhr.setRequestHeader("X-CSRF-Token", this.csrfToken)
      xhr.addEventListener("load", () => {
        if (xhr.status >= 200 && xhr.status < 300) resolve(xhr.response)
        else reject(new Error(xhr.response?.error || `We couldn’t start uploading ${file.name}.`))
      })
      xhr.addEventListener("error", () => reject(new Error(`We couldn’t reach the server to upload ${file.name}.`)))
      this.emit(input, "before-blob-request", { id, file, xhr })
      xhr.send(JSON.stringify({
        blob: { filename: file.name, content_type: file.type || "application/octet-stream", byte_size: file.size, checksum }
      }))
    })
  }

  uploadWhole(input, file, blob, id, onProgress) {
    return new Promise((resolve, reject) => {
      const { url, headers } = blob.direct_upload
      const xhr = new XMLHttpRequest()
      xhr.open("PUT", url, true)
      xhr.responseType = "text"
      for (const key in headers) xhr.setRequestHeader(key, headers[key])
      xhr.upload.addEventListener("progress", (event) => {
        if (event.lengthComputable) onProgress(event.loaded / event.total)
      })
      xhr.addEventListener("load", () => {
        if (xhr.status >= 200 && xhr.status < 300) resolve()
        else reject(new Error(`We couldn’t store ${file.name}. Status: ${xhr.status}`))
      })
      xhr.addEventListener("error", () => reject(new Error(`We couldn’t store ${file.name}.`)))
      this.emit(input, "before-storage-request", { id, file, xhr })
      xhr.send(file.slice())
    })
  }

  async uploadParts(file, multipart, onProgress) {
    const { token, part_size: partSize, part_count: partCount } = multipart
    const etags = new Array(partCount)
    let sent = 0

    try {
      for (let from = 1; from <= partCount; from += PARTS_PER_REQUEST) {
        const numbers = []
        for (let number = from; number < Math.min(from + PARTS_PER_REQUEST, partCount + 1); number++) numbers.push(number)
        const parts = await this.presign(multipart.parts_url, token, numbers)

        await this.eachConcurrently(parts, PART_CONCURRENCY, async ({ part_number: number, url }) => {
          const start = (number - 1) * partSize
          const body = file.slice(start, Math.min(start + partSize, file.size))
          etags[number - 1] = await this.putPart(url, body, file)
          sent += body.size
          onProgress(sent / file.size)
        })
      }

      await this.post(multipart.complete_url, {
        token, parts: etags.map((etag, index) => ({ part_number: index + 1, etag }))
      })
    } catch (error) {
      await this.post(multipart.abort_url, { token }).catch(() => {})
      throw error
    }
  }

  putPart(url, body, file) {
    return new Promise((resolve, reject) => {
      const xhr = new XMLHttpRequest()
      xhr.open("PUT", url, true)
      xhr.addEventListener("load", () => {
        const etag = xhr.getResponseHeader("ETag")
        if (xhr.status < 200 || xhr.status >= 300) reject(new Error(`We couldn’t store part of ${file.name}. Status: ${xhr.status}`))
        else if (!etag) reject(new Error(`The storage bucket did not return an ETag. Its CORS rules need to expose that header.`))
        else resolve(etag)
      })
      xhr.addEventListener("error", () => reject(new Error(`We couldn’t store part of ${file.name}.`)))
      xhr.send(body)
    })
  }

  async presign(url, token, numbers) {
    const response = await this.post(url, { token, part_numbers: numbers })
    return response.parts
  }

  async post(url, body) {
    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": this.csrfToken },
      body: JSON.stringify(body)
    })
    if (!response.ok) {
      const details = await response.json().catch(() => ({}))
      throw new Error(details.error || `Upload failed. Status: ${response.status}`)
    }
    return response.status === 204 ? {} : response.json()
  }

  async eachConcurrently(items, limit, run) {
    const queue = [...items]
    const workers = Array.from({ length: Math.min(limit, queue.length) }, async () => {
      while (queue.length > 0) await run(queue.shift())
    })
    await Promise.all(workers)
  }

  insertHidden(input) {
    const hidden = document.createElement("input")
    hidden.type = "hidden"
    hidden.name = input.name
    input.insertAdjacentElement("beforebegin", hidden)
    return hidden
  }

  emit(input, name, detail) {
    const event = new CustomEvent(`direct-upload:${name}`, { detail, bubbles: true, cancelable: true })
    input.dispatchEvent(event)
    return event
  }

  get csrfToken() {
    return document.querySelector("meta[name=csrf-token]")?.content
  }
}
