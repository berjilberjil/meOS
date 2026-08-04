import Foundation

// Seed food library — Tamil-Nadu focused, mirrored from fitOS (emoji icons dropped;
// MyOS shows an SF Symbol per category). Each row's macros describe exactly one
// serving. Ids are stable ("seed-food-N"); custom foods override by id.
enum FoodSeed {
    static let all: [Food] = rows.enumerated().map { i, r in
        Food(id: "seed-food-\(i + 1)", name: r.0, category: r.1, servingLabel: r.2,
             perServing: Macros(calories: r.3, protein: r.4, carbs: r.5, fiber: r.6, fats: r.7),
             vitamins: vitaminsByName[r.0], isDefault: true)
    }

    /// Key micronutrients per food (informational only — shown in the dashboard).
    private static let vitaminsByName: [String: String] = [
        "Boiled egg": "B12, D", "Egg whites": "B2", "Chicken breast": "B6",
        "Fish (sardine)": "Omega-3, D", "Paneer": "Calcium", "Boiled channa": "Iron, Folate",
        "Soya chunks (dry)": "Iron", "Whey protein": "BCAA", "Moong sprouts": "Vit C, Folate",
        "Ragi ball": "Calcium, Iron", "Oats (dry)": "Fibre, Magnesium", "Sweet potato": "Vit A",
        "Sambar": "Folate", "Curd": "Calcium, Probiotic", "Toned milk": "Calcium, B12",
        "Buttermilk": "Calcium", "Banana": "B6, Potassium", "Apple": "Vit C, Fibre",
        "Dates": "Iron", "Almonds": "Vit E", "Peanuts": "Niacin", "Tender coconut": "Potassium",
    ]

    // name, category, serving, calories, protein, carbs, fiber, fats
    private static let rows: [(String, FoodCategory, String, Double, Double, Double, Double, Double)] = [
        // Protein
        ("Boiled egg", .protein, "1 egg", 78, 6.3, 0.6, 0, 5.3),
        ("Egg whites", .protein, "1 white", 17, 3.6, 0.2, 0, 0.1),
        ("Chicken breast", .protein, "100 g", 165, 31, 0, 0, 3.6),
        ("Fish (sardine)", .protein, "100 g", 208, 25, 0, 0, 11),
        ("Fish curry", .protein, "240 ml", 200, 18, 6, 1, 12),
        ("Chicken curry", .protein, "240 ml", 240, 20, 6, 1, 15),
        ("Paneer", .protein, "100 g", 265, 18, 1.2, 0, 21),
        ("Boiled channa", .protein, "160 g", 269, 15, 45, 12, 4),
        ("Moong sprouts", .protein, "100 g", 31, 3, 6, 2, 0.2),
        ("Soya chunks (dry)", .protein, "50 g", 172, 26, 16, 6, 0.5),
        ("Green gram pesarattu", .protein, "1 dosa", 150, 8, 20, 4, 4),
        ("Whey protein", .protein, "1 scoop", 120, 24, 3, 0, 1.5),
        // Carb / staples
        ("Idli", .carb, "1 idli", 58, 2, 12, 0.6, 0.3),
        ("Plain dosa", .carb, "1 dosa", 133, 2.7, 18, 1, 5.5),
        ("Egg dosa", .carb, "1 dosa", 200, 8, 18, 1, 11),
        ("Wheat dosa", .carb, "1 dosa", 120, 3, 20, 3, 3),
        ("Chapati", .carb, "1 chapati", 104, 3, 18, 2.7, 2.5),
        ("White rice", .carb, "160 g", 205, 4.3, 45, 0.6, 0.4),
        ("Brown rice", .carb, "195 g", 216, 5, 45, 3.5, 1.8),
        ("Curd rice", .carb, "200 g", 197, 6, 30, 1, 6),
        ("Ragi ball", .carb, "1 ball", 220, 5, 48, 8, 1.5),
        ("Oats (dry)", .carb, "40 g", 152, 5, 27, 4, 3),
        ("Upma", .carb, "200 g", 250, 6, 36, 3, 9),
        ("Poha", .carb, "180 g", 270, 5, 40, 2, 10),
        ("Ven pongal", .carb, "200 g", 285, 8, 40, 3, 10),
        ("Sweet potato", .carb, "1 medium", 112, 2, 26, 4, 0.1),
        // Dals / gravies / veg
        ("Sambar", .veg, "240 ml", 150, 6, 20, 5, 5),
        ("Rasam", .veg, "240 ml", 65, 2, 10, 2, 2),
        ("Thuvaram paruppu (dal)", .veg, "240 ml", 190, 12, 28, 8, 3),
        ("Kootu", .veg, "200 g", 160, 6, 18, 6, 7),
        // Dairy
        ("Curd", .dairy, "240 g", 110, 9, 12, 0, 4),
        ("Toned milk", .dairy, "240 ml", 120, 6, 11, 0, 5),
        ("Buttermilk", .dairy, "1 glass", 40, 3, 5, 0, 1),
        // Fruit / snacks
        ("Banana", .fruit, "1 medium", 105, 1.3, 27, 3, 0.4),
        ("Apple", .fruit, "1 medium", 95, 0.5, 25, 4, 0.3),
        ("Dates", .fruit, "2 dates", 133, 1, 36, 3, 0.2),
        ("Peanuts", .other, "30 g", 170, 7, 5, 2.5, 14),
        ("Almonds", .other, "10 nuts", 70, 2.5, 2.5, 1.5, 6),
        // Drinks
        ("Black coffee", .drink, "240 ml", 5, 0.3, 0, 0, 0),
        ("Tea with sugar", .drink, "240 ml", 90, 2, 15, 0, 3),
        ("Tender coconut", .drink, "1 whole", 46, 2, 9, 3, 0.5),
        // Junk
        ("Parotta", .junk, "1 parotta", 260, 5, 36, 1.5, 11),
        ("Chicken biryani", .junk, "1 plate", 550, 25, 65, 3, 22),
        ("Mutton biryani", .junk, "1 plate", 650, 28, 68, 3, 30),
        ("Medu vada", .junk, "1 vada", 130, 4, 15, 2, 6),
        ("Bajji", .junk, "1 piece", 100, 2, 12, 1, 5),
        ("Samosa", .junk, "1 piece", 130, 3, 15, 1.5, 7),
        ("Egg puff", .junk, "1 piece", 260, 7, 26, 1, 14),
        ("Chicken 65", .junk, "150 g", 290, 22, 12, 1, 18),
        ("French fries", .junk, "100 g", 312, 3.4, 41, 4, 15),
        ("Pizza slice", .junk, "1 slice", 285, 12, 36, 2.5, 10),
        ("Chicken burger", .junk, "1 burger", 350, 17, 39, 2, 14),
        ("Shawarma", .junk, "1 roll", 450, 24, 40, 3, 22),
        ("Panipuri", .junk, "6 pieces", 180, 4, 33, 2, 4),
        ("Gulab jamun", .junk, "2 pieces", 300, 4, 45, 0, 12),
        ("Soft drink", .junk, "330 ml", 139, 0, 35, 0, 0),
    ]
}
