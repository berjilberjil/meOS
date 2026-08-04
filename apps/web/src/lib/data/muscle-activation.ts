// For each anatomy muscle group, the exercises that hit it hardest, ranked by
// relative activation (100 = the best builder for that muscle). Referenced by
// exercise NAME so it resolves to whatever is in the catalog (incl. custom edits).

export interface Activation { name: string; percent: number }

export const muscleActivation: Record<string, Activation[]> = {
  shoulders: [
    { name: 'Overhead press', percent: 100 },
    { name: 'Dumbbell shoulder press', percent: 96 },
    { name: 'Arnold press', percent: 94 },
    { name: 'Lateral raise', percent: 88 },
    { name: 'Cable lateral raise', percent: 86 },
    { name: 'Upright row', percent: 82 },
    { name: 'Front raise', percent: 80 },
    { name: 'Reverse pec deck', percent: 74 }
  ],
  chest: [
    { name: 'Barbell bench press', percent: 100 },
    { name: 'Incline barbell press', percent: 95 },
    { name: 'Incline dumbbell press', percent: 93 },
    { name: 'Decline bench press', percent: 90 },
    { name: 'Machine chest press', percent: 88 },
    { name: 'Chest dip', percent: 85 },
    { name: 'Dumbbell fly', percent: 82 },
    { name: 'Pec deck fly', percent: 80 },
    { name: 'Cable crossover', percent: 78 },
    { name: 'Push-up', percent: 70 }
  ],
  back: [
    { name: 'Pull-up', percent: 100 },
    { name: 'Barbell row', percent: 96 },
    { name: 'Lat pulldown', percent: 94 },
    { name: 'T-bar row', percent: 93 },
    { name: 'Seated cable row', percent: 90 },
    { name: 'One-arm dumbbell row', percent: 88 },
    { name: 'Chin-up', percent: 86 },
    { name: 'Deadlift', percent: 84 },
    { name: 'Straight-arm pulldown', percent: 78 },
    { name: 'Back extension', percent: 60 }
  ],
  biceps: [
    { name: 'Barbell curl', percent: 100 },
    { name: 'EZ-bar curl', percent: 97 },
    { name: 'Preacher curl', percent: 95 },
    { name: 'Dumbbell curl', percent: 92 },
    { name: 'Concentration curl', percent: 90 },
    { name: 'Cable bicep curl', percent: 88 },
    { name: 'Hammer curl', percent: 82 },
    { name: 'Chin-up', percent: 72 },
    { name: 'Pull-up', percent: 60 }
  ],
  triceps: [
    { name: 'Close-grip bench press', percent: 100 },
    { name: 'Skull crusher', percent: 96 },
    { name: 'Overhead triceps extension', percent: 94 },
    { name: 'Triceps pushdown', percent: 90 },
    { name: 'Bench dip', percent: 85 },
    { name: 'Chest dip', percent: 78 }
  ],
  forearms: [
    { name: 'Deadlift', percent: 100 },
    { name: 'Barbell row', percent: 86 },
    { name: 'Pull-up', percent: 84 },
    { name: 'Hammer curl', percent: 82 },
    { name: 'Chin-up', percent: 80 }
  ],
  core: [
    { name: 'Hanging leg raise', percent: 100 },
    { name: 'Ab wheel rollout', percent: 96 },
    { name: 'Cable crunch', percent: 94 },
    { name: 'Lying leg raise', percent: 90 },
    { name: 'Bicycle crunch', percent: 88 },
    { name: 'Crunch', percent: 85 },
    { name: 'Plank', percent: 82 },
    { name: 'Russian twist', percent: 80 },
    { name: 'Side plank', percent: 78 },
    { name: 'Mountain climber', percent: 70 }
  ],
  glutes: [
    { name: 'Hip thrust', percent: 100 },
    { name: 'Barbell squat', percent: 92 },
    { name: 'Bulgarian split squat', percent: 90 },
    { name: 'Romanian deadlift', percent: 88 },
    { name: 'Walking lunge', percent: 85 },
    { name: 'Step-up', percent: 82 },
    { name: 'Deadlift', percent: 80 },
    { name: 'Goblet squat', percent: 75 }
  ],
  quads: [
    { name: 'Barbell squat', percent: 100 },
    { name: 'Front squat', percent: 96 },
    { name: 'Hack squat', percent: 94 },
    { name: 'Leg press', percent: 92 },
    { name: 'Leg extension', percent: 88 },
    { name: 'Bulgarian split squat', percent: 86 },
    { name: 'Walking lunge', percent: 84 },
    { name: 'Goblet squat', percent: 82 },
    { name: 'Step-up', percent: 78 }
  ],
  hamstrings: [
    { name: 'Romanian deadlift', percent: 100 },
    { name: 'Lying leg curl', percent: 96 },
    { name: 'Seated leg curl', percent: 94 },
    { name: 'Deadlift', percent: 88 },
    { name: 'Bulgarian split squat', percent: 72 },
    { name: 'Walking lunge', percent: 68 }
  ],
  calves: [
    { name: 'Standing calf raise', percent: 100 },
    { name: 'Seated calf raise', percent: 95 },
    { name: 'Jump rope', percent: 65 }
  ]
};
