import { ethers, ignition } from "hardhat";
import {
    AutomationPool,
    AutomationRegistry,
    AutomationRegistryFactory,
    FakeERC20,
    IAutomationPool__factory,
    L1GasCalculatorStub,
    MockAutomationTarget,
} from "../typechain-types";
import { WORKER } from "../src/roles";
import { default as MockEnvironmentModule } from "../ignition/modules/mock-environment";
import { AutomationPoolTypes } from "../typechain-types/contracts/pool/IAutomationPool";
import { keccak256 } from "ethers";

const BATCH_EXECUTION_ID = ethers.id(
    "BatchExecution(bytes32,address,address,uint8,uint256,uint256,uint256,uint256,uint256,uint256,uint256)",
);

const WORK_ITEM_EXECUTION_ID = ethers.id(
    "WorkItemExecution(bytes32,address,address,uint256,uint8,bytes,uint256,uint256)",
);

const POOL_WORK_PERFORMED_ID = ethers.id(
    "PoolWorkPerformed(uint256,address,address,uint256,uint256,uint256,uint256,uint256,uint256,uint256)",
);

const EXECUTION_RESULT = {
    SUCCESS: 0,
    FAILURE: 1,
};

const OFFCHAIN_CHECK_DATA_HANDLING = {
    NIL: 0,
    IGNORE: 1,
    PREPEND: 2,
    APPEND: 3,
    REPLACE: 4,
};

const CHECK_WORK_SOURCE = {
    NIL: 0,
    FUNCTION_CALL: 1,
};

const CHECK_WORK_CALL_RESULT_INTERPRETATION = {
    NIL: 0,
    SUCCESS: 1,
    FAILURE: 2,
    ACI: 3,
};

const EXECUTION_DATA_HANDLING = {
    NIL: 0,
    NONE: 1,
    CHECK_RESULT_DATA_ONLY: 2,
    EXECUTION_DATA_ONLY: 3,
    CHECK_DATA_ONLY: 4,
    RAW_CHECK_DATA_ONLY: 5,
    ACI: 6,
};

const CHECK_UPKEEP_SELECTOR = ethers.id("checkUpkeep(bytes)").slice(0, 10);
const PERFORM_UPKEEP_SELECTOR = ethers.id("performUpkeep(bytes)").slice(0, 10);

const AbiCoder = ethers.AbiCoder;

async function main() {
    console.log("Deploying mock environment");

    const {
        registryFactory,
        registry,
        pool,
        target,
        billingToken,
        l1GasCalculatorStub,
    }: {
        registryFactory: AutomationRegistryFactory;
        registry: AutomationRegistry;
        pool: AutomationPool;
        target: MockAutomationTarget;
        billingToken: FakeERC20;
        l1GasCalculatorStub: L1GasCalculatorStub;
    } = (await ignition.deploy(MockEnvironmentModule)) as any;

    const targetAddress = await target.getAddress();
    const batchId = AbiCoder.defaultAbiCoder().encode(["address"], [targetAddress]);

    console.log("Deployed mock environment");

    console.log("Setting L1 gas calculator");

    const gasConfig = await registry.getGasConfig();

    await registry.setGasConfig({
        gasPriceOracle: gasConfig.gasPriceOracle,
        gasPricePremium: gasConfig.gasPricePremium,
        gasOverhead: gasConfig.gasOverhead,
        checkGasLimit: 1_000_000n,
        executionGasLimit: 1_000_000n,
        minBalance: ethers.parseEther("1"),
        workFee: 100,
        l1GasCalculator: l1GasCalculatorStub.target,
    });

    console.log("Set L1 gas calculator");

    await l1GasCalculatorStub.setGasFee(ethers.parseUnits("0.01", "ether"));

    const [admin, worker] = await ethers.getSigners();
    const adminAddress = await admin.getAddress();

    // Grant the WORKER role to the worker
    await registry.grantRole(WORKER, worker.getAddress());

    // Order work
    const w1 = ethers.ZeroAddress;
    const w1Encoded = AbiCoder.defaultAbiCoder().encode(["address"], [w1]);
    await target.orderNewWork(w1Encoded, false, false, false, false);
    console.log("Work ordered: " + w1Encoded);

    const poolInterface = IAutomationPool__factory.connect(await pool.getAddress(), admin);

    // Pay for capacity
    await billingToken.mint(adminAddress, 100_000n);
    await billingToken.transfer(pool.getAddress(), 10_000n);
    await poolInterface.setBillingBatchCapacity(1);

    // Add the target to the pool
    const checkGasLimit = 1000000;
    const executionGasLimit = 1000000;
    const workItem1 = {
        checkGasLimit: checkGasLimit,
        executionGasLimit: executionGasLimit,
        value: 0,
        condition: "0x",
        checkData: AbiCoder.defaultAbiCoder().encode(["bytes"], [w1Encoded]),
        executionData: "0x",
    };
    const checkParams: AutomationPoolTypes.WorkCheckParamsStruct = {
        target: targetAddress,
        selector: CHECK_UPKEEP_SELECTOR,
        source: CHECK_WORK_SOURCE.FUNCTION_CALL,
        offchainCheckDataHandling: OFFCHAIN_CHECK_DATA_HANDLING.IGNORE,
        callResultInterpretation: CHECK_WORK_CALL_RESULT_INTERPRETATION.ACI,
        executionDataHandling: EXECUTION_DATA_HANDLING.ACI,
        maxGasLimit: checkGasLimit,
        executionDelay: 0,
        workItems: [workItem1],
    };
    const execParams: AutomationPoolTypes.WorkExecutionParamsStruct = {
        target: targetAddress,
        selector: PERFORM_UPKEEP_SELECTOR,
        flags: 0x1,
        maxGasLimit: executionGasLimit,
        maxGasPrice: ethers.parseUnits("1000", "gwei"),
        minBatchSize: 1,
        maxBatchSize: 100,
    };
    const workDefinition: AutomationPoolTypes.WorkDefinitionStruct = {
        checkParams: checkParams,
        executionParams: execParams,
    };
    console.log("Registering batch...");
    await poolInterface.registerBatch(batchId, workDefinition);
    console.log("Batch added to pool: " + (await target.getAddress()));

    // Add funds to the pool
    const gasFunds = ethers.parseEther("1");
    await pool.depositGasFunds({ value: gasFunds });
    console.log("Funds added to pool: " + ethers.formatEther(gasFunds) + " ETH");

    const offchainData: AutomationPoolTypes.OffchainDataProvisionStruct = {
        itemsData: [],
    };

    // Worker - Check for work
    const performWork: any = await pool.connect(worker).checkWork.staticCallResult(batchId, 0, offchainData);

    // Print JSON.stringify of performWork, providing a function to convert bigint to string
    console.log("Perform work: " + JSON.stringify(performWork, (_, v) => (typeof v === "bigint" ? v.toString() : v)));

    const amountOfWork = Number(performWork.workRequiredCount);

    if (amountOfWork > 0) {
        console.log("Work available: " + amountOfWork + " items");

        // Assemble work data
        const workData: AutomationPoolTypes.PerformWorkItemStruct[] = [];

        for (let i = 0; i < performWork.checkedWorkItems.length; ++i) {
            const checkedWorkItem: AutomationPoolTypes.CheckedWorkItemStructOutput = performWork.checkedWorkItems[i];

            if (!checkedWorkItem.needsExecution) {
                continue;
            }

            const workItem: AutomationPoolTypes.WorkItemStructOutput =
                performWork.workDefinition.checkParams.workItems[Number(checkedWorkItem.index)];

            workData.push({
                maxGasLimit: workItem.executionGasLimit,
                value: workItem.value,
                aggregateCount: 1,
                flags: 0,
                index: checkedWorkItem.index,
                itemHash: checkedWorkItem.itemHash,
                trigger: checkedWorkItem.checkCallData,
                executionData: checkedWorkItem.executionData,
            });
        }

        const startingBalance = await worker.provider.getBalance(worker.getAddress());
        console.log("Work data: ", workData);

        // Worker - Do work
        const doWorkTx = await pool.connect(worker).performWork(batchId, 0, workData);
        const workReceipt = await doWorkTx.wait();
        if (!workReceipt) {
            throw new Error("No work receipt");
        }

        console.log("Total gas used: \t" + workReceipt.gasUsed);

        // Get the BatchExecution event
        const batchExecutionEvent = workReceipt.logs?.find((event) => event.topics[0] === BATCH_EXECUTION_ID);
        if (!batchExecutionEvent) {
            throw new Error("No BatchExecution event");
        }
        const eventData = AbiCoder.defaultAbiCoder().decode(
            ["uint8", "uint256", "uint256", "uint256", "uint256", "uint256", "uint256", "uint256"],
            batchExecutionEvent.data,
        );

        const gasUsed = eventData[4];
        const gasCompensationPaid = eventData[5];
        const gasDebt = eventData[6];
        console.log("Gas used: \t\t" + gasUsed);
        console.log("Gas paid: \t\t" + ethers.formatEther(workReceipt.gasPrice * workReceipt.gasUsed) + " ETH");
        console.log("Gas compensation paid: \t" + ethers.formatEther(gasCompensationPaid) + " ETH");
        console.log("Gas debt: \t\t" + ethers.formatEther(gasDebt) + " ETH");

        console.log("Starting balance: \t" + ethers.formatEther(startingBalance) + " ETH");
        const endingBalance = await worker.provider.getBalance(worker.getAddress());
        console.log("Ending balance: \t" + ethers.formatEther(endingBalance) + " ETH");

        // Report token balances

        const factoryTokenBalance = await billingToken.balanceOf(registryFactory.getAddress());
        const registryTokenBalance = await billingToken.balanceOf(registry.getAddress());
        const poolTokenBalance = await billingToken.balanceOf(pool.getAddress());

        console.log("\nToken balances:");

        console.log("  Factory token balance: \t" + ethers.formatEther(factoryTokenBalance) + " FT");
        console.log("  Registry token balance: \t" + ethers.formatEther(registryTokenBalance) + " FT");
        console.log("  Pool token balance: \t\t" + ethers.formatEther(poolTokenBalance) + " FT");

        // Report native balances

        const factoryBalance = await worker.provider.getBalance(registryFactory.getAddress());
        const registryBalance = await worker.provider.getBalance(registry.getAddress());
        const poolBalance = await worker.provider.getBalance(pool.getAddress());

        console.log("\nNative balances:");

        console.log("  Factory balance: \t\t" + ethers.formatEther(factoryBalance) + " ETH");
        console.log("  Registry balance: \t\t" + ethers.formatEther(registryBalance) + " ETH");
        console.log("  Pool balance: \t\t" + ethers.formatEther(poolBalance) + " ETH");

        // Find work item executions
        const workItemExecutionEvents = workReceipt.logs?.filter((event) => event.topics[0] === WORK_ITEM_EXECUTION_ID);

        console.log("\nWork item executions: " + workItemExecutionEvents?.length);

        // Report failures
        const failureEvents = workItemExecutionEvents.filter((event) => {
            const decoded = AbiCoder.defaultAbiCoder().decode(
                ["uint256", "uint8", "bytes", "uint256", "uint256"],
                event.data,
            );

            return decoded[1] === BigInt(EXECUTION_RESULT.FAILURE);
        });

        console.log(" - Failures: " + failureEvents.length);

        // Report successes
        const successEvents = workItemExecutionEvents.filter((event) => {
            const decoded = AbiCoder.defaultAbiCoder().decode(
                ["uint256", "uint8", "bytes", "uint256", "uint256"],
                event.data,
            );

            return decoded[1] === BigInt(EXECUTION_RESULT.SUCCESS);
        });

        console.log(" - Successes: " + successEvents.length);

        // Find registry PoolWorkPerformed events
        const poolWorkPerformedEvents = workReceipt.logs?.filter((event) => event.topics[0] === POOL_WORK_PERFORMED_ID);

        console.log("\nPool work performed events: " + poolWorkPerformedEvents?.length);
    } else {
        console.log("No work needed");
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
