import { Controller } from "@hotwired/stimulus"

const IMAGE_EXTENSIONS = [".jpg", ".jpeg", ".png", ".webp", ".heic"]
const IMAGE_MIME_TYPES = ["image/jpeg", "image/png", "image/webp", "image/heic"]

export default class extends Controller {
  static targets = ["fileInput", "fileName", "institutionSelector", "dropZone", "fileCount", "clearButton"]

  connect() {
    this.handlePaste = this.paste.bind(this)
    document.addEventListener("paste", this.handlePaste)
  }

  disconnect() {
    document.removeEventListener("paste", this.handlePaste)
  }

  detect() {
    const files = this.fileInputTarget.files
    if (!files || files.length === 0) return

    this.updateUI(files)
  }

  paste(event) {
    const items = event.clipboardData?.items
    if (!items) return

    for (const item of items) {
      if (IMAGE_MIME_TYPES.includes(item.type)) {
        event.preventDefault()
        const file = item.getAsFile()
        if (!file) continue

        const extension = file.type.split("/")[1] === "jpeg" ? "jpg" : file.type.split("/")[1]
        const timestamp = new Date().toISOString().slice(0, 19).replace(/[-:T]/g, "")
        const newFile = new File([file], `clipboard_${timestamp}.${extension}`, { type: file.type })

        const dataTransfer = new DataTransfer()
        // Preserve existing files
        for (const existingFile of this.fileInputTarget.files) {
          dataTransfer.items.add(existingFile)
        }
        dataTransfer.items.add(newFile)
        this.fileInputTarget.files = dataTransfer.files

        this.updateUI(dataTransfer.files)
        break
      }
    }
  }

  dragover(event) {
    event.preventDefault()
    this.dropZoneTarget.classList.add("border-indigo-500", "bg-indigo-50")
  }

  dragleave(event) {
    event.preventDefault()
    this.dropZoneTarget.classList.remove("border-indigo-500", "bg-indigo-50")
  }

  drop(event) {
    event.preventDefault()
    this.dropZoneTarget.classList.remove("border-indigo-500", "bg-indigo-50")

    const droppedFiles = event.dataTransfer?.files
    if (!droppedFiles || droppedFiles.length === 0) return

    const dataTransfer = new DataTransfer()
    // Preserve existing files
    for (const existingFile of this.fileInputTarget.files) {
      dataTransfer.items.add(existingFile)
    }
    // Add dropped files
    for (const file of droppedFiles) {
      dataTransfer.items.add(file)
    }
    this.fileInputTarget.files = dataTransfer.files

    this.updateUI(dataTransfer.files)
  }

  clearFiles(event) {
    event.preventDefault()
    event.stopPropagation()

    const dataTransfer = new DataTransfer()
    this.fileInputTarget.files = dataTransfer.files

    this.fileNameTarget.textContent = "파일을 선택하거나 여기에 놓으세요"
    this.fileNameTarget.title = ""
    this.institutionSelectorTarget.classList.add("hidden")

    if (this.hasFileCountTarget) {
      this.fileCountTarget.classList.add("hidden")
    }
    if (this.hasClearButtonTarget) {
      this.clearButtonTarget.classList.add("hidden")
    }
  }

  updateUI(files) {
    const fileCount = files.length

    if (fileCount === 0) {
      this.fileNameTarget.textContent = "파일을 선택하거나 여기에 놓으세요"
      this.fileNameTarget.title = ""
      this.institutionSelectorTarget.classList.add("hidden")
      if (this.hasFileCountTarget) {
        this.fileCountTarget.classList.add("hidden")
      }
      if (this.hasClearButtonTarget) {
        this.clearButtonTarget.classList.add("hidden")
      }
      return
    }

    // Show clear button when files are selected
    if (this.hasClearButtonTarget) {
      this.clearButtonTarget.classList.remove("hidden")
    }

    // Update file name display
    if (fileCount === 1) {
      this.fileNameTarget.textContent = decodeURIComponent(files[0].name)
      this.fileNameTarget.title = decodeURIComponent(files[0].name)
    } else {
      const names = Array.from(files).map(f => decodeURIComponent(f.name)).join(", ")
      this.fileNameTarget.textContent = `${fileCount}개 파일 선택됨`
      this.fileNameTarget.title = names
    }

    // Show file count badge
    if (this.hasFileCountTarget) {
      if (fileCount > 1) {
        this.fileCountTarget.textContent = `${fileCount}개`
        this.fileCountTarget.classList.remove("hidden")
      } else {
        this.fileCountTarget.classList.add("hidden")
      }
    }

    // Check if any file is an image
    let hasImage = false
    for (const file of files) {
      const ext = "." + file.name.split(".").pop().toLowerCase()
      if (IMAGE_EXTENSIONS.includes(ext) || IMAGE_MIME_TYPES.includes(file.type)) {
        hasImage = true
        break
      }
    }

    if (hasImage) {
      this.institutionSelectorTarget.classList.remove("hidden")
    } else {
      this.institutionSelectorTarget.classList.add("hidden")
    }
  }
}
