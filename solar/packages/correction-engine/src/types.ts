export type GradingMode =
  | "KEYWORDS"
  | "NUMERIC_RANGE"
  | "BOOLEAN"
  | "EXACT"
  | "SCALE";

export interface KeywordRule {
  keyword: string;
  weight: number;
  alternatives?: string[];
  mandatory?: boolean;
}

export interface NumericRule {
  target: number;
  tolerance: number;
  weight?: number;
  strict?: boolean;
}

export interface ScaleRule {
  min: number;
  max: number;
  ideal?: number;
}

export interface ItemMetadata {
  numericRule?: NumericRule;
  scaleRule?: ScaleRule;
  rubricCriteria?: RubricCriterion[];
  autoFeedback?: {
    excellent?: string;
    good?: string;
    average?: string;
    poor?: string;
  };
}

export interface RubricCriterion {
  id: string;
  label: string;
  description?: string;
  maxScore: number;
  keywords?: KeywordRule[];
}

export interface CorrectionItemDefinition {
  id: string;
  prompt: string;
  gradingMode: GradingMode;
  keywords?: KeywordRule[];
  expectedAnswer?: string;
  metadata?: ItemMetadata;
  maxScore: number;
  weight?: number;
}

export interface SubmissionAnswer {
  itemId: string;
  answer: string;
}

export interface ItemResult {
  itemId: string;
  score: number;
  maxScore: number;
  status: "AUTO_GRADED" | "NEEDS_REVIEW";
  feedback?: string;
  details?: Record<string, unknown>;
}

export interface SubmissionResult {
  submissionId: string;
  overallScore: number;
  maxScore: number;
  normalizedScore: number;
  status: "AUTO_GRADED" | "IN_REVIEW";
  items: ItemResult[];
}

