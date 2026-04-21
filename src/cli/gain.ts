import { blockRate, topDenies } from "../lib/audit";

export function runGainCli(): void {
  const rate = blockRate();
  const denies = topDenies(10);

  process.stdout.write("orca-env-plugin audit report\n");
  process.stdout.write("============================\n");
  process.stdout.write(`block rate: ${(rate * 100).toFixed(1)}%\n\n`);
  process.stdout.write("top 10 denies:\n");
  for (const d of denies) {
    process.stdout.write(`  ${d.count.toString().padStart(4)}  ${d.tool.padEnd(10)} ${d.target}\n`);
  }
  process.exit(0);
}
