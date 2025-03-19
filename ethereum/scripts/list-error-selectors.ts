// scripts/listErrorSelectors.ts
import fs from "fs";
import path from "path";
import { keccak256, toUtf8Bytes } from "ethers";

interface ABIInput {
  type: string;
}

interface ABIItem {
  type: string;
  name?: string;
  inputs?: ABIInput[];
}

interface Artifact {
  abi: ABIItem[];
}

function getErrorSelectorsFromABI(abi: ABIItem[]): { signature: string; selector: string }[] {
  const errorEntries = abi.filter(item => item.type === "error");
  return errorEntries.map(err => {
    const inputs = err.inputs ? err.inputs.map(input => input.type).join(",") : "";
    const signature = `${err.name}(${inputs})`;
    const selector = keccak256(toUtf8Bytes(signature)).substring(0, 10); // first 4 bytes
    return { signature, selector };
  });
}

function listErrorSelectors(artifactsDir: string): void {
  const files = fs.readdirSync(artifactsDir);
  for (const file of files) {
    const filePath = path.join(artifactsDir, file);
    const stat = fs.statSync(filePath);
    if (stat.isDirectory()) {
      listErrorSelectors(filePath);
    } else if (file.endsWith(".json")) {
      try {
        const artifactContent = fs.readFileSync(filePath, "utf8");
        const artifact: Artifact = JSON.parse(artifactContent);
        if (artifact.abi) {
          const selectors = getErrorSelectorsFromABI(artifact.abi);
          if (selectors.length > 0) {
            console.log(`Artifact: ${filePath}`);
            selectors.forEach(({ signature, selector }) => {
              console.log(`  ${signature} -> ${selector}`);
            });
          }
        }
      } catch (error) {
        console.error(`Error processing file ${filePath}:`, error);
      }
    }
  }
}

// Adjust this path as needed (this assumes artifacts are in "../artifacts/contracts")
const artifactsPath = path.join(__dirname, "../artifacts/contracts");
listErrorSelectors(artifactsPath);
