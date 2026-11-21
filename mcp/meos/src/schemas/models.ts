/**
 * The JSON shapes MeOS already stores in `app_state`. These are structural
 * mirrors of the Swift models, deliberately lenient: every field the app treats
 * as optional is optional here too, and unknown fields are preserved on write.
 */

export interface Profile {
  name: string;
  dob: string;
  age?: number | null;
  bloodGroup: string;
  relationship: string;
  phone: string;
  email: string;
  city: string;
  hometown: string;
  education: string;
  heightCm?: number | null;
  photoBase64: string;
  role: string;
  work: string;
  website: string;
  instagram: string;
  github: string;
  goalsShort: string[];
  goalsMid: string[];
  goalsLong: string[];
  achievements: Milestone[];
  healthNotes: string;
  about: string;
  habits: string[];
  [key: string]: unknown;
}

export interface Milestone {
  id: string;
  year: string;
  title: string;
  note: string;
}

export interface Note {
  id: string;
  createdAt: string;
  updatedAt: string;
  title: string;
  body: string;
  pinned: boolean;
  locked: boolean;
  content?: unknown;
  [key: string]: unknown;
}

export interface FocusItem {
  id: string;
  text: string;
  done: boolean;
  mins?: number | null;
  spent: number;
}

export interface DayPlan {
  todos: FocusItem[];
  habits: Record<string, boolean>;
  [key: string]: unknown;
}

export interface EventTag {
  id: string;
  name: string;
  symbol: string;
  colorHex: string;
  builtIn: boolean;
}

export interface EventMedia {
  id: string;
  kind: 'image' | 'video';
  data?: string;
  poster?: string | null;
  r2Key?: string | null;
  posterKey?: string | null;
}

export interface Recurrence {
  unit: 'none' | 'daily' | 'weekly' | 'monthly' | 'yearly';
  interval: number;
  until?: string | null;
}

export interface EventItem {
  id: string;
  date: string;
  title: string;
  tagIDs: string[];
  note: string;
  media: EventMedia[];
  special: boolean;
  time?: string | null;
  recurrence: Recurrence;
  reminders: string[];
  category?: string;
  done?: boolean;
  [key: string]: unknown;
}

export interface FitnessDay {
  weightKg?: number | null;
  calories?: number | null;
  proteinG?: number | null;
  waterMl?: number | null;
  steps?: number | null;
  note?: string | null;
  hailed?: number[] | null;
}

export interface FitnessProfile {
  goal: 'cut' | 'maintain' | 'bulk';
  sex: 'male' | 'female';
  activity: 'sedentary' | 'light' | 'moderate' | 'active' | 'athlete';
  targetWeightKg?: number | null;
  calorieTargetKcal?: number | null;
  proteinTargetG?: number | null;
  waterTargetMl?: number | null;
  stepsTarget?: number | null;
  stepsStretch?: number | null;
  [key: string]: unknown;
}

export interface PlanExercise {
  id: string;
  exerciseId: string;
  sets: number;
  reps: number;
  [key: string]: unknown;
}

export interface SetLog {
  id: string;
  weightKg?: number | null;
  reps: number;
  done: boolean;
}

export interface ExerciseLog {
  id: string;
  exerciseId: string;
  group: string;
  sets: SetLog[];
  note?: string | null;
  [key: string]: unknown;
}

export interface WorkoutDayLog {
  done: boolean;
  skipped: boolean;
  items?: PlanExercise[] | null;
  dayId?: string | null;
  programId?: string | null;
  title?: string | null;
  entries?: ExerciseLog[] | null;
  restOverride: boolean;
  [key: string]: unknown;
}

export interface Exercise {
  id: string;
  name: string;
  category: string;
  equipment: string;
  primary: string;
  muscles: string[];
  gifId?: string | null;
  weighted: boolean;
  isDefault: boolean;
  muscleGroup?: string | null;
  [key: string]: unknown;
}

export interface TrainingState {
  customExercises: Exercise[];
  weekPlan: Record<string, unknown>;
  dayLog: Record<string, WorkoutDayLog>;
  programs: WorkoutProgram[];
  activeProgramId?: string | null;
  migratedWeekPlan: boolean;
  [key: string]: unknown;
}

export interface WorkoutProgram {
  id: string;
  name: string;
  notes?: string | null;
  goal?: string | null;
  days: unknown[];
  anchorDate?: string | null;
  createdAt: string;
  [key: string]: unknown;
}

export interface MemoryItem {
  id: string;
  content: string;
  category: string;
  importance: number;
  source: 'stated' | 'extracted' | 'manual';
  confidence: number;
  createdAt: string;
  updatedAt: string;
  pinned: boolean;
  [key: string]: unknown;
}

export interface MemoryState {
  items: MemoryItem[];
}

export interface TrashEntry {
  id: string;
  itemID: string;
  kind: string;
  title: string;
  subtitle: string;
  deletedAt: string;
  payload: string;
  context?: string | null;
  mediaKeys: string[];
}

export interface BelongingItem {
  id: string;
  name: string;
  kind: string;
  pricePaise: number;
  boughtOn: string;
  lifeDays: number;
  note: string;
  retired: boolean;
  photoBase64: string;
  categoryID: string;
  link: string;
  [key: string]: unknown;
}

export interface BelongingCategory {
  id: string;
  name: string;
  icon: string;
  tintHex: number;
  defaultLifeDays: number;
}

export interface BelongingsState {
  items: BelongingItem[];
  salaryPaise: number;
  categories: BelongingCategory[];
  [key: string]: unknown;
}

export interface FoldBank {
  name: string;
  last4: string;
  balance: number;
}

export interface FoldSpend {
  category: string;
  amount: number;
}

export interface FoldData {
  asOf: string;
  currency: string;
  netWorth: number;
  liquid: number;
  investments: number;
  debt: number;
  spentThisMonth: number;
  stocksValue: number;
  mfValue: number;
  changeValue: number;
  changePercent: number;
  changeLabel: string;
  history: number[];
  banks: FoldBank[];
  topSpends: FoldSpend[];
  [key: string]: unknown;
}

export interface WatchItem {
  id: string;
  url: string;
  videoId: string;
  title: string;
  channel: string;
  thumbUrl: string;
  addedAt: string;
  category: string;
  takeaway: string;
  watched: boolean;
  [key: string]: unknown;
}

export interface TaskModeState {
  on: boolean;
  since: string;
  device: string;
}

export const STATE_KEYS = {
  profile: 'meos.profile',
  notes: 'meos.notes',
  days: 'meos.days',
  events: 'meos.events',
  eventTags: 'meos.eventTags',
  fitness: 'meos.fitness',
  fitnessProfile: 'meos.fitnessProfile',
  nutrition: 'meos.nutrition',
  training: 'meos.training',
  memory: 'meos.memory',
  belongings: 'meos.belongings',
  fold: 'meos.fold',
  trash: 'meos.trash',
  watch: 'meos.watch',
  scans: 'meos.scans',
  taskMode: 'meos.taskMode',
  weekly: 'meos.weekly',
  activity: 'meos.activity',
  appearance: 'meos.appearance',
  sixPack: 'meos.sixPack',
  chat: 'meos.chat',
  crypto: 'meos.crypto'
} as const;

export const DEFAULT_PROFILE: Profile = {
  name: '',
  dob: '',
  bloodGroup: '',
  relationship: '',
  phone: '',
  email: '',
  city: '',
  hometown: '',
  education: '',
  photoBase64: '',
  role: '',
  work: '',
  website: '',
  instagram: '',
  github: '',
  goalsShort: [],
  goalsMid: [],
  goalsLong: [],
  achievements: [],
  healthNotes: '',
  about: '',
  habits: ['Gym', 'Read', 'No junk', 'Sleep']
};

export const DEFAULT_FITNESS_PROFILE: FitnessProfile = {
  goal: 'maintain',
  sex: 'male',
  activity: 'moderate'
};

export const DEFAULT_BELONGINGS: BelongingsState = { items: [], salaryPaise: 4_000_000, categories: [] };
