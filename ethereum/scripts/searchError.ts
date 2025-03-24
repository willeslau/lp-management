// scripts/listErrorSelectors.ts
import fs from "fs";
import path from "path";
import { ethers, keccak256, toUtf8Bytes } from "ethers";

const error = "0x4712092d000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000002616d000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008408c379a00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002645524332303a207472616e7366657220616d6f756e7420657863656564732062616c616e6365000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

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
