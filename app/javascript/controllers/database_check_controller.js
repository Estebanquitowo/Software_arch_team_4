import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["status", "results", "authorCount", "bookCount", "authors"]
  static values = { authorsUrl: String }

  connect() {
    this.loadAuthors()
  }

  async loadAuthors() {
    this.statusTarget.textContent = "Loading data..."
    this.resultsTarget.hidden = true

    try {
      const response = await fetch(this.authorsUrlValue, {
        headers: { Accept: "application/json" }
      })

      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      const authors = await response.json()
      if (!Array.isArray(authors)) throw new Error("Invalid API response")

      this.render(authors)
    } catch (error) {
      this.statusTarget.textContent = `Error loading data: ${error.message}`
    }
  }

  render(authors) {
    const booksCount = authors.reduce((total, author) => total + author.books.length, 0)

    this.authorCountTarget.textContent = authors.length
    this.bookCountTarget.textContent = booksCount
    this.authorsTarget.replaceChildren()
    this.resultsTarget.hidden = false

    if (authors.length === 0) {
      this.statusTarget.textContent = "Database is empty."
      return
    }

    this.statusTarget.textContent = ""

    authors.forEach((author) => {
      const section = document.createElement("section")
      const name = document.createElement("h2")
      name.textContent = author.name
      section.append(name)

      const books = document.createElement("ul")
      author.books.forEach((book) => {
        const item = document.createElement("li")
        item.textContent = book.title
        books.append(item)
      })

      if (author.books.length === 0) {
        const noBooks = document.createElement("p")
        noBooks.textContent = "No books"
        section.append(noBooks)
      } else {
        section.append(books)
      }

      this.authorsTarget.append(section)
    })
  }
}
