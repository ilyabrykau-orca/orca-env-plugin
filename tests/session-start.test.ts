import { describe, it, expect } from "bun:test";
import { handleSessionStart } from "../src/session-start.ts";

describe("handleSessionStart", () => {
  it("detects orca-env-plugin project", async () => {
    const result = await handleSessionStart({ cwd: "/Users/test/src/orca-env-plugin" });
    expect(result.appendContext).toContain("project='orca-env-plugin'");
    expect(result.appendContext).toContain("mcp__serena__activate_project");
  });

  it("detects orca-runtime-sensor project", async () => {
    const result = await handleSessionStart({ cwd: "/Users/test/src/orca-runtime-sensor/pkg" });
    expect(result.appendContext).toContain("project='orca-runtime-sensor'");
  });

  it("detects orca-cloud-platform project", async () => {
    const result = await handleSessionStart({ cwd: "/Users/test/src/orca-cloud-platform" });
    expect(result.appendContext).toContain("project='orca-cloud-platform'");
  });

  it("detects orca-sensor project", async () => {
    const result = await handleSessionStart({ cwd: "/Users/test/src/orca-sensor" });
    expect(result.appendContext).toContain("project='orca-sensor'");
  });

  it("detects helm-charts project", async () => {
    const result = await handleSessionStart({ cwd: "/Users/test/src/helm-charts" });
    expect(result.appendContext).toContain("project='helm-charts'");
  });

  it("detects grafana-provisioning project", async () => {
    const result = await handleSessionStart({ cwd: "/Users/test/src/grafana-provisioning" });
    expect(result.appendContext).toContain("project='grafana-provisioning'");
  });

  it("detects orca monorepo for /src/orca paths", async () => {
    const result = await handleSessionStart({ cwd: "/Users/test/src/orca/some/path" });
    expect(result.appendContext).toContain("project='orca'");
  });

  it("detects orca-unified for bare /src", async () => {
    const home = process.env.HOME ?? "";
    const result = await handleSessionStart({ cwd: `${home}/src` });
    expect(result.appendContext).toContain("project='orca-unified'");
  });

  it("returns routing hint for unknown cwd", async () => {
    const result = await handleSessionStart({ cwd: "/tmp/random" });
    expect(result.appendContext).not.toContain("SERENA WORKSPACE");
    expect(result.appendContext).toContain("PREFERRED ROUTING");
  });

  it("returns routing hint for empty cwd", async () => {
    const result = await handleSessionStart({ cwd: "" });
    expect(result.appendContext).toContain("PREFERRED ROUTING");
  });

  it("always includes routing hint", async () => {
    const result = await handleSessionStart({ cwd: "/Users/test/src/orca-env-plugin" });
    expect(result.appendContext).toContain("PREFERRED ROUTING");
    expect(result.appendContext).toContain("CBM");
  });
});
