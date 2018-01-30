import * as path from 'path';
import * as getPort from "get-port";
import BN = require('bn.js');
import { networkConfigurations } from "./NetworkConfigurations";

export class Configuration {
    public readonly httpProviderHost: string;
    public readonly httpProviderPort: number;
    public readonly gasPrice: BN;
    public readonly privateKey: string;
    public readonly contractSourceRoot: string;
    public readonly contractOutputPath: string;
    public readonly abiOutputPath: string;
    public readonly augurjsRepoPath: string;
    public readonly contractAddressesOutputPath: string;
    public readonly contractInterfacesOutputPath: string;
    public readonly uploadBlockNumbersOutputPath: string;
    public readonly controllerAddress: string|undefined;
    public readonly createGenesisUniverse: boolean;
    public readonly isProduction: boolean;
    public readonly useNormalTime: boolean;
    public readonly networkName: string|null;
    public readonly enableSdb: boolean;

    public constructor(host: string, port: number, gasPrice: BN, privateKey: string, contractSourceRoot: string, contractOutputRoot: string, artifactOutputRoot: string, controllerAddress: string|undefined, createGenesisUniverse: boolean=true, isProduction: boolean=false, useNormalTime: boolean=true, networkName: string|null=null, enableSdb: boolean=false) {
        this.httpProviderHost = host;
        this.httpProviderPort = port;
        this.gasPrice = gasPrice;
        this.privateKey = privateKey;
        this.contractSourceRoot = contractSourceRoot;
        this.contractOutputPath = path.join(contractOutputRoot, 'contracts.json');
        this.abiOutputPath = path.join(contractOutputRoot, 'abi.json');
        this.contractAddressesOutputPath = path.join(artifactOutputRoot, 'addresses.json');
        this.contractInterfacesOutputPath = path.join(contractSourceRoot, '../libraries', 'ContractInterfaces.ts');
        this.uploadBlockNumbersOutputPath = path.join(artifactOutputRoot, 'upload-block-numbers.json');
        this.augurjsRepoPath = path.join(contractOutputRoot, '../augur.js');
        this.controllerAddress = controllerAddress;
        this.createGenesisUniverse = createGenesisUniverse;
        this.isProduction = isProduction;
        this.useNormalTime = isProduction || useNormalTime;
        this.networkName = networkName;
        this.enableSdb = enableSdb;
    }

    private static createWithHost(host: string, port: number, gasPrice: BN, privateKey: string, isProduction: boolean=false, useNormalTime: boolean=true, networkName: string|null=null): Configuration {
        const contractSourceRoot = path.join(__dirname, "../../source/contracts/");
        const contractOutputRoot = (typeof process.env.CONTRACT_OUTPUT_ROOT === "undefined") ? path.join(__dirname, "../../output/contracts/") : path.normalize(<string> process.env.CONTRACT_OUTPUT_ROOT);
        const artifactOutputRoot = (typeof process.env.ARTIFACT_OUTPUT_ROOT === "undefined") ? path.join(__dirname, "../../output/contracts/") : path.normalize(<string> process.env.ARTIFACT_OUTPUT_ROOT);
        const controllerAddress = process.env.AUGUR_CONTROLLER_ADDRESS;
        const createGenesisUniverse = (typeof process.env.CREATE_GENESIS_UNIVERSE === "undefined") ? true : process.env.CREATE_GENESIS_UNIVERSE === "true";
        useNormalTime = (typeof process.env.USE_NORMAL_TIME === "string") ? process.env.USE_NORMAL_TIME === "true" : useNormalTime
        const enableSdb = (typeof process.env.ENABLE_SOLIDITY_DEBUG === "undefined") ? false : process.env.ENABLE_SOLIDITY_DEBUG === "true";

        return new Configuration(host, port, gasPrice, privateKey, contractSourceRoot, contractOutputRoot, artifactOutputRoot, controllerAddress, createGenesisUniverse, isProduction, useNormalTime, networkName, enableSdb);
    }

    public static create = async (isProduction: boolean=false, useNormalTime: boolean=true): Promise<Configuration> => {
        const host = (typeof process.env.ETHEREUM_HOST === "undefined") ? "localhost" : process.env.ETHEREUM_HOST!;
        const port = (typeof process.env.ETHEREUM_PORT === "undefined") ? await getPort() : parseInt(process.env.ETHEREUM_PORT || "0");
        const gasPrice = ((typeof process.env.ETHEREUM_GAS_PRICE_IN_NANOETH === "undefined") ? new BN(20) : new BN(process.env.ETHEREUM_GAS_PRICE_IN_NANOETH!)).mul(new BN(1000000000));
        const privateKey = process.env.ETHEREUM_PRIVATE_KEY || '0xbaadf00dbaadf00dbaadf00dbaadf00dbaadf00dbaadf00dbaadf00dbaadf00d';
        useNormalTime = (typeof process.env.USE_NORMAL_TIME === "string") ? process.env.USE_NORMAL_TIME === "true" : useNormalTime

        return Configuration.createWithHost(host, port, gasPrice, privateKey, isProduction, useNormalTime);
    }

    public static network = (networkName: string, useNormalTime: boolean=true):Configuration => {
        const network = networkConfigurations[networkName];
        if (network === undefined || network === null) throw new Error(`Network configuration ${networkName} not found`);
        if (network.privateKey === undefined || network.privateKey === null) throw new Error(`Network configuration for ${networkName} has no private key available. Check that this key is in the environment ${networkName.toUpperCase()}_PRIVATE_KEY`);
        useNormalTime = (typeof process.env.USE_NORMAL_TIME === "string") ? process.env.USE_NORMAL_TIME === "true" : useNormalTime

        return Configuration.createWithHost(network.host, network.port, network.gasPrice, network.privateKey, network.isProduction, useNormalTime, networkName);
    }
}
