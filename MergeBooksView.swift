import SwiftUI
import SwiftData

struct MergeBooksView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Book.title) private var books: [Book]

    @State private var selectedBook1: Book?
    @State private var selectedBook2: Book?
    @State private var keepSourceBook = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Select Books") {
                    Picker("First Book", selection: $selectedBook1) {
                        Text("None").tag(nil as Book?)
                        ForEach(books) { book in
                            Text(book.title).tag(book as Book?)
                        }
                    }
                    Picker("Second Book", selection: $selectedBook2) {
                        Text("None").tag(nil as Book?)
                        ForEach(books) { book in
                            Text(book.title).tag(book as Book?)
                        }
                    }
                }

                Section {
                    Toggle("Keep source books (otherwise delete them)", isOn: $keepSourceBook)
                }

                Button("Merge") {
                    merge()
                }
                .disabled(selectedBook1 == nil || selectedBook2 == nil || selectedBook1 == selectedBook2)
            }
            .navigationTitle("Merge Books")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func merge() {
        guard let book1 = selectedBook1, let book2 = selectedBook2 else { return }
        // Move all cards from book2 into book1, preserving order
        let cardsToMove = book2.cards.sorted { $0.sortOrder < $1.sortOrder }
        for card in cardsToMove {
            card.book = book1
            book1.cards.append(card)
        }
        if !keepSourceBook {
            modelContext.delete(book2)
        }
        try? modelContext.save()
        dismiss()
    }
}
