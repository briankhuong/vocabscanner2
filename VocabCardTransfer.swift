import Foundation

/// Codable representation of a VocabCard for export/import
struct VocabCardExport: Codable {
    var word: String
    var pronunciation: String?
    var definition: String?
    var dictionaryExample: String?
    var contextSentence: String
    var translation: String
    var easeFactor: Double
    var interval: Int
    var repetitions: Int
    var nextReviewDate: Date

    init(from card: VocabCard) {
        self.word = card.word
        self.pronunciation = card.pronunciation
        self.definition = card.definition
        self.dictionaryExample = card.dictionaryExample
        self.contextSentence = card.contextSentence
        self.translation = card.translation
        self.easeFactor = card.easeFactor
        self.interval = card.interval
        self.repetitions = card.repetitions
        self.nextReviewDate = card.nextReviewDate
    }

    func toVocabCard() -> VocabCard {
        let card = VocabCard(
            word: word,
            contextSentence: contextSentence,
            translation: translation,
            pronunciation: pronunciation ?? "",
            definition: definition ?? "",
            dictionaryExample: dictionaryExample
        )
        card.easeFactor = easeFactor
        card.interval = interval
        card.repetitions = repetitions
        card.nextReviewDate = nextReviewDate
        return card
    }
}

struct BookExport: Codable {
    var title: String
    var author: String
    var cards: [VocabCardExport]
}
