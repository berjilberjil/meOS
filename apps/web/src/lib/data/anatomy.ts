// Gym-goer's muscle map — top to bottom. Only the muscles worth knowing to train.

export interface Muscle {
  name: string;
  what: string; // plain-language role + why a lifter cares
  train: string; // the go-to movement(s)
}

export interface MuscleGroup {
  id: string;
  name: string;
  icon: string;
  /** Which body view this group reads best on. */
  view: 'front' | 'back';
  /** body-paths.ts muscle slugs that light up for this group. */
  slugs: string[];
  blurb: string;
  muscles: Muscle[];
}

// Ordered head -> toe.
export const muscleGroups: MuscleGroup[] = [
  {
    id: 'shoulders',
    name: 'Shoulders',
    icon: '',
    view: 'front',
    slugs: ['deltoids'],
    blurb: 'The deltoid caps each shoulder in three heads — hit all three for round, wide delts.',
    muscles: [
      { name: 'Anterior deltoid', what: 'Front head — raises the arm forward. Gets heavy work from all pressing.', train: 'Overhead press, front raise' },
      { name: 'Lateral deltoid', what: 'Side head — the one that builds shoulder width and the capped look.', train: 'Lateral raise' },
      { name: 'Posterior deltoid', what: 'Rear head — pulls the arm back. Usually the lagging head; train it directly.', train: 'Reverse fly, face pull' }
    ]
  },
  {
    id: 'chest',
    name: 'Chest',
    icon: '',
    view: 'front',
    slugs: ['chest'],
    blurb: 'The pectorals push. Angle changes which part does the work.',
    muscles: [
      { name: 'Upper chest (clavicular head)', what: 'Top slab of the pec. Built with incline angles — the part most lifters miss.', train: 'Incline bench / incline press' },
      { name: 'Lower & mid chest (sternal head)', what: 'The big fan of the pec that drives flat and decline pressing.', train: 'Flat bench, dips' },
      { name: 'Serratus anterior', what: 'The finger-like muscle on the ribs under the pec — protracts the shoulder blade.', train: 'Push-up plus, cable punch' }
    ]
  },
  {
    id: 'back',
    name: 'Back',
    icon: '',
    view: 'back',
    slugs: ['trapezius', 'upper-back', 'lower-back'],
    blurb: 'The pulling engine. Width comes from lats, thickness from traps and rhomboids.',
    muscles: [
      { name: 'Latissimus dorsi', what: 'The big wing muscle — creates the V-taper and drives every pull-down and row.', train: 'Pull-up, lat pulldown' },
      { name: 'Trapezius', what: 'Diamond from neck to mid-back. Shrugs, sets the shoulder blades, holds posture.', train: 'Shrug, deadlift' },
      { name: 'Rhomboids', what: 'Between the shoulder blades — squeeze them to add mid-back thickness.', train: 'Row, reverse fly' },
      { name: 'Erector spinae', what: 'The lower-back columns that keep the spine braced and upright under load.', train: 'Deadlift, back extension' }
    ]
  },
  {
    id: 'biceps',
    name: 'Biceps',
    icon: '',
    view: 'front',
    slugs: ['biceps'],
    blurb: 'Front of the upper arm — flexes the elbow and turns the forearm.',
    muscles: [
      { name: 'Long head', what: 'Outer bicep — builds the peak. Worked when the elbows sit behind the body.', train: 'Incline curl' },
      { name: 'Short head', what: 'Inner bicep — adds width to the front of the arm.', train: 'Preacher curl, concentration curl' },
      { name: 'Brachialis', what: 'Sits under the bicep — push it up and the whole arm looks thicker.', train: 'Hammer curl' }
    ]
  },
  {
    id: 'triceps',
    name: 'Triceps',
    icon: '',
    view: 'back',
    slugs: ['triceps'],
    blurb: 'Back of the upper arm — two-thirds of arm size. Three heads straighten the elbow.',
    muscles: [
      { name: 'Long head', what: 'Biggest head, runs down the inner arm — trained with overhead work.', train: 'Overhead extension' },
      { name: 'Lateral head', what: 'Outer head — gives the arm its horseshoe shape.', train: 'Pushdown' },
      { name: 'Medial head', what: 'Deep head that works in every press and extension for elbow strength.', train: 'Close-grip press, dips' }
    ]
  },
  {
    id: 'forearms',
    name: 'Forearms',
    icon: '',
    view: 'front',
    slugs: ['forearm'],
    blurb: 'Grip and wrist strength — the base for every heavy pull.',
    muscles: [
      { name: 'Wrist flexors', what: 'Inner forearm — curls the wrist and locks your grip on the bar.', train: 'Wrist curl, dead hang' },
      { name: 'Wrist extensors', what: 'Outer forearm — extends the wrist and balances grip health.', train: 'Reverse wrist curl' },
      { name: 'Brachioradialis', what: 'Thick muscle from forearm to elbow — pops on hammer and reverse curls.', train: 'Hammer / reverse curl' }
    ]
  },
  {
    id: 'core',
    name: 'Core / Abs',
    icon: '',
    view: 'front',
    slugs: ['abs', 'obliques'],
    blurb: 'The midsection braces every lift and shows the six-pack when body fat drops.',
    muscles: [
      { name: 'Rectus abdominis', what: 'The six-pack sheet — flexes the trunk. Visible when lean, not just when trained.', train: 'Crunch, leg raise' },
      { name: 'External obliques', what: 'The sides of the waist — rotate and side-bend the torso.', train: 'Cable twist, side plank' },
      { name: 'Transverse abdominis', what: 'Deep corset muscle — brace it to protect the spine on heavy sets.', train: 'Plank, vacuum' }
    ]
  },
  {
    id: 'glutes',
    name: 'Glutes',
    icon: '',
    view: 'back',
    slugs: ['gluteal'],
    blurb: 'The strongest muscle group — powers every hinge, jump and sprint.',
    muscles: [
      { name: 'Gluteus maximus', what: 'The big driver — extends the hip on squats, deadlifts and thrusts.', train: 'Hip thrust, squat' },
      { name: 'Gluteus medius', what: 'Upper-side glute — stabilises the hip and stops the knee caving in.', train: 'Abduction, lateral walk' },
      { name: 'Gluteus minimus', what: 'Deep hip stabiliser under the medius — keeps the pelvis level.', train: 'Abduction, single-leg work' }
    ]
  },
  {
    id: 'quads',
    name: 'Quadriceps',
    icon: '',
    view: 'front',
    slugs: ['quadriceps'],
    blurb: 'Front of the thigh — four heads that straighten the knee.',
    muscles: [
      { name: 'Rectus femoris', what: 'Runs down the middle — the only quad that also lifts the hip.', train: 'Squat, leg extension' },
      { name: 'Vastus lateralis', what: 'Outer sweep — gives the thigh its width from the side.', train: 'Squat, leg press' },
      { name: 'Vastus medialis', what: 'The teardrop above the inner knee — key for knee health and lockout.', train: 'Leg extension, deep squat' },
      { name: 'Vastus intermedius', what: 'Deep head under the rectus femoris — adds overall quad mass.', train: 'Squat, leg press' }
    ]
  },
  {
    id: 'hamstrings',
    name: 'Hamstrings',
    icon: '',
    view: 'back',
    slugs: ['hamstring'],
    blurb: 'Back of the thigh — bends the knee and extends the hip.',
    muscles: [
      { name: 'Biceps femoris', what: 'Outer hamstring — the part most involved in knee bending.', train: 'Leg curl, RDL' },
      { name: 'Semitendinosus', what: 'Inner hamstring — long and cordy, drives hip extension.', train: 'Romanian deadlift' },
      { name: 'Semimembranosus', what: 'Deep inner hamstring — works with the others on every hinge.', train: 'Good morning, leg curl' }
    ]
  },
  {
    id: 'calves',
    name: 'Calves',
    icon: '',
    view: 'back',
    slugs: ['calves'],
    blurb: 'Lower leg — points the toes and holds you on every step.',
    muscles: [
      { name: 'Gastrocnemius', what: 'The diamond-shaped bulge — trained with the leg straight.', train: 'Standing calf raise' },
      { name: 'Soleus', what: 'Flat muscle underneath — trained with the knee bent, big endurance role.', train: 'Seated calf raise' }
    ]
  }
];
