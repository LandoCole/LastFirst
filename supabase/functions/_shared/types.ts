// Shared TypeScript interfaces for curator edge functions

export interface CuratorRequest {
  curation_id?: string;
  message: string;
  user_id?: string;
  model?: string;
}

export interface NormalizedLLMResponse {
  content: string;
  toolCalls: ToolCall[];
  stopReason: string;
  usage?: { input_tokens: number; output_tokens: number };
  rawContent?: Record<string, unknown>[];
}

export interface ToolCall {
  id: string;
  name: string;
  input: Record<string, unknown>;
}

export interface StatusMessage {
  type: string;
  plan?: { label: string; description: string }[];
  stepIndex?: number;
  tool?: string;
  message?: string;
  detail?: string;
  finding?: string;
  title?: string;
  // Multi-agent status fields
  agentRole?: string;
  agentTaskId?: string;
  totalAgents?: number;
  completedAgents?: number;
}

export interface Finding {
  source: "library" | "web";
  content_id?: string;
  url?: string;
  title: string;
  author?: string;
  summary?: string;
  relevance_note: string;
  confidence: number; // 0-1
  word_count?: number;
  estimated_read_minutes?: number;
  file_type?: string;
  availability?: string;
  image_url?: string;
}

export interface SubagentConfig {
  role: string;
  query: string;
  userId: string;
  userPreferences?: Finding[];
}

export interface SubagentResult {
  findings: Finding[];
  tokensUsed: number;
}

export interface ClassificationResult {
  complexity: "simple" | "moderate" | "complex";
  subqueries: { role: string; query: string }[];
  reasoning: string;
  needs_clarification?: boolean;
}

export interface ClarificationOption {
  id: string;
  label: string;
  emoji?: string;
}

export interface ClarificationQuestion {
  id: string;
  question: string;
  selection_type: "single" | "multi";
  options: ClarificationOption[];
}

export interface ClarificationResponse {
  __clarification_response: true;
  original_query: string;
  selections: {
    question_id: string;
    question_text: string;
    selected_option_ids: string[];
    selected_labels: string[];
  }[];
}

export type LLMProvider = "anthropic" | "openai" | "google";
