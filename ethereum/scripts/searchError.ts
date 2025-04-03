// scripts/listErrorSelectors.ts
import fs from "fs";
import path from "path";
import { ethers, keccak256, toUtf8Bytes } from "ethers";

const error = "0xe75959500000000000000000000000000000000000000000000000000000000000001d600000000000000000000000000000000000000000000509b65be9d19fe57d19f6";

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
          const iface = new ethers.Interface(artifact.abi);

          const errorFragment = iface.getError(error.substring(0, 10));
          if (errorFragment === null) {
            continue;
          }

          console.log(iface.decodeErrorResult(errorFragment, error));
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
