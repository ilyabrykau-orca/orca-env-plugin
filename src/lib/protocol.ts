interface HookOutput {
  hookSpecificOutput: {
    hookEventName: string;
    permissionDecision?: "allow" | "deny";
    permissionDecisionReason?: string;
    updatedInput?: unknown;
    additionalContext?: string;
  };
  additional_context?: string;
}

export function deny(reason: string): string {
  const out: HookOutput = {
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: reason,
    },
  };
  return JSON.stringify(out);
}

export function allow(reason: string, updatedInput?: unknown): string {
  const out: HookOutput = {
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
      permissionDecisionReason: reason,
      ...(updatedInput !== undefined && { updatedInput }),
    },
  };
  return JSON.stringify(out);
}

export function rewriteNoAllow(updatedInput: unknown): string {
  const out: HookOutput = {
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      updatedInput,
    },
  };
  return JSON.stringify(out);
}

export function sessionContext(ctx: string): string {
  return JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      additionalContext: ctx,
    },
  });
}
