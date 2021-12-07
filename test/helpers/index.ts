import { Contract, Signer } from "ethers";
import { deployments, ethers } from "hardhat";

export async function deploy<T extends Contract>(
    deploymentName: string,
    { from, args, connect }: { from?: string; args: Array<unknown>; connect?: Signer },
    contractName: string = deploymentName,
): Promise<T> {
    if (from === undefined) {
        const deployer = await ethers.getNamedSigner("deployer");
        from = deployer.address;
    }

    const deployment = await deployments.deploy(deploymentName, {
        from,
        contract: contractName,
        args,
        log: true,
    });

    const instance = await ethers.getContractAt(deploymentName, deployment.address);

    return (connect ? instance.connect(connect) : instance) as T;
}

export async function hardhatFastForward(secondsToIncrease: number): Promise<void> {
    await ethers.provider.send("evm_increaseTime", [secondsToIncrease]);
    await ethers.provider.send("evm_mine", []);
}