/**
 * DragCopyManager - Reusable drag-and-drop value copying utility
 *
 * Usage:
 *   import DragCopyManager from "utils/drag_copy_manager"
 *
 *   // In your Stimulus controller
 *   connect() {
 *     this.dragManager = new DragCopyManager({
 *       // Define field type compatibility (which types can drop onto which)
 *       compatibility: {
 *         text: ["text"],           // text can drop on text
 *         select: ["select"],       // select can drop on same select only (checked by fieldKey)
 *       },
 *       // Whether same fieldKey is required for compatibility (for select types)
 *       requireSameFieldKey: ["select"],
 *       // CSS classes for visual feedback
 *       classes: {
 *         dragging: "opacity-50",
 *         dropTarget: ["ring-2", "ring-indigo-400", "bg-indigo-50"]
 *       },
 *       // Callback when drop is successful
 *       onDrop: async (sourceData, targetData) => {
 *         // Save to server, update UI, etc.
 *       }
 *     })
 *   }
 *
 *   // Make an element draggable
 *   this.dragManager.makeDraggable(element, {
 *     fieldKey: "merchant",
 *     fieldType: "text",
 *     side: "left",
 *     value: "Starbucks",
 *     context: { txId: 123 }  // Any additional data
 *   })
 *
 *   // Make an element a drop target
 *   this.dragManager.makeDropTarget(element, {
 *     fieldKey: "description",
 *     fieldType: "text",
 *     side: "right",
 *     context: { txId: 456 }
 *   })
 */

export default class DragCopyManager {
  constructor(options = {}) {
    this.compatibility = options.compatibility || { text: ["text"] }
    this.requireSameFieldKey = options.requireSameFieldKey || []
    this.classes = {
      dragging: options.classes?.dragging || "opacity-50",
      dropTarget: options.classes?.dropTarget || ["ring-2", "ring-indigo-400", "bg-indigo-50"]
    }
    this.onDrop = options.onDrop || (() => {})
    this.blockSameSide = options.blockSameSide !== false // Default true

    this.dragData = null
    this.elements = new Set()
  }

  /**
   * Make an element draggable
   * @param {HTMLElement} element
   * @param {Object} data - { fieldKey, fieldType, side, value, context }
   */
  makeDraggable(element, data) {
    element.draggable = true
    element.dataset.dragFieldKey = data.fieldKey
    element.dataset.dragFieldType = data.fieldType
    element.dataset.dragSide = data.side

    const handlers = {
      dragstart: (e) => this.handleDragStart(e, data),
      dragend: (e) => this.handleDragEnd(e)
    }

    element.addEventListener("dragstart", handlers.dragstart)
    element.addEventListener("dragend", handlers.dragend)

    // Store for cleanup
    element._dragHandlers = handlers
    this.elements.add(element)

    return this
  }

  /**
   * Make an element a drop target
   * @param {HTMLElement} element
   * @param {Object} data - { fieldKey, fieldType, side, context }
   */
  makeDropTarget(element, data) {
    element.dataset.dropFieldKey = data.fieldKey
    element.dataset.dropFieldType = data.fieldType
    element.dataset.dropSide = data.side

    const handlers = {
      dragover: (e) => this.handleDragOver(e, data),
      dragenter: (e) => this.handleDragEnter(e, data),
      dragleave: (e) => this.handleDragLeave(e),
      drop: (e) => this.handleDrop(e, data)
    }

    element.addEventListener("dragover", handlers.dragover)
    element.addEventListener("dragenter", handlers.dragenter)
    element.addEventListener("dragleave", handlers.dragleave)
    element.addEventListener("drop", handlers.drop)

    // Store for cleanup
    element._dropHandlers = handlers
    this.elements.add(element)

    return this
  }

  /**
   * Make an element both draggable and a drop target
   * @param {HTMLElement} element
   * @param {Object} data - { fieldKey, fieldType, side, value, context }
   */
  makeDraggableDropTarget(element, data) {
    this.makeDraggable(element, data)
    this.makeDropTarget(element, data)
    return this
  }

  /**
   * Check if source can be dropped on target
   */
  isCompatible(sourceData, targetData) {
    // Block same side if configured
    if (this.blockSameSide && sourceData.side === targetData.side) {
      return false
    }

    const sourceType = sourceData.fieldType
    const targetType = targetData.fieldType

    // Check type compatibility
    const compatibleTypes = this.compatibility[sourceType] || []
    if (!compatibleTypes.includes(targetType)) {
      return false
    }

    // Check if same fieldKey is required for this type
    if (this.requireSameFieldKey.includes(sourceType)) {
      if (sourceData.fieldKey !== targetData.fieldKey) {
        return false
      }
    }

    return true
  }

  handleDragStart(e, data) {
    this.dragData = { ...data }
    e.dataTransfer.setData("application/json", JSON.stringify(data))
    e.dataTransfer.effectAllowed = "copy"

    const classes = Array.isArray(this.classes.dragging)
      ? this.classes.dragging
      : [this.classes.dragging]
    e.target.classList.add(...classes)
  }

  handleDragEnd(e) {
    const classes = Array.isArray(this.classes.dragging)
      ? this.classes.dragging
      : [this.classes.dragging]
    e.target.classList.remove(...classes)
    this.dragData = null
  }

  handleDragOver(e, targetData) {
    if (!this.dragData) return

    if (this.isCompatible(this.dragData, targetData)) {
      e.preventDefault()
      e.dataTransfer.dropEffect = "copy"
    }
  }

  handleDragEnter(e, targetData) {
    if (!this.dragData) return

    if (this.isCompatible(this.dragData, targetData)) {
      const classes = Array.isArray(this.classes.dropTarget)
        ? this.classes.dropTarget
        : [this.classes.dropTarget]
      e.target.classList.add(...classes)
    }
  }

  handleDragLeave(e) {
    const classes = Array.isArray(this.classes.dropTarget)
      ? this.classes.dropTarget
      : [this.classes.dropTarget]
    e.target.classList.remove(...classes)
  }

  async handleDrop(e, targetData) {
    e.preventDefault()

    const classes = Array.isArray(this.classes.dropTarget)
      ? this.classes.dropTarget
      : [this.classes.dropTarget]
    e.target.classList.remove(...classes)

    try {
      const sourceData = JSON.parse(e.dataTransfer.getData("application/json"))

      if (!this.isCompatible(sourceData, targetData)) {
        return
      }

      await this.onDrop(sourceData, targetData, e.target)
    } catch (error) {
      console.error("DragCopyManager: Error handling drop", error)
    }
  }

  /**
   * Remove all event listeners and cleanup
   */
  destroy() {
    this.elements.forEach(element => {
      if (element._dragHandlers) {
        element.removeEventListener("dragstart", element._dragHandlers.dragstart)
        element.removeEventListener("dragend", element._dragHandlers.dragend)
        delete element._dragHandlers
      }
      if (element._dropHandlers) {
        element.removeEventListener("dragover", element._dropHandlers.dragover)
        element.removeEventListener("dragenter", element._dropHandlers.dragenter)
        element.removeEventListener("dragleave", element._dropHandlers.dragleave)
        element.removeEventListener("drop", element._dropHandlers.drop)
        delete element._dropHandlers
      }
    })
    this.elements.clear()
    this.dragData = null
  }
}
