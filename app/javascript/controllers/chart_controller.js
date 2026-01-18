import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    type: { type: String, default: 'bar' },
    data: Object
  }

  connect() {
    const isLine = this.typeValue === 'line'

    this.chart = new Chart(this.element, {
      type: this.typeValue,
      data: this.dataValue,
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          x: { stacked: !isLine },
          y: {
            stacked: !isLine,
            ticks: {
              callback: (value) => '₩' + value.toLocaleString()
            }
          }
        },
        plugins: {
          tooltip: {
            callbacks: {
              label: (context) => `${context.dataset.label}: ₩${context.raw.toLocaleString()}`
            }
          },
          legend: {
            position: 'bottom',
            labels: {
              boxWidth: 12,
              padding: 15
            }
          }
        },
        elements: isLine ? {
          line: {
            tension: 0.3
          },
          point: {
            radius: 4,
            hoverRadius: 6
          }
        } : {}
      }
    })
  }

  disconnect() {
    if (this.chart) {
      this.chart.destroy()
    }
  }
}
