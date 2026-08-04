import Foundation

// Seed exercise library, mirrored from fitOS (emoji icons dropped). `gifId` is the
// ExerciseDB open-mirror demo id (shown in-app); `muscles` are anatomy slugs the
// body map highlights. Ids are stable ("seed-ex-N"); custom exercises override by id.
enum ExerciseSeed {
    static let all: [Exercise] = rows.enumerated().map { i, r in
        Exercise(id: "seed-ex-\(i + 1)", name: r.0, category: r.1, equipment: r.2,
                 primary: r.3, muscles: r.4, gifId: r.5, weighted: r.6, isDefault: true)
    }

    // name, category, equipment, primary, muscles(slugs), gifId, weighted
    private static let rows: [(String, WorkoutCategory, String, String, [String], String?, Bool)] = [
        // Chest
        ("Barbell bench press", .chest, "Barbell", "Mid chest", ["chest", "triceps", "deltoids"], "EIeI8Vf", true),
        ("Incline dumbbell press", .chest, "Dumbbell", "Upper chest", ["chest", "deltoids", "triceps"], "PG1kcIb", true),
        ("Machine chest press", .chest, "Machine", "Chest", ["chest", "triceps"], "WbNq5Xu", true),
        ("Cable crossover", .chest, "Cable", "Inner chest", ["chest"], "0CXGHya", true),
        ("Pec deck fly", .chest, "Machine", "Chest", ["chest"], "tBWXbIT", true),
        ("Chest dip", .chest, "Bodyweight", "Lower chest", ["chest", "triceps"], "9WTm7dq", true),
        ("Push-up", .chest, "Bodyweight", "Chest", ["chest", "triceps", "abs"], "4Jt8QsQ", false),
        ("Incline barbell press", .chest, "Barbell", "Upper chest", ["chest", "deltoids"], "3TZduzM", true),
        ("Dumbbell fly", .chest, "Dumbbell", "Chest", ["chest"], "ESOd5Pl", true),
        // Back
        ("Deadlift", .back, "Barbell", "Whole back", ["lower-back", "hamstring", "gluteal", "trapezius"], "ila4NZS", true),
        ("Pull-up", .back, "Bodyweight", "Lats", ["upper-back", "biceps"], "0V2YQjW", false),
        ("Lat pulldown", .back, "Cable", "Lats", ["upper-back", "biceps"], "4IKbhHV", true),
        ("Barbell row", .back, "Barbell", "Mid back", ["upper-back", "biceps"], "eZyBC3j", true),
        ("Seated cable row", .back, "Cable", "Mid back", ["upper-back", "biceps"], "fUBheHs", true),
        ("One-arm dumbbell row", .back, "Dumbbell", "Lats", ["upper-back", "biceps"], "BJ0Hz5L", true),
        ("Face pull", .back, "Cable", "Rear delts", ["deltoids", "upper-back"], "wqNPGCg", true),
        ("T-bar row", .back, "Barbell", "Mid back", ["upper-back", "biceps"], "aaXr7ld", true),
        ("Chin-up", .back, "Bodyweight", "Lats / biceps", ["upper-back", "biceps"], "T2mxWqc", false),
        ("Back extension", .back, "Bodyweight", "Lower back", ["lower-back", "gluteal"], "rUXfn3R", false),
        // Shoulders
        ("Overhead press", .shoulders, "Barbell", "Front delts", ["deltoids", "triceps"], "kTbSH9h", true),
        ("Dumbbell shoulder press", .shoulders, "Dumbbell", "Shoulders", ["deltoids", "triceps"], "znQUdHY", true),
        ("Lateral raise", .shoulders, "Dumbbell", "Side delts", ["deltoids"], "DsgkuIt", true),
        ("Front raise", .shoulders, "Dumbbell", "Front delts", ["deltoids"], "3eGE2JC", true),
        ("Reverse pec deck", .shoulders, "Machine", "Rear delts", ["deltoids", "upper-back"], "aqvSOQE", true),
        ("Barbell shrug", .shoulders, "Barbell", "Traps", ["trapezius"], "dG7tG5y", true),
        ("Arnold press", .shoulders, "Dumbbell", "Shoulders", ["deltoids", "triceps"], "Xy4jlWA", true),
        ("Upright row", .shoulders, "Barbell", "Side delts / traps", ["deltoids", "trapezius"], "UDlhcO8", true),
        // Arms
        ("Barbell curl", .arms, "Barbell", "Biceps", ["biceps"], "25GPyDY", true),
        ("Dumbbell curl", .arms, "Dumbbell", "Biceps", ["biceps"], "NbVPDMW", true),
        ("Hammer curl", .arms, "Dumbbell", "Brachialis", ["biceps", "forearm"], "2NpxjC1", true),
        ("Preacher curl", .arms, "Machine", "Biceps", ["biceps"], "jivWf8n", true),
        ("Triceps pushdown", .arms, "Cable", "Triceps", ["triceps"], "gAwDzB3", true),
        ("Overhead triceps extension", .arms, "Dumbbell", "Triceps", ["triceps"], "2IxROQ1", true),
        ("Close-grip bench press", .arms, "Barbell", "Triceps", ["triceps", "chest"], "J6Dx1Mu", true),
        ("Skull crusher", .arms, "Barbell", "Triceps", ["triceps"], "h8LFzo9", true),
        ("EZ-bar curl", .arms, "Barbell", "Biceps", ["biceps"], "6TG6x2w", true),
        ("Bench dip", .arms, "Bodyweight", "Triceps", ["triceps"], "9RT8oQW", false),
        // Legs
        ("Barbell squat", .legs, "Barbell", "Quads", ["quadriceps", "gluteal"], "qXTaZnJ", true),
        ("Leg press", .legs, "Machine", "Quads", ["quadriceps", "gluteal"], "2Qh2J1e", true),
        ("Romanian deadlift", .legs, "Barbell", "Hamstrings", ["hamstring", "gluteal"], "wQ2c4XD", true),
        ("Leg extension", .legs, "Machine", "Quads", ["quadriceps"], "my33uHU", true),
        ("Lying leg curl", .legs, "Machine", "Hamstrings", ["hamstring"], "17lJ1kr", true),
        ("Walking lunge", .legs, "Dumbbell", "Quads / glutes", ["quadriceps", "gluteal", "hamstring"], "IZVHb27", true),
        ("Bulgarian split squat", .legs, "Dumbbell", "Quads / glutes", ["quadriceps", "gluteal"], "qx4fgX7", true),
        ("Hip thrust", .legs, "Barbell", "Glutes", ["gluteal", "hamstring"], "Pjbc0Kt", true),
        ("Standing calf raise", .legs, "Machine", "Calves", ["calves"], "ykUOVze", true),
        ("Front squat", .legs, "Barbell", "Quads", ["quadriceps", "gluteal"], "zG0zs85", true),
        ("Goblet squat", .legs, "Dumbbell", "Quads", ["quadriceps", "gluteal"], "yn8yg1r", true),
        // Core
        ("Plank", .core, "Bodyweight", "Whole core", ["abs", "obliques", "lower-back"], "hCjGsRQ", false),
        ("Hanging leg raise", .core, "Bodyweight", "Lower abs", ["abs"], "I3tsCnC", false),
        ("Cable crunch", .core, "Cable", "Abs", ["abs"], "WW95auq", true),
        ("Russian twist", .core, "Bodyweight", "Obliques", ["obliques", "abs"], "XVDdcoj", false),
        ("Crunch", .core, "Bodyweight", "Abs", ["abs"], "kjJ3VoQ", false),
        ("Bicycle crunch", .core, "Bodyweight", "Abs / obliques", ["abs", "obliques"], "tZkGYZ9", false),
        ("Mountain climber", .core, "Bodyweight", "Whole core", ["abs", "obliques"], "RJgzwny", false),
        // Cardio
        ("Treadmill run", .cardio, "Cardio", "Heart / legs", ["quadriceps", "calves"], "CcWEoWV", false),
        ("Incline walk", .cardio, "Cardio", "Heart", ["quadriceps", "calves"], "rjtuP6X", false),
        ("Cycling", .cardio, "Cardio", "Legs", ["quadriceps", "calves"], "H1PESYI", false),
        ("Rowing machine", .cardio, "Cardio", "Full body", ["upper-back", "quadriceps"], "IGjKj1v", false),
        ("Burpee", .cardio, "Bodyweight", "Full body", ["quadriceps", "chest", "abs"], "dK9394r", false),
        ("Jump rope", .cardio, "Cardio", "Heart / calves", ["calves"], nil, false),
        // Boxing (heavy bag)
        ("Jab", .boxing, "Bag", "Shoulders / core", ["deltoids", "obliques"], nil, false),
        ("Cross", .boxing, "Bag", "Shoulders / core", ["deltoids", "obliques", "abs"], nil, false),
        ("Hook", .boxing, "Bag", "Shoulders / obliques", ["deltoids", "obliques"], "hoXt6wv", false),
        ("Uppercut", .boxing, "Bag", "Arms / core", ["biceps", "abs"], nil, false),
        ("Heavy bag round", .boxing, "Bag", "Full body / cardio", ["deltoids", "obliques", "abs"], nil, false),
    ]
}
