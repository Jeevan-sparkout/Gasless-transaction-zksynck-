import axios from "axios";
import * as fs from "fs";
import * as path from "path";
import dotenv from "dotenv";

dotenv.config();

async function main() {
    const contractAddress = "0x9932F47c8d14b144A22b5A2ba929648f0Ffc95B5";
    const apiKey = process.env.API;
    const apiUrl = "https://block-explorer-api.sepolia.zksync.dev/api";

    if (!apiKey) {
        throw new Error("API key not found in .env");
    }

    const sourcePath = path.join(__dirname, "../contracts/MyERC20Token_flat.sol");
    const sourceCode = fs.readFileSync(sourcePath, "utf8");

    const verificationData = {
        module: "contract",
        action: "verifysourcecode",
        contractaddress: contractAddress,
        sourceCode: {
            language: "Solidity",
            settings: {
                optimizer: {
                    enabled: true,
                    runs: 200
                },
                outputSelection: {
                    "*": {
                        "*": ["abi", "evm.bytecode", "evm.deployedBytecode", "evm.methodIdentifiers", "metadata", "devdoc", "userdoc", "storageLayout", "evm.gasEstimates"]
                    }
                }
            },
            sources: {
                "contracts/MyERC20Token.sol": {
                    content: sourceCode
                }
            }
        },
        codeformat: "solidity-standard-json-input",
        contractname: "contracts/MyERC20Token.sol:MyERC20Token",
        compilerversion: "0.8.30",
        zksolcVersion: "v1.5.15",
        optimizationUsed: "1",
        runs: 200,
        constructorArguements: "0x", // Empty constructor
    };

    console.log("Submitting verification request to zkSync API...");
    
    try {
        const response = await axios.post(apiUrl, verificationData);
        console.log("Response:", JSON.stringify(response.data, null, 2));
        
        if (response.data.status === "1") {
            console.log("Verification request submitted successfully. ID:", response.data.result);
        } else {
            console.error("Verification submission failed:", response.data.result);
        }
    } catch (error: any) {
        console.error("Error submitting verification:", error.message);
        if (error.response) {
            console.error("API Response Error:", error.response.data);
        }
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
