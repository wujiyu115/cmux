export interface VerificationStep {
  name: string;
  command: string;
  required: boolean;
}

export interface VerificationReport {
  passed: boolean;
  steps: Array<{ name: string; passed: boolean; logPath: string }>;
}

export interface Verifier {
  verify(worktreeDir: string, steps: VerificationStep[]): Promise<VerificationReport>;
}
