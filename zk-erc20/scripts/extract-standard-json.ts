import * as fs from "fs";
import * as path from "path";

async function main() {
    const buildInfoDir = path.join(__dirname, "../artifacts-zk/build-info");
    const files = fs.readdirSync(buildInfoDir).filter(f => f.endsWith(".json"));
    
    if (files.length === 0) {
        console.error("No build-info files found. Run 'npx hardhat compile' first.");
        return;
    }

    // Assuming the first (or only) build-info file is the one we want
    const buildInfoPath = path.join(buildInfoDir, files[0]);
    console.log(`Reading build-info from ${buildInfoPath}`);
    
    const buildInfoData = JSON.parse(fs.readFileSync(buildInfoPath, "utf8"));
    
    if (!buildInfoData.input) {
        console.error("No 'input' field found in build-info.");
        return;
    }

    const outputPath = path.join(__dirname, "../standard-json-input-MyERC20.json");
    fs.writeFileSync(outputPath, JSON.stringify(buildInfoData.input, null, 2));
    
    console.log(`Successfully extracted Standard JSON Input to: standard-json-input-MyERC20.json`);
    console.log(`You can now upload this file directly to the zkSync Block Explorer manual verification page.`);
}

main().catch(console.error);
