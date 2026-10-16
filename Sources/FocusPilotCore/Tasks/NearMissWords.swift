/// Real English and Spanish words and names that are within a typo of a date
/// name, so they are never taken for a misspelled date. Checked before the
/// system spelling checker, which may lack a Spanish dictionary.
enum NearMissWords {
    static func contains(_ word: String) -> Bool {
        words.contains(word.lowercased())
    }

    private static let words: Set<String> = [
        // English
        "match", "marsh", "marks", "money", "monkey", "moody", "fridge", "frida", "total", "lunch",
        "sundae", "sunny", "banana", "domino", "tonights",
        // Spanish
        "marco", "marcos", "marca", "marcha", "marte", "martas", "lunas", "huevos", "salado", "sabana",
        "sábana", "dominó", "todas", "todos", "pesado", "pasada", "posado", "manzana",
        // Names
        "martha", "marta", "mario", "maria", "maría", "marcy", "martin", "martín", "domingo", "fryda",
    ]
}
