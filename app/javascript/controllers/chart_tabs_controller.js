import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "integratedView", "trendView", "sparklineContainer"]
  static values = {
    data: Object
  }

  connect() {
    this.sparklineCharts = []
    this.showIntegratedView() // Default to integrated view
  }

  disconnect() {
    this.destroySparklines()
  }

  switchTab(event) {
    const tab = event.currentTarget
    const view = tab.dataset.view

    // Update tab styles
    this.tabTargets.forEach(t => {
      if (t === tab) {
        t.classList.remove('text-gray-500', 'hover:text-gray-700', 'border-transparent')
        t.classList.add('text-indigo-600', 'border-indigo-600')
      } else {
        t.classList.remove('text-indigo-600', 'border-indigo-600')
        t.classList.add('text-gray-500', 'hover:text-gray-700', 'border-transparent')
      }
    })

    // Show appropriate view
    if (view === 'integrated') {
      this.showIntegratedView()
    } else if (view === 'trend') {
      this.showTrendView()
    }
  }

  showIntegratedView() {
    this.integratedViewTarget.classList.remove('hidden')
    this.trendViewTarget.classList.add('hidden')
  }

  showTrendView() {
    this.integratedViewTarget.classList.add('hidden')
    this.trendViewTarget.classList.remove('hidden')

    // Lazy load sparklines when first shown
    if (this.sparklineCharts.length === 0) {
      this.initializeSparklines()
    }
  }

  initializeSparklines() {
    // Sort datasets by total spending (highest first)
    const sortedDatasets = [...this.dataValue.datasets].sort((a, b) => {
      const sumA = a.data.reduce((acc, val) => acc + val, 0)
      const sumB = b.data.reduce((acc, val) => acc + val, 0)
      return sumB - sumA
    })

    // Create sparkline for each category
    sortedDatasets.forEach(dataset => {
      const total = dataset.data.reduce((acc, val) => acc + val, 0)

      // Create container
      const container = document.createElement('div')
      container.className = 'bg-white rounded-lg shadow p-4'

      // Category header
      const header = document.createElement('div')
      header.className = 'flex items-center justify-between mb-3'

      const leftDiv = document.createElement('div')
      leftDiv.className = 'flex items-center space-x-2'

      const colorDot = document.createElement('div')
      colorDot.className = 'w-3 h-3 rounded-full'
      colorDot.style.backgroundColor = dataset.borderColor

      const categoryName = document.createElement('span')
      categoryName.className = 'font-semibold text-gray-900'
      categoryName.textContent = dataset.label

      leftDiv.appendChild(colorDot)
      leftDiv.appendChild(categoryName)

      const amountSpan = document.createElement('span')
      amountSpan.className = 'text-lg font-bold text-gray-900'
      amountSpan.textContent = `₩${total.toLocaleString()}`

      header.appendChild(leftDiv)
      header.appendChild(amountSpan)
      container.appendChild(header)

      // Canvas wrapper with fixed height
      const canvasWrapper = document.createElement('div')
      canvasWrapper.style.height = '60px'
      canvasWrapper.style.position = 'relative'

      const canvas = document.createElement('canvas')
      canvasWrapper.appendChild(canvas)
      container.appendChild(canvasWrapper)

      // Add to DOM
      this.sparklineContainerTarget.appendChild(container)

      // Create sparkline chart
      const chart = new Chart(canvas, {
        type: 'line',
        data: {
          labels: this.dataValue.labels,
          datasets: [{
            data: dataset.data,
            borderColor: dataset.borderColor,
            backgroundColor: `${dataset.borderColor}20`,
            fill: true,
            tension: 0.3,
            borderWidth: 2,
            pointRadius: 0,
            pointHoverRadius: 4,
            pointHoverBackgroundColor: dataset.borderColor,
            pointHoverBorderColor: '#fff',
            pointHoverBorderWidth: 2
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          interaction: {
            intersect: false,
            mode: 'index'
          },
          scales: {
            x: {
              display: false
            },
            y: {
              display: false,
              beginAtZero: true
            }
          },
          plugins: {
            legend: {
              display: false
            },
            tooltip: {
              enabled: true,
              displayColors: false,
              callbacks: {
                title: (items) => items[0].label,
                label: (context) => `₩${context.raw.toLocaleString()}`
              }
            }
          }
        }
      })

      this.sparklineCharts.push(chart)
    })
  }

  destroySparklines() {
    this.sparklineCharts.forEach(chart => chart.destroy())
    this.sparklineCharts = []
    if (this.hasSparklineContainerTarget) {
      this.sparklineContainerTarget.innerHTML = ''
    }
  }
}
