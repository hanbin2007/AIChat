export interface GeminiModelDescriptor {
  id: string;
  family: "gemini-3-pro" | "gemini-3-flash" | "gemini-2.5" | "custom";
  displayName: string;
  capabilities: {
    thinking: boolean;
    search: boolean;
    codeExecution: boolean;
    audio: boolean;
    vision: boolean;
  };
  supportedIntensities: ("fast" | "balanced" | "deep" | "extreme")[];
}

export const DEFAULT_MODELS: GeminiModelDescriptor[] = [
  {
    id: "gemini-3.1-pro-preview",
    family: "gemini-3-pro",
    displayName: "Gemini 3.1 Pro",
    capabilities: { thinking: true, search: true, codeExecution: true, audio: false, vision: true },
    supportedIntensities: ["fast", "balanced", "deep", "extreme"],
  },
  {
    id: "gemini-3-flash-preview",
    family: "gemini-3-flash",
    displayName: "Gemini 3 Flash",
    capabilities: { thinking: true, search: true, codeExecution: true, audio: true, vision: true },
    supportedIntensities: ["fast", "balanced", "deep", "extreme"],
  },
  {
    id: "gemini-2.5-flash",
    family: "gemini-2.5",
    displayName: "Gemini 2.5 Flash",
    capabilities: { thinking: true, search: true, codeExecution: true, audio: true, vision: true },
    supportedIntensities: ["fast", "balanced", "deep", "extreme"],
  },
];
